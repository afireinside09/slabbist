import Foundation

/// One point on a card's price-history line. Returned by
/// `public.get_product_price_history`. PostgREST emits `numeric` as
/// either JSON number or string depending on the value, so the
/// initializer tolerates both.
nonisolated struct PriceHistoryDTO: Codable, Sendable, Equatable {
    let capturedAt: Date
    let marketPrice: Double
    let lowPrice: Double?
    let midPrice: Double?
    let highPrice: Double?

    enum CodingKeys: String, CodingKey {
        case capturedAt  = "captured_at"
        case marketPrice = "market_price"
        case lowPrice    = "low_price"
        case midPrice    = "mid_price"
        case highPrice   = "high_price"
    }

    init(
        capturedAt: Date,
        marketPrice: Double,
        lowPrice: Double? = nil,
        midPrice: Double? = nil,
        highPrice: Double? = nil
    ) {
        self.capturedAt = capturedAt
        self.marketPrice = marketPrice
        self.lowPrice = lowPrice
        self.midPrice = midPrice
        self.highPrice = highPrice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.capturedAt  = try c.decode(Date.self, forKey: .capturedAt)
        self.marketPrice = try c.decodeFlexibleDouble(forKey: .marketPrice)
        self.lowPrice    = try c.decodeFlexibleDoubleIfPresent(forKey: .lowPrice)
        self.midPrice    = try c.decodeFlexibleDoubleIfPresent(forKey: .midPrice)
        self.highPrice   = try c.decodeFlexibleDoubleIfPresent(forKey: .highPrice)
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

    nonisolated func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if try decodeNil(forKey: key) { return nil }
        return try decodeFlexibleDouble(forKey: key)
    }
}
