import SwiftUI
import SwiftData
import OSLog

struct LotsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(StoreHydrator.self) private var hydrator

    @State private var showingNewLot = false
    @State private var lots: [Lot] = []
    @State private var selectedLot: Lot?
    @State private var viewModel: LotsViewModel?

    var body: some View {
        NavigationStack {
            SlabbedRoot {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        header

                        PrimaryGoldButton(
                            title: "New bulk scan",
                            systemIcon: "viewfinder",
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
                        selectedLot = lot
                    }
                }
            }
            .navigationDestination(item: $selectedLot) { lot in
                BulkScanView(lot: lot)
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
                        Button {
                            selectedLot = lot
                        } label: {
                            row(for: lot)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
                "Tap New bulk scan to start a lot.",
                "Photograph each slab's label; cards match automatically.",
                "Open a lot anytime to see comps, totals, and what's left.",
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
