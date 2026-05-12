import SwiftUI

struct SecondaryButtonStyle: ButtonStyle {
    enum Role { case standard, destructive }
    var role: Role = .standard

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SlabFont.sans(size: 15, weight: .semibold))
            .foregroundStyle(role == .destructive ? AppColor.negative : AppColor.muted)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .stroke(
                        role == .destructive ? AppColor.negative : AppColor.muted,
                        lineWidth: 1
                    )
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

struct SecondaryButton: View {
    let title: String
    var role: SecondaryButtonStyle.Role = .standard
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(SecondaryButtonStyle(role: role))
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.4)
    }
}

#Preview("SecondaryButton") {
    VStack(spacing: Spacing.l) {
        SecondaryButton(title: "Resume offer", action: {})
        SecondaryButton(title: "Bounce back", action: {})
        SecondaryButton(title: "Decline", role: .destructive, action: {})
        SecondaryButton(title: "Disabled", isEnabled: false, action: {})
    }
    .padding()
    .background(AppColor.ink)
}
