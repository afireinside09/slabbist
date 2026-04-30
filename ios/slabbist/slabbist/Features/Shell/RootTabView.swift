import SwiftUI

struct RootTabView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        TabView {
            Tab("Lots", systemImage: "square.stack.3d.up") {
                LotsListView()
            }
            Tab("Scan", systemImage: "viewfinder") {
                ScanShortcutView()
            }
            Tab("Grade", systemImage: "checkmark.seal") {
                gradeTab
            }
            Tab("Movers", systemImage: "chart.line.uptrend.xyaxis") {
                MoversListView()
            }
            Tab("More", systemImage: "ellipsis.circle") {
                SettingsView()
            }
        }
        .tint(AppColor.gold)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
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
                    KickerLabel("Grade")
                    Text("Sign in required").slabRowTitle()
                }
            }
        }
    }
}
