import SwiftUI

struct RootTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OutboxFailureBridge.self) private var failureBridge
    @Environment(TabRouter.self) private var router
    @State private var showFailuresSheet: Bool = false

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            SyncStatusPill(onReviewFailures: { showFailuresSheet = true })
            TabView(selection: $router.selectedTab) {
                Tab("Lots", systemImage: "square.stack.3d.up", value: TabRouter.Tab.lots) {
                    LotsListView()
                }
                Tab("Scan", systemImage: "viewfinder", value: TabRouter.Tab.scan) {
                    ScanShortcutView()
                }
                Tab("Pre-grade", systemImage: "checkmark.seal", value: TabRouter.Tab.preGrade) {
                    gradeTab
                }
                Tab("Movers", systemImage: "chart.line.uptrend.xyaxis", value: TabRouter.Tab.movers) {
                    MoversListView()
                }
                Tab("Grade Gains", systemImage: "arrow.up.forward.square", value: TabRouter.Tab.gradeGains) {
                    GradeGainsListView()
                }
            }
            .tint(AppColor.gold)
            .toolbarBackground(AppColor.ink, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
        }
        .sheet(isPresented: $showFailuresSheet) {
            OutboxFailuresView(
                loader: failureBridge.load,
                onRetry: failureBridge.retry,
                onDiscard: failureBridge.discard,
                onClose: { showFailuresSheet = false }
            )
        }
    }

    /// Force-unwrap is safe: `RootTabView` only renders when the parent
    /// `RootView` has already checked `session.isSignedIn`, which is true
    /// iff `userId` is non-nil.
    @ViewBuilder
    private var gradeTab: some View {
        if let userId = session.userId {
            GradeHistoryView(
                repo: AppRepositories.live().gradeEstimates,
                currentUserId: userId
            )
        } else {
            // Defensive: if RootTabView is ever rendered before sign-in,
            // show a minimal placeholder rather than crashing.
            SlabbedRoot {
                VStack(spacing: Spacing.s) {
                    KickerLabel("Pre-grade")
                    Text("Sign in required").slabRowTitle()
                }
            }
        }
    }
}
