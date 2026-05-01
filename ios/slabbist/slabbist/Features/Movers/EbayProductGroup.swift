import Foundation

/// Product-level grouping over a flat list of eBay listing rows. The
/// eBay-Listings tab on the Movers screen lists Pokémon products
/// first; tapping a product drills into the listings tied to it.
/// Built from the same `EbayListingBrowseRowDTO` payload the flat
/// list used to render so no new RPC is needed — grouping is a pure
/// client-side fold.
nonisolated struct EbayProductGroup: Identifiable, Hashable, Sendable {
    let productId: Int
    let subTypeName: String
    let productName: String
    let groupId: Int
    let groupName: String?
    let cardImageUrl: String?
    let listings: [EbayListingBrowseRowDTO]

    /// `(productId, subTypeName)` is the natural key for a Pokémon
    /// product variant; ebay listings link to it many-to-one.
    var id: String { "\(productId)|\(subTypeName)" }

    var listingCount: Int { listings.count }
    var minPrice: Double? { listings.map(\.price).min() }
    var maxPrice: Double? { listings.map(\.price).max() }

    /// Most-recently-refreshed listing's image — falls back to the
    /// card stock image (`cardImageUrl`) when no listing image landed.
    var displayImageUrl: String? {
        listings.first(where: { $0.imageUrl != nil })?.imageUrl ?? cardImageUrl
    }
}

extension Array where Element == EbayListingBrowseRowDTO {
    /// Groups listings by `(productId, subTypeName)` while preserving
    /// the order in which each product first appears. Within a group,
    /// listings are sorted ascending by price so the cheapest comp
    /// surfaces first when the drill-down opens.
    func groupedByProduct() -> [EbayProductGroup] {
        var order: [String] = []
        var bucket: [String: [EbayListingBrowseRowDTO]] = [:]
        var meta: [String: EbayListingBrowseRowDTO] = [:]
        for row in self {
            let key = "\(row.productId)|\(row.subTypeName)"
            if bucket[key] == nil {
                order.append(key)
                meta[key] = row
            }
            bucket[key, default: []].append(row)
        }
        return order.compactMap { key in
            guard let head = meta[key], let rows = bucket[key] else { return nil }
            return EbayProductGroup(
                productId: head.productId,
                subTypeName: head.subTypeName,
                productName: head.productName,
                groupId: head.groupId,
                groupName: head.groupName,
                cardImageUrl: head.cardImageUrl,
                listings: rows.sorted(by: { $0.price < $1.price })
            )
        }
    }
}
