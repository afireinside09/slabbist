import SwiftUI

/// Detail page for a single cameo card: the card image (when mapped to a
/// TCGplayer product) plus its metadata and a product-specific affiliate link.
/// Falls back to a search link for cards not yet mapped.
struct CameoCardDetailView: View {
    let card: CameoCardDTO

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if let urlString = card.tcgProduct?.imageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .empty:
                            ProgressView().tint(AppColor.gold).frame(maxWidth: .infinity, minHeight: 280)
                        case .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(card.cardName).slabRowTitle()
                    Text("\(card.setName)\(card.cardNumber.map { " · #\($0)" } ?? "")")
                        .font(SlabFont.mono(size: 13))
                        .foregroundStyle(AppColor.dim)
                    if let notes = card.notes, !notes.isEmpty {
                        Text(notes)
                            .font(SlabFont.sans(size: 12))
                            .foregroundStyle(AppColor.dim)
                    }
                }

                if let productId = card.tcgProduct?.productId, productId > 0 {
                    TCGPlayerLinkButton(productId: productId, subId: "cameo")
                } else {
                    TCGPlayerSearchLinkButton(query: "\(card.cardName) \(card.setName)")
                }
            }
            .padding(Spacing.m)
        }
        .background(AppColor.ink)
        .navigationTitle(card.cardName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
            .fill(AppColor.surface)
            .frame(maxWidth: .infinity, minHeight: 280)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(AppColor.dim)
            )
    }
}
