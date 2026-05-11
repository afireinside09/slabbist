import SwiftUI
import SwiftData
import OSLog

/// Read-only detail screen for a lot: header, aggregate eBay-comp totals,
/// and the per-scan list with each slab's PSA validation status and latest
/// comp. The camera lives only in the Scan tab — this screen is for review.
struct LotDetailView: View {
    let lot: Lot

    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @Query private var scans: [Scan]
    @Query private var snapshots: [GradedMarketSnapshot]
    @Query private var identities: [GradedCardIdentity]
    @State private var scanPendingDelete: Scan?
    @State private var showingVendorPicker = false
    @State private var showingMarginSheet = false

    init(lot: Lot) {
        self.lot = lot
        let lotId = lot.id
        _scans = Query(
            filter: #Predicate<Scan> { $0.lotId == lotId },
            sort: [SortDescriptor(\Scan.createdAt, order: .reverse)]
        )
        // Snapshots aren't filtered server-side — there's no FK from snapshot
        // to scan. We join in memory by (identityId, gradingService, grade).
        // Sorted newest-first so `latestSnapshot(for:)` picks the freshest.
        _snapshots = Query(sort: [SortDescriptor(\GradedMarketSnapshot.fetchedAt, order: .reverse)])
        // Identities are unbounded but small (one row per unique slab the
        // user has ever scanned). Joined in-memory by `gradedCardIdentityId`.
        _identities = Query()
    }

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    frozenBanner
                    aggregateStrip
                    vendorStrip
                    marginRow
                    if scans.isEmpty {
                        emptyHint
                    } else {
                        slabsSection
                    }
                    actionBar
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationTitle(lot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingVendorPicker) {
            VendorPicker(
                storeId: lot.storeId,
                onPick: { vendor in
                    try? offerRepository().attachVendor(vendor, to: lot)
                },
                onCreate: { id, name, method, value, notes in
                    try vendorsRepository().upsert(id: id, displayName: name, contactMethod: method, contactValue: value, notes: notes)
                }
            )
        }
        .sheet(isPresented: $showingMarginSheet) {
            MarginPickerSheet(
                currentPct: lot.marginPctSnapshot ?? 0.6,
                onSelect: { pct in
                    try? offerRepository().setLotMargin(pct, on: lot)
                }
            )
        }
    }

    // MARK: - Repository helpers

    /// Builds an `OfferRepository` scoped to this lot's store + the current
    /// signed-in user. Built lazily on every call rather than cached so
    /// the SwiftData context and session UUIDs always reflect "now"; the
    /// type is cheap to construct.
    private func offerRepository() -> OfferRepository {
        OfferRepository(
            context: context,
            kicker: kicker,
            currentStoreId: lot.storeId,
            currentUserId: session.userId ?? UUID()
        )
    }

    private func vendorsRepository() -> VendorsRepository {
        VendorsRepository(context: context, kicker: kicker, currentStoreId: lot.storeId)
    }

    /// Fallback when the lot has a `vendorId` but no name-snapshot yet —
    /// happens for lots whose vendor was attached before the snapshot was
    /// being persisted, or in the race between attach + sync.
    private func lookupVendorName() -> String? {
        guard let vid = lot.vendorId else { return nil }
        return try? context.fetch(
            FetchDescriptor<Vendor>(predicate: #Predicate { $0.id == vid })
        ).first?.displayName
    }

    private var formattedMargin: String {
        guard let m = lot.marginPctSnapshot else { return "—" }
        return "\(Int((m * 100).rounded()))% of comp"
    }

    private func deleteScan(_ scan: Scan) {
        guard let viewModel = LotsViewModel.resolve(context: context, kicker: kicker, session: session) else {
            AppLog.scans.error("delete scan: no LotsViewModel — user signed out?")
            return
        }
        do {
            try viewModel.deleteScan(scan)
        } catch {
            AppLog.scans.error("delete scan failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Lot")
            Text(lot.name)
                .slabTitle()
                .lineLimit(2)
            Text(headerSubtitle)
                .font(SlabFont.mono(size: 12))
                .foregroundStyle(AppColor.muted)
        }
    }

    private var headerSubtitle: String {
        let total = scans.count
        let validated = scans.filter { $0.status == .validated }.count
        let scanCopy = total == 1 ? "slab" : "slabs"
        return "\(total) \(scanCopy) • \(validated) validated"
    }

    private var aggregateStrip: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HeroValueBlock(
                    kicker: "Estimated",
                    cents: aggregateValueCents,
                    caption: aggregateValueDetail,
                    size: 54
                )
                SlabCardDivider()
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel("Latest comp")
                    Spacer()
                    Text(latestCompLabel)
                        .font(SlabFont.mono(size: 13, weight: .medium))
                        .foregroundStyle(latestComp == nil ? AppColor.dim : AppColor.text)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.l)
        }
    }

    private var latestCompLabel: String {
        guard let date = latestComp else { return "Awaiting first lookup" }
        return Self.relative.localizedString(for: date, relativeTo: Date())
    }

    /// Row that surfaces the lot's attached vendor (or invites attaching one).
    /// Reads from the snapshot first so a vendor rename after the offer was
    /// priced doesn't silently rewrite this lot's header copy — falls back to
    /// a live lookup for lots that were attached before snapshotting landed.
    private var vendorStrip: some View {
        SlabCard {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    KickerLabel("Vendor")
                    Text(lot.vendorNameSnapshot ?? lookupVendorName() ?? "No vendor attached")
                        .slabRowTitle()
                }
                Spacer()
                Button(lot.vendorId == nil ? "Attach" : "Change") { showingVendorPicker = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(lotIsFrozen ? AppColor.dim : AppColor.gold)
                    .accessibilityIdentifier("lot-vendor-attach")
                    .disabled(lotIsFrozen)
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
        }
    }

    /// Margin display + adjust affordance. The snapshot here is the value
    /// `OfferRepository.setLotMargin` writes; the store-default seeded onto
    /// a fresh lot via `snapshotDefaultMargin` shows here too until the user
    /// adjusts it manually.
    private var marginRow: some View {
        SlabCard {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    KickerLabel("Margin")
                    Text(formattedMargin).font(SlabFont.mono(size: 14))
                }
                Spacer()
                Button("Adjust") { showingMarginSheet = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(lotIsFrozen ? AppColor.dim : AppColor.gold)
                    .accessibilityIdentifier("lot-margin-adjust")
                    .disabled(lotIsFrozen)
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
        }
    }

    /// True when the lot has reached a terminal offer state (paid or voided).
    /// Hides editing affordances and surfaces the "Frozen" banner — the
    /// underlying transaction snapshot must stay immutable once written.
    private var lotIsFrozen: Bool {
        let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
        return state == .paid || state == .voided
    }

    /// Newest transaction id associated with this lot. Used to deep-link the
    /// "View receipt" CTA on the frozen banner + action bar. Returns `nil`
    /// (CTA hidden) when the row hasn't synced down yet — the banner still
    /// renders so the lock state is communicated immediately.
    private func matchingTransactionId() -> UUID? {
        let lotId = lot.id
        var desc = FetchDescriptor<StoreTransaction>(
            predicate: #Predicate<StoreTransaction> { $0.lotId == lotId },
            sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
        )
        desc.fetchLimit = 1
        return (try? context.fetch(desc).first)?.id
    }

    /// Top-of-page lock banner shown when the lot is in a terminal state.
    /// Pairs a state-coloured label with a "View receipt" deep-link so the
    /// operator can jump from the frozen lot directly into the underlying
    /// transaction row without hunting for it via the recent-transactions
    /// section.
    @ViewBuilder
    private var frozenBanner: some View {
        let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
        if state == .paid || state == .voided {
            SlabCard {
                HStack {
                    Image(systemName: "lock.fill").foregroundStyle(AppColor.gold)
                    Text(state == .paid ? "Frozen — paid" : "Frozen — voided")
                        .font(SlabFont.mono(size: 12, weight: .semibold))
                        .tracking(1)
                    Spacer()
                    if let txnId = matchingTransactionId() {
                        NavigationLink(value: LotsRoute.transaction(txnId)) {
                            Text("View receipt")
                                .font(SlabFont.sans(size: 13, weight: .semibold))
                                .foregroundStyle(AppColor.gold)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("view-receipt")
                    }
                }
                .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
            }
            .accessibilityIdentifier("lot-frozen-banner")
        }
    }

    /// Bottom action row driven entirely by `LotOfferState`. Each case maps
    /// to exactly one button (or no button), so the state machine in
    /// `OfferRepository` stays the single source of truth — this view just
    /// renders the legal next move.
    @ViewBuilder
    private var actionBar: some View {
        let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
        switch state {
        case .drafting:
            EmptyView()
        case .priced:
            PrimaryGoldButton(title: "Send to offer") {
                try? offerRepository().sendToOffer(lot)
            }
            .accessibilityIdentifier("send-to-offer")
        case .presented, .accepted:
            NavigationLink("Resume offer", value: LotsRoute.offerReview(lot.id))
                .accessibilityIdentifier("resume-offer")
        case .declined:
            Button("Re-open as new offer") { try? offerRepository().reopenDeclined(lot) }
                .accessibilityIdentifier("reopen-declined")
        case .paid, .voided:
            // Terminal — surface the receipt link in place of an actionable
            // CTA. `frozenBanner` already mirrors this affordance at the top
            // of the screen; keeping it in the action bar means the receipt
            // is always reachable without scrolling once a long slab list
            // pushes the banner off-screen.
            if let txnId = matchingTransactionId() {
                NavigationLink(value: LotsRoute.transaction(txnId)) {
                    Text("View receipt")
                        .font(SlabFont.sans(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.gold)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("view-receipt-action")
            }
        }
    }

    private var slabsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Slabs")
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(scans, id: \.id) { scan in
                        if scan.id != scans.first?.id {
                            SlabCardDivider()
                        }
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                NavigationLink(value: LotsRoute.scan(scan.id)) {
                                    slabRow(for: scan)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("scan-row-\(scan.certNumber)")
                                .contextMenu {
                                    Button("Delete slab", systemImage: "trash", role: .destructive) {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                            scanPendingDelete = scan
                                        }
                                    }
                                }
                                rowMenu(for: scan)
                            }
                            if scanPendingDelete?.id == scan.id {
                                // No parent accessibilityIdentifier here:
                                // SwiftUI propagates parent identifiers
                                // down to children, which would mask the
                                // strip's own `inline-delete-cancel` /
                                // `inline-delete-confirm` button IDs that
                                // XCUITests query.
                                InlineDeleteConfirmation(
                                    title: "Delete this slab?",
                                    detail: "Removes \(scan.grader.rawValue) \(scan.certNumber) from this lot. The eBay comp cache stays around in case you re-scan.",
                                    confirmLabel: "Delete slab",
                                    onCancel: { dismissDeleteConfirmation() },
                                    onConfirm: { confirmDelete(scan) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func dismissDeleteConfirmation() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            scanPendingDelete = nil
        }
    }

    private func confirmDelete(_ scan: Scan) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            scanPendingDelete = nil
        }
        deleteScan(scan)
    }

    private func rowMenu(for scan: Scan) -> some View {
        Menu {
            Button("Delete slab", systemImage: "trash", role: .destructive) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    scanPendingDelete = scan
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.dim)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Slab actions")
        .accessibilityIdentifier("scan-menu-\(scan.certNumber)")
    }

    private func slabRow(for scan: Scan) -> some View {
        let identity = identity(for: scan)
        let trailing = trailingValue(for: scan)
        return HStack(alignment: .center, spacing: Spacing.m) {
            Circle()
                .fill(statusColor(for: scan))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(rowTitle(for: scan, identity: identity))
                    .slabRowTitle()
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(secondaryLine(for: scan, identity: identity))
                    .font(SlabFont.mono(size: 11))
                    .foregroundStyle(AppColor.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                if let trailing {
                    Text(formattedCents(trailing.cents))
                        .font(SlabFont.mono(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.text)
                    if trailing.isManual {
                        Text("Manual")
                            .font(SlabFont.mono(size: 9, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(AppColor.gold)
                    }
                }
                if let buy = scan.buyPriceCents {
                    Text("Buy \(formattedCents(buy))")
                        .font(SlabFont.mono(size: 11, weight: .semibold))
                        .foregroundStyle(scan.buyPriceOverridden ? AppColor.gold : AppColor.text)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColor.dim)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    /// Resolves the price shown on the trailing edge of a slab row.
    /// Mirrors the comp-card hero by reading `scan.reconciledHeadlinePriceCents`
    /// — the server-reconciled value that respects the PPT/Poketrace
    /// reconciliation rule (e.g. "poketrace-preferred" when sale count is
    /// high enough). Falls back to a per-source snapshot for legacy scans
    /// persisted before reconciliation was plumbed, and finally to the
    /// user's manual price.
    private func trailingValue(for scan: Scan) -> (cents: Int64, isManual: Bool)? {
        if let cents = scan.reconciledHeadlinePriceCents {
            return (cents, false)
        }
        if let snap = latestSnapshot(for: scan), let cents = snap.headlinePriceCents {
            return (cents, false)
        }
        if let manual = scan.vendorAskCents {
            return (manual, true)
        }
        return nil
    }

    /// Lookup helper — joins a scan to its `GradedCardIdentity` row by
    /// the FK that cert-lookup writes when validation succeeds.
    /// `nil` for scans that haven't validated yet (and for legacy
    /// scans that validated before the identity row started being
    /// persisted client-side).
    private func identity(for scan: Scan) -> GradedCardIdentity? {
        guard let id = scan.gradedCardIdentityId else { return nil }
        return identities.first(where: { $0.id == id })
    }

    private func rowTitle(for scan: Scan, identity: GradedCardIdentity?) -> String {
        if let identity {
            // Card name as the row title — matches what the green
            // resolve banner showed at scan time, persisted now.
            if let n = identity.cardNumber, !n.isEmpty {
                return "\(identity.cardName) #\(n)"
            }
            return identity.cardName
        }
        return "\(scan.grader.rawValue) · \(scan.certNumber)"
    }

    private var emptyHint: some View {
        FeatureEmptyState(
            systemImage: "viewfinder",
            title: "No slabs in this lot yet",
            subtitle: "Open the Scan tab when you're ready to add slabs. Cert lookup and eBay comps populate automatically as each slab is scanned.",
            steps: []
        )
    }

    // MARK: - Joins / aggregates

    /// Newest snapshot whose `(identityId, gradingService, grade)` matches the
    /// scan. Returns nil for scans that haven't been validated yet, scans
    /// that failed cert lookup, or scans whose comp fetch hasn't landed.
    private func latestSnapshot(for scan: Scan) -> GradedMarketSnapshot? {
        guard let identityId = scan.gradedCardIdentityId, let grade = scan.grade else { return nil }
        let service = scan.grader.rawValue
        return snapshots.first(where: {
            $0.identityId == identityId && $0.gradingService == service && $0.grade == grade
        })
    }

    private var aggregateValueCents: Int64 {
        scans.compactMap { trailingValue(for: $0)?.cents }.reduce(0, +)
    }

    private var aggregateValueDetail: String {
        let pricedCount = scans.compactMap { trailingValue(for: $0) }.count
        if pricedCount == 0 { return "No comps yet" }
        let manualCount = scans.compactMap { trailingValue(for: $0) }.filter(\.isManual).count
        let suffix = pricedCount == 1 ? "slab" : "slabs"
        if manualCount > 0 {
            return "across \(pricedCount) \(suffix) · \(manualCount) manual"
        }
        return "across \(pricedCount) \(suffix)"
    }

    private var latestComp: Date? {
        scans.compactMap { latestSnapshot(for: $0)?.fetchedAt }.max()
    }

    private func statusColor(for scan: Scan) -> Color {
        switch scan.status {
        case .validated:          return AppColor.positive
        case .pendingValidation:  return AppColor.gold
        case .validationFailed:   return AppColor.negative
        case .manualEntry:        return AppColor.muted
        }
    }

    private func secondaryLine(for scan: Scan, identity: GradedCardIdentity?) -> String {
        switch scan.status {
        case .validated:
            // Lead with set + grader/grade so the user always sees
            // *what* the slab is, not a cert number. Fetched-state
            // signal trails once a snapshot lands.
            let head = primaryDetail(scan: scan, identity: identity)
            if latestSnapshot(for: scan) != nil {
                return "\(head) • comp ready"
            }
            return "\(head) • fetching comp…"
        case .pendingValidation:
            return "Validating cert…"
        case .validationFailed:
            return "Cert not found"
        case .manualEntry:
            return "Manual entry"
        }
    }

    /// Set / grade summary used in the validated-row subtitle. Falls
    /// back to a cert-style line when identity hasn't been persisted
    /// yet (e.g. scans that landed before the identity upsert).
    private func primaryDetail(scan: Scan, identity: GradedCardIdentity?) -> String {
        let gradeLabel = "\(scan.grader.rawValue) \(scan.grade ?? "—")"
        if let identity {
            var parts: [String] = []
            if let year = identity.year { parts.append(String(year)) }
            parts.append(identity.setName)
            if let v = identity.variant, !v.isEmpty { parts.append(v) }
            return "\(parts.joined(separator: " · ")) • \(gradeLabel)"
        }
        return "Grade \(scan.grade ?? "—")"
    }

    private func formattedCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = cents % 100 == 0 ? 0 : 2
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
