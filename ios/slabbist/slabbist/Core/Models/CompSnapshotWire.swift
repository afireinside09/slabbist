import Foundation

/// Immutable, self-contained serialization of a `GradedMarketSnapshot`
/// frozen onto a `Scan` at offer-send time. Persisted as a JSON-string
/// blob in `scans.comp_snapshot` (text column) so the comp that justified
/// an offer stays retrievable later — even after the live `graded_market`
/// cache is overwritten by a subsequent refetch.
///
/// Stored as a text blob (not jsonb) to mirror the existing `*JSON`
/// String? convention on `GradedMarketSnapshot` and to keep the outbox
/// patch a plain `.string` value. This is an audit/retrieval record, not
/// a server-side query target.
struct CompSnapshotWire: Codable, Equatable {
    let source: String
    let headlinePriceCents: Int64?
    let ptAvgCents: Int64?
    let ptLowCents: Int64?
    let ptHighCents: Int64?
    let ptAvg1dCents: Int64?
    let ptAvg7dCents: Int64?
    let ptAvg30dCents: Int64?
    let ptMedian3dCents: Int64?
    let ptMedian7dCents: Int64?
    let ptMedian30dCents: Int64?
    let ptTrend: String?
    let ptConfidence: String?
    let ptSaleCount: Int?
    let poketraceCardId: String?
    let tcgplayerProductId: Int?
    let tierPricesCents: [String: Int64]
    let priceHistory: [PriceHistoryPoint]
    let soldListings: [SoldListing]
    let marketplaceURL: URL?
    let fetchedAt: Date
    let cacheHit: Bool

    enum CodingKeys: String, CodingKey {
        case source
        case headlinePriceCents = "headline_price_cents"
        case ptAvgCents = "pt_avg_cents"
        case ptLowCents = "pt_low_cents"
        case ptHighCents = "pt_high_cents"
        case ptAvg1dCents = "pt_avg_1d_cents"
        case ptAvg7dCents = "pt_avg_7d_cents"
        case ptAvg30dCents = "pt_avg_30d_cents"
        case ptMedian3dCents = "pt_median_3d_cents"
        case ptMedian7dCents = "pt_median_7d_cents"
        case ptMedian30dCents = "pt_median_30d_cents"
        case ptTrend = "pt_trend"
        case ptConfidence = "pt_confidence"
        case ptSaleCount = "pt_sale_count"
        case poketraceCardId = "poketrace_card_id"
        case tcgplayerProductId = "tcgplayer_product_id"
        case tierPricesCents = "tier_prices_cents"
        case priceHistory = "price_history"
        case soldListings = "sold_listings"
        case marketplaceURL = "marketplace_url"
        case fetchedAt = "fetched_at"
        case cacheHit = "cache_hit"
    }
}

extension CompSnapshotWire {
    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Build a wire struct from the on-device snapshot, reusing the
    /// snapshot's decoded accessors so the nested blobs (tier ladder,
    /// price history, sold listings) come across already-typed.
    init(from snapshot: GradedMarketSnapshot) {
        self.source = snapshot.source
        self.headlinePriceCents = snapshot.headlinePriceCents
        self.ptAvgCents = snapshot.ptAvgCents
        self.ptLowCents = snapshot.ptLowCents
        self.ptHighCents = snapshot.ptHighCents
        self.ptAvg1dCents = snapshot.ptAvg1dCents
        self.ptAvg7dCents = snapshot.ptAvg7dCents
        self.ptAvg30dCents = snapshot.ptAvg30dCents
        self.ptMedian3dCents = snapshot.ptMedian3dCents
        self.ptMedian7dCents = snapshot.ptMedian7dCents
        self.ptMedian30dCents = snapshot.ptMedian30dCents
        self.ptTrend = snapshot.ptTrend
        self.ptConfidence = snapshot.ptConfidence
        self.ptSaleCount = snapshot.ptSaleCount
        self.poketraceCardId = snapshot.poketraceCardId
        self.tcgplayerProductId = snapshot.tcgplayerProductId
        self.tierPricesCents = snapshot.ptTierPricesCents
        self.priceHistory = snapshot.priceHistory
        self.soldListings = snapshot.soldListings
        self.marketplaceURL = snapshot.marketplaceURL
        self.fetchedAt = snapshot.fetchedAt
        self.cacheHit = snapshot.cacheHit
    }

    /// JSON-string blob for `scans.comp_snapshot`. Returns nil on encode
    /// failure (caller skips the freeze rather than queueing a bad patch).
    static func encode(from snapshot: GradedMarketSnapshot) -> String? {
        guard let data = try? makeEncoder().encode(CompSnapshotWire(from: snapshot)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode a persisted blob back into a wire struct. Returns nil when
    /// missing or malformed; the detail UI renders "no frozen comp".
    static func decode(_ json: String?) -> CompSnapshotWire? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? makeDecoder().decode(CompSnapshotWire.self, from: data)
    }
}
