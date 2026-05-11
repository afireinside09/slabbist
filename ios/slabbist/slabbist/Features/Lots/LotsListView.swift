import SwiftUI
import SwiftData
import OSLog

/// Typed routes for the Lots tab's NavigationStack. Using a single typed
/// path eliminates the prior bug where mixing `.navigationDestination(item:)`
/// for `Lot` with `.navigationDestination(for: Scan.self)` could cause
/// SwiftUI to keep an old `selectedLot` binding active across pops, making
/// it possible to "drill further and further" into the same product.
enum LotsRoute: Hashable {
    case lot(UUID)
    case scan(UUID)
    case offerReview(UUID)
    case transaction(UUID)
    case transactionsList
}

struct LotsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(StoreHydrator.self) private var hydrator
    @Environment(OutboxKicker.self) private var kicker

    @State private var showingNewLot = false
    @State private var lots: [Lot] = []
    @State private var path: [LotsRoute] = []
    @State private var viewModel: LotsViewModel?
    @State private var lotPendingDelete: Lot?

    /// All transactions, newest-first. Filtered to the last 7 days and capped
    /// at 8 rows for the dashboard surface — Plan 3 / Task 12. Storing in a
    /// `@Query` (vs ad-hoc fetch) keeps the section reactive when a new lot
    /// is marked paid in another view.
    @Query(sort: [SortDescriptor(\StoreTransaction.paidAt, order: .reverse)])
    private var allTransactions: [StoreTransaction]

    private var recentTransactions: [StoreTransaction] {
        let since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        return Array(allTransactions.filter { $0.paidAt >= since }.prefix(8))
    }

    var body: some View {
        NavigationStack(path: $path) {
            SlabbedRoot {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        header

                        PrimaryGoldButton(
                            title: "New lot",
                            systemIcon: "plus",
                            trailingChevron: true,
                            isLoading: isHydrating,
                            isEnabled: viewModel != nil
                        ) {
                            showingNewLot = true
                        }
                        .accessibilityIdentifier("new-lot-button")

                        if viewModel == nil {
                            setupStatusCard
                        } else if lots.isEmpty {
                            emptyStateCard
                        } else {
                            openLotsSection
                        }

                        recentTransactionsSection

                        Spacer(minLength: Spacing.xxxl)
                    }
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.xxxl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingNewLot) {
                if let viewModel {
                    NewLotSheet { name in
                        let lot = try viewModel.createLot(name: name)
                        refresh()
                        path = [.lot(lot.id)]
                    }
                }
            }
            .navigationDestination(for: LotsRoute.self) { route in
                routeDestination(route)
            }
            .task(id: session.userId) {
                await prepare()
            }
        }
    }

    private var isHydrating: Bool {
        if case .running = hydrator.state { return true }
        return false
    }

    private var setupStatusCard: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(hydrationStatusTitle)
                    .font(SlabFont.sans(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.text)
                Text(hydrationStatusDetail)
                    .font(SlabFont.sans(size: 12))
                    .foregroundStyle(AppColor.dim)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hydrationStatusTitle: String {
        switch hydrator.state {
        case .failed: return "Couldn't reach your store"
        default: return "Setting up your store…"
        }
    }

    private var hydrationStatusDetail: String {
        switch hydrator.state {
        case .failed(let message): return message
        default: return "Pulling your account from the server. One moment."
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Current lots")
            Text(headerTitle).slabTitle()
            if !lots.isEmpty {
                Text(headerSubtitle)
                    .font(SlabFont.mono(size: 13))
                    .foregroundStyle(AppColor.muted)
            }
        }
    }

    private var headerTitle: String {
        switch lots.count {
        case 0:  return "No open lots"
        case 1:  return "1 open lot"
        default: return "\(lots.count) open lots"
        }
    }

    private var headerSubtitle: String {
        let lastUpdated = lots.map(\.updatedAt).max()
        guard let lastUpdated else { return "" }
        let rel = Self.relative.localizedString(for: lastUpdated, relativeTo: Date())
        return "Updated \(rel)"
    }

    private var openLotsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Open lots")
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(Array(lots.enumerated()), id: \.element.id) { index, lot in
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                NavigationLink(value: LotsRoute.lot(lot.id)) {
                                    row(for: lot)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("lot-row-\(lot.name)")
                                .contextMenu {
                                    Button("Delete lot", systemImage: "trash", role: .destructive) {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                            lotPendingDelete = lot
                                        }
                                    }
                                }
                                rowMenu(for: lot)
                            }
                            if lotPendingDelete?.id == lot.id {
                                // No parent accessibilityIdentifier here:
                                // SwiftUI propagates parent identifiers
                                // down to children, which would mask the
                                // strip's own `inline-delete-cancel` /
                                // `inline-delete-confirm` button IDs that
                                // XCUITests query.
                                InlineDeleteConfirmation(
                                    title: "Delete \(lot.name) and all slabs?",
                                    detail: "This removes the lot and every slab inside it. This can't be undone.",
                                    confirmLabel: "Delete lot",
                                    onCancel: { dismissDeleteConfirmation() },
                                    onConfirm: { confirmDelete(lot) }
                                )
                            }
                        }
                        if index < lots.count - 1 {
                            SlabCardDivider()
                        }
                    }
                }
            }
        }
    }

    private func dismissDeleteConfirmation() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            lotPendingDelete = nil
        }
    }

    private func confirmDelete(_ lot: Lot) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            lotPendingDelete = nil
        }
        do {
            try viewModel?.deleteLot(lot)
            refresh()
        } catch {
            AppLog.lots.error("delete lot failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rowMenu(for lot: Lot) -> some View {
        Menu {
            Button("Delete lot", systemImage: "trash", role: .destructive) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    lotPendingDelete = lot
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
        .accessibilityLabel("Lot actions")
        .accessibilityIdentifier("lot-menu-\(lot.name)")
    }

    /// Resolves a path route to its destination view by looking the entity up
    /// from the SwiftData store. Stable across re-renders because routes
    /// carry only `UUID`s, not @Model references that can mutate.
    @ViewBuilder
    private func routeDestination(_ route: LotsRoute) -> some View {
        switch route {
        case .lot(let lotId):
            if let lot = try? context.fetch(
                FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
            ).first {
                LotDetailView(lot: lot)
            } else {
                missingEntityView(label: "Lot")
            }
        case .scan(let scanId):
            if let scan = try? context.fetch(
                FetchDescriptor<Scan>(predicate: #Predicate { $0.id == scanId })
            ).first {
                ScanDetailView(scan: scan)
            } else {
                missingEntityView(label: "Slab")
            }
        case .offerReview(let lotId):
            if let lot = try? context.fetch(
                FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
            ).first {
                OfferReviewView(lot: lot)
            } else {
                missingEntityView(label: "Lot")
            }
        case .transaction(let txnId):
            if let txn = try? context.fetch(
                FetchDescriptor<StoreTransaction>(predicate: #Predicate { $0.id == txnId })
            ).first {
                TransactionDetailView(transaction: txn)
            } else {
                missingEntityView(label: "Transaction")
            }
        case .transactionsList:
            TransactionsListView()
        }
    }

    /// Last-7-days transaction list shown beneath open lots. Empty case is a
    /// no-op so the dashboard stays focused for stores that haven't paid a
    /// lot recently. Each row is a typed `NavigationLink` into the same
    /// `LotsRoute` stack so deep-links survive tab switches.
    @ViewBuilder
    private var recentTransactionsSection: some View {
        if !recentTransactions.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    KickerLabel("Recent transactions")
                    Spacer()
                    NavigationLink(value: LotsRoute.transactionsList) {
                        Text("View all")
                            .font(SlabFont.sans(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.gold)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recent-transactions-view-all")
                }
                SlabCard {
                    VStack(spacing: 0) {
                        ForEach(recentTransactions, id: \.id) { txn in
                            if txn.id != recentTransactions.first?.id { SlabCardDivider() }
                            NavigationLink(value: LotsRoute.transaction(txn.id)) {
                                HStack {
                                    Text(txn.vendorNameSnapshot).slabRowTitle()
                                    Spacer()
                                    Text(formatCents(txn.totalBuyCents))
                                        .font(SlabFont.mono(size: 12, weight: .semibold))
                                }
                                .padding(.horizontal, Spacing.l)
                                .padding(.vertical, Spacing.md)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recent-txn-row-\(txn.id.uuidString)")
                        }
                    }
                }
            }
        }
    }

    private func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }

    private func missingEntityView(label: String) -> some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.dim)
            Text("\(label) no longer available")
                .font(SlabFont.sans(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.ink)
    }

    private func row(for lot: Lot) -> some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(lot.name).slabRowTitle()
                Text(rowSubtitle(for: lot))
                    .font(SlabFont.mono(size: 12))
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
            statePill(for: lot)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColor.dim)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Compact workflow-state badge surfaced on each lot row. Mirrors the
    /// `LotOfferState` machine but maps to friendlier copy ("Awaiting" for
    /// `.presented` so the store isn't reminded of jargon mid-shift) and
    /// colour-codes by where in the funnel the lot is — gold for in-flight,
    /// positive for paid, negative for voided, muted for terminal-with-no-go.
    private func statePill(for lot: Lot) -> some View {
        let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
        let label: String
        let color: Color
        switch state {
        case .drafting:  label = "Drafting";  color = AppColor.dim
        case .priced:    label = "Priced";    color = AppColor.gold
        case .presented: label = "Awaiting";  color = AppColor.gold
        case .accepted:  label = "Accepted";  color = AppColor.gold
        case .declined:  label = "Declined";  color = AppColor.muted
        case .paid:      label = "Paid";      color = AppColor.positive
        case .voided:    label = "Voided";    color = AppColor.negative
        }
        return Text(label)
            .font(SlabFont.mono(size: 10, weight: .semibold))
            .tracking(1)
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xxs)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.4), lineWidth: 1))
    }

    private func rowSubtitle(for lot: Lot) -> String {
        Self.relative.localizedString(for: lot.updatedAt, relativeTo: Date())
    }

    private var emptyStateCard: some View {
        FeatureEmptyState(
            systemImage: "square.stack.3d.up",
            title: "No lots yet",
            subtitle: "A lot is a stack of cards you're processing together — a 500-count, a tournament pickup, a buylist haul.",
            steps: [
                "Tap New lot to organize a stack.",
                "Open the Scan tab when you're ready to add slabs.",
                "Each lot shows totals, validation, and live eBay comps.",
            ]
        )
    }

    private func prepare() async {
        guard let userId = session.userId else {
            viewModel = nil
            lots = []
            return
        }
        await hydrator.hydrateIfNeeded(userId: userId)
        viewModel = LotsViewModel.resolve(context: context, kicker: kicker, session: session)
        refresh()
    }

    private func refresh() {
        guard let viewModel else {
            lots = []
            return
        }
        do {
            lots = try viewModel.listOpenLots()
        } catch {
            AppLog.lots.error("listOpenLots failed: \(error.localizedDescription, privacy: .public)")
            lots = []
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
