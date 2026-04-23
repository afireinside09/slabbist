import SwiftUI

/// 40×40 circular button used for close/back/bell/filter affordances.
struct SecondaryIconButton: View {
    let systemIcon: String
    var accessibilityLabel: String? = nil
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
        .accessibilityLabel(accessibilityLabel ?? systemIcon)
    }
}

#Preview("SecondaryIconButton") {
    HStack(spacing: Spacing.s) {
        SecondaryIconButton(systemIcon: "xmark", action: {})
        SecondaryIconButton(systemIcon: "chevron.left", action: {})
        SecondaryIconButton(systemIcon: "bell", action: {})
        SecondaryIconButton(systemIcon: "line.3.horizontal.decrease", action: {})
    }
    .padding()
    .background(AppColor.ink)
}
