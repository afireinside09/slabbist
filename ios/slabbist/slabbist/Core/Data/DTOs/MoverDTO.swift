import Foundation

/// One row from the `public.get_top_movers` RPC. Each row represents a
/// single (product, sub_type) whose latest price differs from its prior
/// snapshot.
///
/// PostgREST serializes Postgres `numeric` as JSON *string* in some
/// configurations (v11+) to preserve arbitrary precision, and as JSON
/// number in others. `init(from:)` tolerates both so the DTO survives
/// either wire shape without a bespoke server coercion layer.
nonisolated struct MoverDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    let productId: Int
    let productName: String
    let groupName: String?
    let imageUrl: String?
    let subTypeName: String
    let currentPrice: Double
    let previousPrice: Double
    let absChange: Double
    let pctChange: Double
    let capturedAt: Date
    let previousCapturedAt: Date
    /// Populated only by the per-set RPC (`get_set_movers`) which
    /// returns gainers + losers in one payload. Nil when fetched via
    /// the per-direction RPC (`get_top_movers`), where direction is
    /// implicit from the call.
    let direction: String?

    var id: String {
        if let dir = direction {
            return "\(productId)-\(subTypeName)-\(dir)"
        }
        return "\(productId)-\(subTypeName)"
    }

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case productName = "product_name"
        case groupName = "group_name"
        case imageUrl = "image_url"
        case subTypeName = "sub_type_name"
        case currentPrice = "current_price"
        case previousPrice = "previous_price"
        case absChange = "abs_change"
        case pctChange = "pct_change"
        case capturedAt = "captured_at"
        case previousCapturedAt = "previous_captured_at"
        case direction
    }

    init(
        productId: Int,
        productName: String,
        groupName: String?,
        imageUrl: String?,
        subTypeName: String,
        currentPrice: Double,
        previousPrice: Double,
        absChange: Double,
        pctChange: Double,
        capturedAt: Date,
        previousCapturedAt: Date,
        direction: String? = nil
    ) {
        self.productId = productId
        self.productName = productName
        self.groupName = groupName
        self.imageUrl = imageUrl
        self.subTypeName = subTypeName
        self.currentPrice = currentPrice
        self.previousPrice = previousPrice
        self.absChange = absChange
        self.pctChange = pctChange
        self.capturedAt = capturedAt
        self.previousCapturedAt = previousCapturedAt
        self.direction = direction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.productId       = try c.decode(Int.self, forKey: .productId)
        self.productName     = try c.decode(String.self, forKey: .productName)
        self.groupName       = try c.decodeIfPresent(String.self, forKey: .groupName)
        self.imageUrl        = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        self.subTypeName     = try c.decode(String.self, forKey: .subTypeName)
        self.currentPrice    = try c.decodeFlexibleDouble(forKey: .currentPrice)
        self.previousPrice   = try c.decodeFlexibleDouble(forKey: .previousPrice)
        self.absChange       = try c.decodeFlexibleDouble(forKey: .absChange)
        self.pctChange       = try c.decodeFlexibleDouble(forKey: .pctChange)
        self.capturedAt          = try c.decode(Date.self, forKey: .capturedAt)
        self.previousCapturedAt  = try c.decode(Date.self, forKey: .previousCapturedAt)
        self.direction       = try c.decodeIfPresent(String.self, forKey: .direction)
    }
}

private extension KeyedDecodingContainer {
    /// Decodes a Double from either a JSON number or a numeric string
    /// (PostgREST's default for `numeric` types).
    func decodeFlexibleDouble(forKey key: Key) throws -> Double {
        if let asDouble = try? decode(Double.self, forKey: key) {
            return asDouble
        }
        if let asString = try? decode(String.self, forKey: key),
           let parsed = Double(asString) {
            return parsed
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Expected a number or numeric string for \(key.stringValue)."
        )
    }
}
