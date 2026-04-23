import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Lots", systemImage: "square.stack.3d.up") {
                LotsListView()
            }
            Tab("Scan", systemImage: "viewfinder") {
                ScanShortcutView()
            }
            Tab("More", systemImage: "ellipsis.circle") {
                SettingsView()
            }
        }
        .tint(AppColor.gold)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
