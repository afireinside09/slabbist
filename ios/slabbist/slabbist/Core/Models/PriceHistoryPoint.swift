import Foundation

struct PriceHistoryPoint: Codable, Equatable, Hashable {
    let ts: Date
    let priceCents: Int64

    enum CodingKeys: String, CodingKey {
        case ts
        case priceCents = "price_cents"
    }
}
