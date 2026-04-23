import SwiftUI

/// Full-width gold-gradient CTA button. Optional leading icon tile + trailing chevron
/// match the mockup's "Scan cards" pattern.
struct PrimaryGoldButton: View {
    let title: String
    var systemIcon: String? = nil
    var trailingChevron: Bool = false
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                if let icon = systemIcon {
                    Circle()
                        .fill(AppColor.ink)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(AppColor.gold)
                        )
                }

                if isLoading {
                    ProgressView().tint(AppColor.ink)
                } else {
                    Text(title)
                        .font(SlabFont.sans(size: 16, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(AppColor.ink)
                        .frame(maxWidth: .infinity, alignment: systemIcon == nil ? .center : .leading)
                }

                if trailingChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.ink)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .frame(height: systemIcon == nil ? 52 : 68)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [AppColor.gold, AppColor.goldDim],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .shadow(color: AppColor.gold.opacity(0.13), radius: 18, y: 14)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .disabled(!isEnabled || isLoading)
    }
}

#Preview("PrimaryGoldButton") {
    VStack(spacing: Spacing.l) {
        PrimaryGoldButton(title: "Continue", action: {})
        PrimaryGoldButton(
            title: "Scan cards",
            systemIcon: "viewfinder",
            trailingChevron: true,
            action: {}
        )
        PrimaryGoldButton(title: "Loading", isLoading: true, action: {})
        PrimaryGoldButton(title: "Disabled", isEnabled: false, action: {})
    }
    .padding()
    .background(AppColor.ink)
}
