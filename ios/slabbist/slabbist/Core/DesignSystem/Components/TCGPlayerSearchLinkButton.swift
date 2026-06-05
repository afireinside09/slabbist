import SwiftUI

/// "Search on TCGplayer" affiliate button for cards we have no resolved product
/// id for (cameo cards). Builds a search URL via `TCGPlayerAffiliateLink.searchLink`
/// and renders nothing for a blank query. `subId` is recorded as impact's subId1.
struct TCGPlayerSearchLinkButton: View {
    let query: String
    var subId: String = "cameo"

    var body: some View {
        if let url = TCGPlayerAffiliateLink.searchLink(query: query, subId: subId) {
            VStack(spacing: Spacing.xs) {
                Link(destination: url) {
                    HStack(spacing: Spacing.xs) {
                        Text("Search on TCGplayer")
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(TCGPlayerSearchLinkButtonStyle())
                .accessibilityLabel("Search on TCGplayer")
                .accessibilityHint("Opens a TCGplayer search for this card")

                Text("Affiliate link — Slabbist may earn a commission.")
                    .font(SlabFont.sans(size: 11))
                    .foregroundStyle(AppColor.dim)
                    .accessibilityLabel("Affiliate link disclosure. Slabbist may earn a commission.")
            }
        }
    }
}

private struct TCGPlayerSearchLinkButtonStyle: ButtonStyle {
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

#Preview("TCGPlayerSearchLinkButton") {
    VStack(spacing: Spacing.l) {
        TCGPlayerSearchLinkButton(query: "Pokémon March Neo Genesis")
        TCGPlayerSearchLinkButton(query: "   ") // renders nothing
    }
    .padding()
    .background(AppColor.ink)
}
