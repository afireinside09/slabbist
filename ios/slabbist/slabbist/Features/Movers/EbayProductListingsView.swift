import SwiftUI

/// Drill-down for the Movers eBay-Listings tab: shows every eBay
/// listing tied to a single Pokémon product variant. Reached by
/// tapping a product card in the eBay tab — the parent already has
/// the listings cached, so this view doesn't fetch anything itself.
struct EbayProductListingsView: View {
    let group: EbayProductGroup

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    hero
                    summary
                    listings
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationTitle(group.productName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            heroImage
            VStack(alignment: .leading, spacing: Spacing.xs) {
                KickerLabel(MoversFormat.variantBadge(group.subTypeName) ?? group.subTypeName)
                Text(group.productName).slabTitle()
                if let set = group.groupName, !set.isEmpty {
                    Text(set)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.muted)
                }
            }
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        if let urlString = group.displayImageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 320)
                case .failure:
                    imagePlaceholder
                case .empty:
                    imagePlaceholder.redacted(reason: .placeholder)
                @unknown default:
                    imagePlaceholder
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(AppColor.elev)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .stroke(AppColor.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
            .fill(AppColor.elev)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(AppColor.dim)
            )
            .frame(height: 240)
    }

    private var summary: some View {
        SlabCard {
            HStack(alignment: .top, spacing: Spacing.l) {
                summaryColumn(
                    kicker: "Listings",
                    value: "\(group.listingCount)",
                    detail: group.listingCount == 1 ? "live result" : "live results"
                )
                Spacer()
                summaryColumn(
                    kicker: "Price range",
                    value: priceRangeLabel,
                    detail: "from cheapest"
                )
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.md)
        }
    }

    private func summaryColumn(kicker: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            KickerLabel(kicker)
            Text(value).slabRowTitle()
            Text(detail)
                .font(SlabFont.sans(size: 11))
                .foregroundStyle(AppColor.dim)
        }
    }

    private var priceRangeLabel: String {
        guard let minP = group.minPrice else { return "—" }
        if let maxP = group.maxPrice, maxP > minP {
            return "\(MoversFormat.price(minP)) – \(MoversFormat.price(maxP))"
        }
        return MoversFormat.price(minP)
    }

    private var listings: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("eBay listings")
            Text("Affiliate links — Slabbist may earn a commission.")
                .font(SlabFont.sans(size: 11))
                .foregroundStyle(AppColor.dim)
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(Array(group.listings.enumerated()), id: \.element.id) { index, listing in
                        if index > 0 { SlabCardDivider() }
                        EbayProductListingRow(listing: listing)
                    }
                }
            }
        }
    }
}

/// Single-listing row inside the per-product drill-down. Tap opens
/// the listing on eBay. Compared to the flat-list row it drops the
/// product name (now in the hero) and emphasises grade + price.
private struct EbayProductListingRow: View {
    let listing: EbayListingBrowseRowDTO

    var body: some View {
        Button {
            if let url = EbayAffiliateLink.rewrite(listing.url) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(alignment: .center, spacing: Spacing.m) {
                thumbnail
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(listing.gradeBadge)
                        .font(SlabFont.mono(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.gold)
                    Text(listing.title)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.text)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    if let endAt = listing.endAt {
                        Text("Ends \(endAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(SlabFont.mono(size: 11))
                            .foregroundStyle(AppColor.dim)
                    }
                }
                Spacer(minLength: Spacing.s)
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text(MoversFormat.price(listing.price))
                        .slabMetric()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.dim)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens listing on eBay")
    }

    @ViewBuilder
    private var thumbnail: some View {
        let urlString = listing.imageUrl ?? listing.cardImageUrl
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(AppColor.elev2)
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .empty, .failure:
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColor.dim)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
    }
}
