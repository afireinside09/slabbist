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
}

struct LotsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(StoreHydrator.self) private var hydrator

    @State private var showingNewLot = false
    @State private var lots: [Lot] = []
    @State private var path: [LotsRoute] = []
    @State private var viewModel: LotsViewModel?
    @State private var lotPendingDelete: Lot?

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

                        if viewModel == nil {
                            setupStatusCard
                        } else if lots.isEmpty {
                            emptyStateCard
                        } else {
                            openLotsSection
                        }

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
            .confirmationDialog(
                "Delete \(lotPendingDelete?.name ?? "lot")?",
                isPresented: Binding(
                    get: { lotPendingDelete != nil },
                    set: { if !$0 { lotPendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: lotPendingDelete
            ) { lot in
                Button("Delete lot and all slabs", role: .destructive) {
                    do {
                        try viewModel?.deleteLot(lot)
                        refresh()
                    } catch {
                        AppLog.lots.error("delete lot failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: { _ in
                Text("This removes the lot and every slab inside it. This can't be undone.")
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
                    ForEach(lots, id: \.id) { lot in
                        if lot.id != lots.first?.id {
                            SlabCardDivider()
                        }
                        NavigationLink(value: LotsRoute.lot(lot.id)) {
                            row(for: lot)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete lot", systemImage: "trash", role: .destructive) {
                                lotPendingDelete = lot
                            }
                        }
                    }
                }
            }
        }
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
        }
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
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(lot.name).slabRowTitle()
                Text(rowSubtitle(for: lot))
                    .font(SlabFont.mono(size: 12))
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColor.dim)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
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
        viewModel = LotsViewModel.resolve(context: context, session: session)
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
