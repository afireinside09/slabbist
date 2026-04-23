import SwiftUI
import SwiftData
import OSLog

/// Destination of the "Scan" tab. Resolves to either the most recent open lot's
/// `BulkScanView` (if one exists) or presents `NewLotSheet` to create one.
struct ScanShortcutView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session

    @State private var viewModel: LotsViewModel?
    @State private var resolvedLot: Lot?
    @State private var showingNewLot = false

    var body: some View {
        NavigationStack {
            SlabbedRoot {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        KickerLabel("Scan")
                        Text("New bulk scan").slabTitle()
                    }
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.top, Spacing.l)

                    VStack(spacing: Spacing.m) {
                        PrimaryGoldButton(
                            title: "Start new lot",
                            systemIcon: "plus",
                            trailingChevron: true,
                            action: { showingNewLot = true }
                        )
                        if let lot = resolvedLot {
                            NavigationLink {
                                BulkScanView(lot: lot)
                            } label: {
                                SlabCard {
                                    HStack {
                                        VStack(alignment: .leading, spacing: Spacing.xs) {
                                            Text("Resume \(lot.name)").slabRowTitle()
                                            Text("Most recent open lot")
                                                .font(SlabFont.sans(size: 12))
                                                .foregroundStyle(AppColor.dim)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(AppColor.dim)
                                    }
                                    .padding(.horizontal, Spacing.l)
                                    .padding(.vertical, Spacing.md)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.xxl)

                    Spacer()
                }
            }
            .sheet(isPresented: $showingNewLot) {
                if let viewModel {
                    NewLotSheet { name in
                        let lot = try viewModel.createLot(name: name)
                        resolvedLot = lot
                    }
                }
            }
            .onAppear {
                bootstrap()
                refresh()
            }
        }
    }

    private func bootstrap() {
        guard viewModel == nil else { return }
        viewModel = LotsViewModel.resolve(context: context, session: session)
    }

    private func refresh() {
        guard let viewModel else { return }
        resolvedLot = (try? viewModel.listOpenLots())?.first
    }
}
