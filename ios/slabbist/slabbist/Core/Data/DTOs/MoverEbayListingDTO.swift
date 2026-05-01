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
    /// Nullable: the scraper's eBay sources gate to graded slabs server-side
    /// via the "Graded" aspect, so listings whose titles don't carry the
    /// grader name still land here with this column unset.
    let gradingService: String?
    let grade: String?
    let buyingOptions: String?
    let endAt: Date?
    let refreshedAt: Date

    var id: String { ebayItemId }

    /// Short label rendered on the carousel chip. "PSA 10" when both
    /// grader and grade are known; "PSA" or "10" when only one is; falls
    /// back to "Graded" when the scraper couldn't parse either from the
    /// title (the slab is still graded — eBay's filter guaranteed that).
    var gradeBadge: String {
        switch (gradingService, grade) {
        case let (service?, grade?): return "\(service) \(grade)"
        case let (service?, nil):    return service
        case let (nil, grade?):      return grade
        case (nil, nil):             return "Graded"
        }
    }

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
        gradingService: String? = nil,
        grade: String? = nil,
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
        self.gradingService = try c.decodeIfPresent(String.self, forKey: .gradingService)
        self.grade          = try c.decodeIfPresent(String.self, forKey: .grade)
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
