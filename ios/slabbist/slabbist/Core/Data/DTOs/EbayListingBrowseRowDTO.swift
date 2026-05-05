import Foundation

/// One row from `public.get_ebay_listings`. Wraps both the listing
/// fields and the card metadata (product name, set name, image)
/// because the eBay-Listings tab on the Movers screen renders cards
/// across many products in one flat list — each row needs to identify
/// the card it represents without extra round-trips.
nonisolated struct EbayListingBrowseRowDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    // Card identity
    let productId: Int
    let subTypeName: String
    let productName: String
    let groupId: Int
    let groupName: String?
    let cardImageUrl: String?

    // Listing fields
    let ebayItemId: String
    let title: String
    let price: Double
    let currency: String
    let url: String
    let imageUrl: String?
    /// See MoverEbayListingDTO — graded gating is enforced at the
    /// scraper's source layer, so these can be null when the title
    /// doesn't surface the grader / grade.
    let gradingService: String?
    let grade: String?
    let buyingOptions: String?
    let endAt: Date?
    let refreshedAt: Date

    /// `(productId, subType, ebayItemId)` is unique by table design;
    /// itemId alone is unique across the whole table since eBay item
    /// IDs are globally distinct.
    var id: String { ebayItemId }

    var gradeBadge: String {
        switch (gradingService, grade) {
        case let (service?, grade?): return "\(service) \(grade)"
        case let (service?, nil):    return service
        case let (nil, grade?):      return grade
        case (nil, nil):             return "Graded"
        }
    }

    enum CodingKeys: String, CodingKey {
        case productId      = "product_id"
        case subTypeName    = "sub_type_name"
        case productName    = "product_name"
        case groupId        = "group_id"
        case groupName      = "group_name"
        case cardImageUrl   = "card_image_url"
        case ebayItemId     = "ebay_item_id"
        case title
        case price
        case currency
        case url
        case imageUrl       = "image_url"
        case gradingService = "grading_service"
        case grade
        case buyingOptions  = "buying_options"
        case endAt          = "end_at"
        case refreshedAt    = "refreshed_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.productId      = try c.decode(Int.self, forKey: .productId)
        self.subTypeName    = try c.decode(String.self, forKey: .subTypeName)
        self.productName    = try c.decode(String.self, forKey: .productName)
        self.groupId        = try c.decode(Int.self, forKey: .groupId)
        self.groupName      = try c.decodeIfPresent(String.self, forKey: .groupName)
        self.cardImageUrl   = try c.decodeIfPresent(String.self, forKey: .cardImageUrl)
        self.ebayItemId     = try c.decode(String.self, forKey: .ebayItemId)
        self.title          = try c.decode(String.self, forKey: .title)
        self.price          = try c.decodeFlexibleDouble(forKey: .price)
        self.currency       = try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        self.url            = try c.decode(String.self, forKey: .url)
        self.imageUrl       = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        self.gradingService = try c.decodeIfPresent(String.self, forKey: .gradingService)
        self.grade          = try c.decodeIfPresent(String.self, forKey: .grade)
        self.buyingOptions  = try c.decodeIfPresent(String.self, forKey: .buyingOptions)
        self.endAt          = try c.decodeIfPresent(Date.self, forKey: .endAt)
        self.refreshedAt    = try c.decode(Date.self, forKey: .refreshedAt)
    }

    init(
        productId: Int, subTypeName: String, productName: String,
        groupId: Int, groupName: String?, cardImageUrl: String?,
        ebayItemId: String, title: String, price: Double, currency: String,
        url: String, imageUrl: String?,
        gradingService: String? = nil, grade: String? = nil,
        buyingOptions: String? = nil, endAt: Date? = nil, refreshedAt: Date = Date()
    ) {
        self.productId      = productId
        self.subTypeName    = subTypeName
        self.productName    = productName
        self.groupId        = groupId
        self.groupName      = groupName
        self.cardImageUrl   = cardImageUrl
        self.ebayItemId     = ebayItemId
        self.title          = title
        self.price          = price
        self.currency       = currency
        self.url            = url
        self.imageUrl       = imageUrl
        self.gradingService = gradingService
        self.grade          = grade
        self.buyingOptions  = buyingOptions
        self.endAt          = endAt
        self.refreshedAt    = refreshedAt
    }
}

private extension KeyedDecodingContainer {
    nonisolated func decodeFlexibleDouble(forKey key: Key) throws -> Double {
        if let asDouble = try? decode(Double.self, forKey: key) { return asDouble }
        if let asString = try? decode(String.self, forKey: key),
           let parsed = Double(asString) { return parsed }
        throw DecodingError.dataCorruptedError(
            forKey: key, in: self,
            debugDescription: "Expected a number or numeric string for \(key.stringValue)."
        )
    }
}
