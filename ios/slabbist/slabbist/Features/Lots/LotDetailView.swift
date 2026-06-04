import SwiftUI
import SwiftData
import OSLog
import Supabase
import Auth

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
    /// Scan whose `ManualPriceSheet` is presented from the inline
    /// `SetPricePill` on a slab row. `.sheet(item:)` so taps land on a
    /// stable target even if the row re-orders between tap and present.
    @State private var manualPriceTarget: Scan?
    /// Surfaced when an offer-state action throws (illegal transition, an
    /// expired session, or a failed local write) so a tap can't silently
    /// no-op — the user sees what happened instead of a dead button.
    @State private var actionError: String?
    @Binding private var path: [LotsRoute]

    init(lot: Lot, path: Binding<[LotsRoute]>) {
        self.lot = lot
        self._path = path
        let lotId = lot.id
        _scans = Query(
            filter: #Predicate<Scan> { $0.lotId == lotId },
            sort: [SortDescriptor(\Scan.createdAt, order: .reverse)]
        )
        // Snapshots aren't filtered server-side — there's no FK from snapshot
        // to scan. We join in memory by (identityId, gradingService, grade).
        // Sorted newest-first so `latestSnapshot(for:)` picks the freshest.
        //
        // Bounded to the last 30 days so a long-running store doesn't load
        // every snapshot it ever recorded on every LotDetailView appear —
        // pre-fix this was O(allSnapshots × scansInLot) per render. The
        // window matches the existing "comp data is recoverable from a
        // cheap re-fetch" policy documented in ModelContainer.swift's
        // recovery comment: scans whose latest snapshot is >30 days old
        // are stale enough that the auto-recovery hatch in C2 will
        // re-fetch them when the user opens the lot or scan detail.
        let snapshotCutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        _snapshots = Query(
            filter: #Predicate<GradedMarketSnapshot> { $0.fetchedAt >= snapshotCutoff },
            sort: [SortDescriptor(\GradedMarketSnapshot.fetchedAt, order: .reverse)]
        )
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
        .toolbarBackground(AppColor.ink, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert(
            "Couldn't complete that",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            ),
            actions: { Button("OK", role: .cancel) { actionError = nil } },
            message: { Text(actionError ?? "") }
        )
        .sheet(isPresented: $showingVendorPicker) {
            VendorPicker(
                storeId: lot.storeId,
                onPick: { vendor in
                    runAction { try offerRepository().attachVendor(vendor, to: lot) }
                },
                onCreate: { id, name, method, value, notes in
                    try vendorsRepository().upsert(id: id, displayName: name, contactMethod: method, contactValue: value, notes: notes)
                }
            )
        }
        .sheet(isPresented: $showingMarginSheet) {
            LotMarginSheet(
                currentPct: lot.marginPctSnapshot ?? 0.7,
                usesLadder: lot.marginPctSnapshot == nil,
                storeId: lot.storeId,
                onSelectLotMargin: { pct in
                    runAction { try offerRepository().setLotMargin(pct, on: lot) }
                },
                onSelectLadder: {
                    runAction { try offerRepository().clearLotMargin(on: lot) }
                }
            )
        }
        .sheet(item: $manualPriceTarget) { scan in
            ManualPriceSheet(initialCents: scan.vendorAskCents) { cents in
                try setVendorAskCents(cents, on: scan)
            }
        }
        .task(id: lot.id) {
            recoverLegacyFetchingRows()
        }
    }

    /// P1.5 — On first appear of a lot whose scans pre-date the C2
    /// migration, every `.fetching` row with `compFetchStartedAt == nil`
    /// would otherwise read as stale and surface a negative-tinted
    /// Retry pill simultaneously (alarm fatigue, not recovery).
    ///
    /// Instead, walk those rows once and re-fire `CompFetchService.fetch`
    /// for each — the service de-dupes by `(identityId, service, grade)`
    /// so duplicates collapse to one in-flight call per slab tier. Any
    /// row whose comp doesn't come back (e.g. genuine outage) will
    /// stamp `compFetchStartedAt = Date()` on entry; if the new fetch
    /// also stalls past 90s the row reverts to surfacing a Retry pill —
    /// at that point the operator should see *one* pill, not a wall.
    ///
    /// Mirrors the `autoTriggerCompFetchIfNeeded` recovery hatch the
    /// scan-detail screen already uses.
    private func recoverLegacyFetchingRows() {
        let legacy = scans.filter { scan in
            scan.compFetchState == CompFetchState.fetching.rawValue &&
            scan.compFetchStartedAt == nil &&
            scan.gradedCardIdentityId != nil &&
            scan.grade != nil
        }
        guard !legacy.isEmpty else { return }
        let repo = CompRepository.live()
        for scan in legacy {
            CompFetchService.fetch(scan: scan, repository: repo, context: context, kicker: kicker)
        }
    }

    /// Persist a per-scan manual price from the inline `SetPricePill`'s
    /// sheet. Routes through `LotsViewModel.setOfferCents` so the same
    /// outbox patch + invariants the detail screen uses also drive the
    /// row-level affordance. Throws `LotsViewModel.ResolveError` when no
    /// store has synced yet so `ManualPriceSheet` can render the error
    /// inline instead of swallowing the tap (P0.2).
    private func setVendorAskCents(_ cents: Int64?, on scan: Scan) throws {
        let viewModel = try LotsViewModel.requireResolve(context: context, kicker: kicker, session: session)
        try viewModel.setOfferCents(scan: scan, cents: cents)
    }

    /// Re-fire the comp fetch for a scan whose persisted state is stuck
    /// on `.fetching` because the originating task died with the app.
    /// Shares `CompFetchService`'s in-flight de-dup with every other
    /// comp fetch in the process.
    private func retryCompFetch(scan: Scan) {
        CompFetchService.fetch(scan: scan, repository: CompRepository.live(), context: context, kicker: kicker)
    }

    // MARK: - Repository helpers

    /// Runs an offer-state mutation and surfaces any throw to the user via
    /// the action-error alert, replacing the old `try?` swallows that turned
    /// an illegal transition or expired session into a silent dead tap.
    private func runAction(_ work: () throws -> Void) {
        do { try work() } catch { actionError = error.localizedDescription }
    }

    /// Builds an `OfferUseCase` scoped to this lot's store + the current
    /// signed-in user. Built lazily on every call rather than cached so
    /// the SwiftData context and session UUIDs always reflect "now"; the
    /// type is cheap to construct.
    private func offerRepository() throws -> OfferUseCase {
        OfferUseCase(
            context: context,
            kicker: kicker,
            currentStoreId: lot.storeId,
            currentUserId: try session.requireUserId()
        )
    }

    private func vendorsRepository() -> VendorsUseCase {
        VendorsUseCase(context: context, kicker: kicker, currentStoreId: lot.storeId)
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
        guard let m = lot.marginPctSnapshot else { return "Auto (ladder)" }
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
                    .foregroundStyle(lotIsFrozen ? AppColor.dim : AppColor.text)
                    .accessibilityIdentifier("lot-vendor-attach")
                    .disabled(lotIsFrozen)
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
        }
    }

    /// Margin display + adjust affordance. The snapshot here is the value
    /// `OfferUseCase.setLotMargin` writes; the store-default seeded onto
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
                    .foregroundStyle(lotIsFrozen ? AppColor.dim : AppColor.text)
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
                    Image(systemName: "lock.fill").foregroundStyle(AppColor.text)
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
    /// `OfferUseCase` stays the single source of truth — this view just
    /// renders the legal next move.
    @ViewBuilder
    private var actionBar: some View {
        let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
        switch state {
        case .drafting:
            EmptyView()
        case .priced:
            PrimaryGoldButton(title: "Create Offer") {
                do {
                    try offerRepository().sendToOffer(lot)
                    path.append(LotsRoute.offerReview(lot.id))
                } catch {
                    actionError = error.localizedDescription
                }
            }
            .accessibilityIdentifier("create-offer")
        case .presented, .accepted:
            NavigationLink(value: LotsRoute.offerReview(lot.id)) {
                Text("Resume offer")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("resume-offer")
        case .declined:
            Button("Re-open as new offer") {
                runAction { try offerRepository().reopenDeclined(lot) }
            }
            .accessibilityIdentifier("reopen-declined")
        case .paid:
            // Terminal — surface the receipt link in place of an actionable
            // CTA. `frozenBanner` already mirrors this affordance at the top
            // of the screen; keeping it in the action bar means the receipt
            // is always reachable without scrolling once a long slab list
            // pushes the banner off-screen. Paid lots intentionally have no
            // re-open path: an operator must void the transaction first.
            if let txnId = matchingTransactionId() {
                NavigationLink(value: LotsRoute.transaction(txnId)) {
                    Text("View receipt")
                        .font(SlabFont.sans(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.text)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("view-receipt-action")
            }
        case .voided:
            // Voided lots get both affordances: receipt deep-link for audit
            // trail, plus a re-open CTA so an operator who voided in error
            // can take the lot back into pricing. Without the re-open path
            // a voided lot is a dead-end in the UI.
            VStack(spacing: Spacing.m) {
                if let txnId = matchingTransactionId() {
                    NavigationLink(value: LotsRoute.transaction(txnId)) {
                        Text("View receipt")
                            .font(SlabFont.sans(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.text)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("view-receipt-action")
                }
                Button("Re-open lot as new offer") {
                    runAction { try offerRepository().reopenVoided(lot) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.muted)
                .accessibilityIdentifier("reopen-voided")
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
                                        withAnimation(.easeOut(duration: 0.25)) {
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
        withAnimation(.easeOut(duration: 0.25)) {
            scanPendingDelete = nil
        }
    }

    private func confirmDelete(_ scan: Scan) {
        withAnimation(.easeOut(duration: 0.25)) {
            scanPendingDelete = nil
        }
        deleteScan(scan)
    }

    private func rowMenu(for scan: Scan) -> some View {
        Menu {
            Button("Delete slab", systemImage: "trash", role: .destructive) {
                withAnimation(.easeOut(duration: 0.25)) {
                    scanPendingDelete = scan
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(SlabFont.sans(size: 14, weight: .semibold))
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
                trailingValueView(for: scan)
                if let buy = scan.buyPriceCents {
                    Text("Buy \(formattedCents(buy))")
                        .font(SlabFont.mono(size: 11, weight: .semibold))
                        .foregroundStyle(scan.buyPriceOverridden ? AppColor.gold : AppColor.text)
                }
                Image(systemName: "chevron.right")
                    .font(SlabFont.sans(size: 12))
                    .foregroundStyle(AppColor.dim)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    /// Trailing-edge price/state cell on a slab row. Drives the inline
    /// "Set price" pill (F3) and the stale comp-fetch Retry pill (C2)
    /// alongside the existing reconciled / no-state cases. The "Manual"
    /// gold tag from the pre-F3 design is gone — the pencil glyph inside
    /// `SetPricePill`'s hasManual variant carries the same meaning and
    /// removing the gold honors the one-gold-per-screen rule.
    ///
    /// `.hasSnapshot` renders identically to `.hasReconciled` — the user
    /// can't tell them apart, but they're separate cases so legacy-snapshot
    /// rows (validated before reconciliation was plumbed) follow a
    /// grep-able + tested path through the state machine.
    @ViewBuilder
    private func trailingValueView(for scan: Scan) -> some View {
        switch resolveState(for: scan) {
        case .hasReconciled(let cents), .hasSnapshot(let cents):
            Text(formattedCents(cents))
                .font(SlabFont.mono(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.text)
        case .hasManual(let cents):
            SetPricePill(priceCents: cents) { manualPriceTarget = scan }
                .accessibilityLabel("Manual price \(formattedCents(cents)). Tap to edit.")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("edit-price-pill-\(scan.certNumber)")
        case .hasManualWithReconciled(let manualCents, _):
            // P1.3: the user typed a manual price and a comp later
            // landed. Lot total uses the reconciled value
            // (`aggregateCents` on the state); the row keeps showing
            // the manual pill so the operator can see their input
            // wasn't silently shadowed.
            SetPricePill(priceCents: manualCents) { manualPriceTarget = scan }
                .accessibilityLabel("Manual price \(formattedCents(manualCents)). Tap to edit.")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("edit-price-pill-\(scan.certNumber)")
        case .needsPrice:
            SetPricePill(priceCents: nil) { manualPriceTarget = scan }
                .accessibilityLabel("Set manual price for \(scan.grader.rawValue) \(scan.certNumber)")
                .accessibilityHint("Opens the price entry sheet")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("set-price-pill-\(scan.certNumber)")
        case .staleFetching:
            Button {
                retryCompFetch(scan: scan)
            } label: {
                RetryPill()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry comp fetch for \(scan.grader.rawValue) \(scan.certNumber)")
            .accessibilityHint("Tries the comp fetch again")
            .accessibilityIdentifier("comp-retry-\(scan.certNumber)")
        case .fetching, .failed, .idle:
            EmptyView()
        }
    }

    /// Single resolver shared by the row body, the aggregate strip, and
    /// the legacy first-launch auto-retry path. Threads the latest
    /// snapshot in so `.hasSnapshot` can pick up legacy rows whose comp
    /// fetch persisted before `reconciledHeadlinePriceCents` was plumbed.
    private func resolveState(for scan: Scan) -> ScanRowTrailingState {
        ScanRowTrailingState.resolve(for: scan, snapshot: latestSnapshot(for: scan))
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

    /// Per-scan resolved states for the lot's aggregate strip. Computed
    /// once and reused by `aggregateValueCents` and `aggregateValueDetail`
    /// so the resolver runs N times per body invocation, not 2N+ — and so
    /// the header reads the **same** state the row body renders (P0.1:
    /// pre-fix the two consumers used different resolvers and could drift).
    private var resolvedRowStates: [ScanRowTrailingState] {
        scans.map { resolveState(for: $0) }
    }

    private var aggregateValueCents: Int64 {
        resolvedRowStates.compactMap(\.aggregateCents).reduce(0, +)
    }

    private var aggregateValueDetail: String {
        let states = resolvedRowStates
        let pricedCount = states.compactMap(\.aggregateCents).count
        if pricedCount == 0 { return "No comps yet" }
        let manualCount = states.filter(\.isManualContribution).count
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
        case .pendingValidation:  return AppColor.muted
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
        Currency.displayUSDCompact(cents: cents)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
