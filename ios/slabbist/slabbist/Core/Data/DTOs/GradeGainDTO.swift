import Foundation

/// One row from `get_set_grade_gains`. Profit (psa10 − raw − fee) is
/// computed client-side because the fee is user-adjustable; this DTO
/// carries only server facts.
nonisolated struct GradeGainDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    let productId: Int
    let productName: String
    let groupName: String?
    let imageUrl: String?
    let subTypeName: String
    let rawPriceCents: Int
    let psa10PriceCents: Int
    let spreadCents: Int
    let ptSaleCount: Int?

    var id: Int { productId }

    /// Profit in cents for a given grading fee (cents): the raw→PSA 10
    /// spread less the fee. Can be negative; the view model filters
    /// non-positive rows out of `visibleRows`.
    func profitCents(feeCents: Int) -> Int { spreadCents - feeCents }

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case productName = "product_name"
        case groupName = "group_name"
        case imageUrl = "image_url"
        case subTypeName = "sub_type_name"
        case rawPriceCents = "raw_price_cents"
        case psa10PriceCents = "psa10_price_cents"
        case spreadCents = "spread_cents"
        case ptSaleCount = "pt_sale_count"
    }
}
