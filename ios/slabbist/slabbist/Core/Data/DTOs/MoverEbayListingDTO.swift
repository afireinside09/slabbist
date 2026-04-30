import Foundation

/// One row from `public.get_mover_ebay_listings`. Active eBay listing
/// the scraper has positively tied to a specific (product, sub_type)
/// movers card. The table is replaced wholesale by every scraper
/// run, so the iOS layer treats this as a snapshot — no pagination,
/// no caching beyond the in-memory view-model state.
nonisolated struct MoverEbayListingDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    let ebayItemId: String
    let title: String
    let price: Double
    let currency: String
    let url: String
    let imageUrl: String?
    let gradingService: String
    let grade: String
    let buyingOptions: String?
    let endAt: Date?
    let refreshedAt: Date

    var id: String { ebayItemId }

    /// Short label rendered on the carousel chip, e.g. "PSA 10".
    var gradeBadge: String { "\(gradingService) \(grade)" }

    enum CodingKeys: String, CodingKey {
        case ebayItemId    = "ebay_item_id"
        case title
        case price
        case currency
        case url
        case imageUrl      = "image_url"
        case gradingService = "grading_service"
        case grade
        case buyingOptions = "buying_options"
        case endAt         = "end_at"
        case refreshedAt   = "refreshed_at"
    }

    init(
        ebayItemId: String,
        title: String,
        price: Double,
        currency: String,
        url: String,
        imageUrl: String?,
        gradingService: String,
        grade: String,
        buyingOptions: String? = nil,
        endAt: Date? = nil,
        refreshedAt: Date = Date()
    ) {
        self.ebayItemId = ebayItemId
        self.title = title
        self.price = price
        self.currency = currency
        self.url = url
        self.imageUrl = imageUrl
        self.gradingService = gradingService
        self.grade = grade
        self.buyingOptions = buyingOptions
        self.endAt = endAt
        self.refreshedAt = refreshedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ebayItemId     = try c.decode(String.self, forKey: .ebayItemId)
        self.title          = try c.decode(String.self, forKey: .title)
        self.price          = try c.decodeFlexibleDouble(forKey: .price)
        self.currency       = try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        self.url            = try c.decode(String.self, forKey: .url)
        self.imageUrl       = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        self.gradingService = try c.decode(String.self, forKey: .gradingService)
        self.grade          = try c.decode(String.self, forKey: .grade)
        self.buyingOptions  = try c.decodeIfPresent(String.self, forKey: .buyingOptions)
        self.endAt          = try c.decodeIfPresent(Date.self, forKey: .endAt)
        self.refreshedAt    = try c.decode(Date.self, forKey: .refreshedAt)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDouble(forKey key: Key) throws -> Double {
        if let asDouble = try? decode(Double.self, forKey: key) { return asDouble }
        if let asString = try? decode(String.self, forKey: key),
           let parsed = Double(asString) { return parsed }
        throw DecodingError.dataCorruptedError(
            forKey: key, in: self,
            debugDescription: "Expected a number or numeric string for \(key.stringValue)."
        )
    }
}
