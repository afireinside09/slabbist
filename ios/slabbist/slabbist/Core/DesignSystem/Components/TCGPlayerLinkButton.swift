import SwiftUI

/// "View on TCGplayer" affiliate button shown on card-detail surfaces. Renders
/// nothing when no link can be built (non-positive product id), so callers can
/// place it unconditionally. `subId` is the originating surface
/// ("graded" | "mover" | "gradegain"), recorded as impact's subId1.
struct TCGPlayerLinkButton: View {
    let productId: Int
    let subId: String

    var body: some View {
        if let url = TCGPlayerAffiliateLink.link(productId: productId, subId: subId) {
            VStack(spacing: Spacing.xs) {
                Link(destination: url) {
                    HStack(spacing: Spacing.xs) {
                        Text("View on TCGplayer")
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(TCGPlayerLinkButtonStyle())
                .accessibilityLabel("View on TCGplayer")
                .accessibilityHint("Opens this card's page on TCGplayer")

                Text("Affiliate link — Slabbist may earn a commission.")
                    .font(SlabFont.sans(size: 11))
                    .foregroundStyle(AppColor.dim)
                    .accessibilityLabel("Affiliate link disclosure. Slabbist may earn a commission.")
            }
        }
    }
}

/// Gold-outlined CTA — distinct from the muted `SecondaryButtonStyle` so the
/// affiliate action reads as a deliberate call to action, while staying within
/// the dark+gold system and meeting the 44pt touch target / AA contrast.
private struct TCGPlayerLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SlabFont.sans(size: 15, weight: .semibold))
            .foregroundStyle(AppColor.gold)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .stroke(AppColor.gold, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

#Preview("TCGPlayerLinkButton") {
    VStack(spacing: Spacing.l) {
        TCGPlayerLinkButton(productId: 517812, subId: "graded")
        TCGPlayerLinkButton(productId: 0, subId: "graded") // renders nothing
    }
    .padding()
    .background(AppColor.ink)
}
