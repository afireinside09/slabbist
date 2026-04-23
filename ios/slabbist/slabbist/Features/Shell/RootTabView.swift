import SwiftUI

struct RootTabView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        TabView {
            LotsListView()
                .tabItem { Label("Lots", systemImage: "square.stack.3d.up") }
            ScanShortcutView()
                .tabItem { Label("Scan", systemImage: "viewfinder") }
            gradeTab
                .tabItem { Label("Grade", systemImage: "checkmark.seal") }
            SettingsView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(AppColor.gold)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
            Text("Sign in required")
                .foregroundStyle(.secondary)
        }
    }
}
