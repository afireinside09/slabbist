import SwiftUI

/// 40×40 circular button used for close/back/bell/filter affordances.
/// `accessibilityLabel` is required — SF Symbol names ("xmark",
/// "line.3.horizontal.decrease") are not human-readable in VoiceOver,
/// so every caller must pass a short spoken label.
struct SecondaryIconButton: View {
    let systemIcon: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemIcon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColor.text)
                .frame(width: 40, height: 40)
                .background(AppColor.elev)
                .clipShape(Circle())
                .overlay(Circle().stroke(AppColor.hairline, lineWidth: 1))
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("SecondaryIconButton") {
    HStack(spacing: Spacing.s) {
        SecondaryIconButton(systemIcon: "xmark", accessibilityLabel: "Close", action: {})
        SecondaryIconButton(systemIcon: "chevron.left", accessibilityLabel: "Back", action: {})
        SecondaryIconButton(systemIcon: "bell", accessibilityLabel: "Notifications", action: {})
        SecondaryIconButton(systemIcon: "line.3.horizontal.decrease", accessibilityLabel: "Filter", action: {})
    }
    .padding()
    .background(AppColor.ink)
}
