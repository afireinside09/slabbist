import SwiftUI

/// Top-trailing gear affordance shown on every primary tab root. Presents
/// Settings as a sheet — Settings is no longer its own tab.
struct SettingsGearButton: View {
    @State private var showSettings = false

    var body: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.gold)
                .frame(width: 44, height: 44, alignment: .center) // ≥44pt tap target
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("settings-gear")
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
