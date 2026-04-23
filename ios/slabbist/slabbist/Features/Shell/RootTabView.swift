import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            LotsListView()
                .tabItem { Label("Lots", systemImage: "square.stack.3d.up") }
            ScanShortcutView()
                .tabItem { Label("Scan", systemImage: "viewfinder") }
            SettingsView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(AppColor.gold)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
