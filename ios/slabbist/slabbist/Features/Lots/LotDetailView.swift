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
    @Query private var scans: [Scan]
    @Query private var snapshots: [GradedMarketSnapshot]
    @Query private var identities: [GradedCardIdentity]
    @State private var scanPendingDelete: Scan?

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
                    aggregateStrip
                    if scans.isEmpty {
                        emptyHint
                    } else {
                        slabsSection
                    }
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
    }

    private func deleteScan(_ scan: Scan) {
        guard let viewModel = LotsViewModel.resolve(context: context, session: session) else {
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
            HStack(alignment: .top, spacing: Spacing.l) {
                aggregateColumn(
                    kicker: "Estimated",
                    value: formattedCents(aggregateValueCents),
                    detail: aggregateValueDetail
                )
                Spacer()
                aggregateColumn(
                    kicker: "Latest comp",
                    value: latestComp.map { Self.relative.localizedString(for: $0, relativeTo: Date()) } ?? "—",
                    detail: latestComp == nil ? "Awaiting first lookup" : "across this lot"
                )
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.md)
        }
    }

    private func aggregateColumn(kicker: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            KickerLabel(kicker)
            Text(value).slabRowTitle()
            Text(detail)
                .font(SlabFont.sans(size: 11))
                .foregroundStyle(AppColor.dim)
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColor.dim)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    /// Resolves the price shown on the trailing edge of a slab row.
    /// Prefers the live PPT comp; falls back to the user's manual price
    /// when no comp exists yet (or PPT returned no_data / failed).
    private func trailingValue(for scan: Scan) -> (cents: Int64, isManual: Bool)? {
        if let snap = latestSnapshot(for: scan), let cents = snap.headlinePriceCents {
            return (cents, false)
        }
        if let manual = scan.offerCents {
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
