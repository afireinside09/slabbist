import SwiftUI
import SwiftData
import OSLog

/// Destination of the "Scan" tab. Resolves to either the most recent open lot's
/// `BulkScanView` (if one exists) or presents `NewLotSheet` to create one.
struct ScanShortcutView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(StoreHydrator.self) private var hydrator

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
                            isLoading: isHydrating,
                            isEnabled: viewModel != nil,
                            action: { showingNewLot = true }
                        )
                        if viewModel == nil {
                            setupStatusCard
                        }
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
                        } else if viewModel != nil {
                            // No open lot to resume — explain what
                            // bulk scanning does so the Start-new-lot
                            // button has clear context above it.
                            FeatureEmptyState(
                                systemImage: "viewfinder",
                                title: "Bulk scan a stack",
                                subtitle: "Slabbist watches your camera and identifies each slab as you flip through them — no manual entry, no per-card taps.",
                                steps: [
                                    "Tap Start new lot to open a fresh session.",
                                    "Hold the camera over each slab's label.",
                                    "Cards land in your Lots tab in real time.",
                                ]
                            )
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
            HStack(spacing: Spacing.m) {
                Image(systemName: statusIcon)
                    .foregroundStyle(AppColor.dim)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(statusTitle)
                        .font(SlabFont.sans(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.text)
                    Text(statusDetail)
                        .font(SlabFont.sans(size: 12))
                        .foregroundStyle(AppColor.dim)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.md)
        }
    }

    private var statusIcon: String {
        switch hydrator.state {
        case .failed: return "exclamationmark.triangle"
        default: return "hourglass"
        }
    }

    private var statusTitle: String {
        switch hydrator.state {
        case .failed: return "Couldn't reach your store"
        default: return "Setting up your store…"
        }
    }

    private var statusDetail: String {
        switch hydrator.state {
        case .failed(let message):
            return message
        default:
            return "Pulling your account from the server. One moment."
        }
    }

    private func prepare() async {
        guard let userId = session.userId else {
            viewModel = nil
            resolvedLot = nil
            return
        }
        await hydrator.hydrateIfNeeded(userId: userId)
        viewModel = LotsViewModel.resolve(context: context, session: session)
        refresh()
    }

    private func refresh() {
        guard let viewModel else {
            resolvedLot = nil
            return
        }
        resolvedLot = (try? viewModel.listOpenLots())?.first
    }
}
