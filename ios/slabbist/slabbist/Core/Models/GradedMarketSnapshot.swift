import Foundation
import SwiftData

@Model
final class GradedMarketSnapshot {
    var identityId: UUID
    var gradingService: String
    var grade: String

    /// "pokemonpricetracker" | "poketrace". Two snapshots can coexist for the
    /// same (identity, service, grade) — one per source.
    ///
    /// The default literal matters: SwiftData's lightweight migration uses it
    /// to backfill existing rows from the pre-poketrace schema (which had no
    /// `source` column). Without the default, migration fails with
    /// NSCocoaErrorDomain 134110 ("missing attribute values on mandatory
    /// destination attribute") and the catch-init-failure path in
    /// ModelContainer.swift has to nuke the store. Existing rows pre-date
    /// the poketrace integration so PPT is the correct backfill.
    var source: String = "pokemonpricetracker"

    var headlinePriceCents: Int64?

    // PPT-shaped ladder. Only populated when source == "pokemonpricetracker".
    var loosePriceCents: Int64?
    var psa7PriceCents: Int64?
    var psa8PriceCents: Int64?
    var psa9PriceCents: Int64?
    var psa9_5PriceCents: Int64?
    var psa10PriceCents: Int64?
    var bgs10PriceCents: Int64?
    var cgc10PriceCents: Int64?
    var sgc10PriceCents: Int64?

    var pptTCGPlayerId: String?
    var pptURL: URL?

    // Poketrace-shaped fields. Only populated when source == "poketrace".
    var ptAvgCents: Int64?
    var ptLowCents: Int64?
    var ptHighCents: Int64?
    var ptAvg1dCents: Int64?
    var ptAvg7dCents: Int64?
    var ptAvg30dCents: Int64?
    var ptMedian3dCents: Int64?
    var ptMedian7dCents: Int64?
    var ptMedian30dCents: Int64?
    var ptTrend: String?      // "up" | "down" | "stable"
    var ptConfidence: String? // "high" | "medium" | "low"
    var ptSaleCount: Int?
    var poketraceCardId: String?

    /// JSON-encoded `[PriceHistoryPoint]`. Decoded on demand for the
    /// sparkline view; SwiftData prefers a single primitive blob over
    /// a Codable property of a value-array type, which can fail lightweight
    /// migration.
    var priceHistoryJSON: String?

    var fetchedAt: Date
    var cacheHit: Bool
    var isStaleFallback: Bool

    init(
        identityId: UUID,
        gradingService: String,
        grade: String,
        source: String,
        headlinePriceCents: Int64?,
        loosePriceCents: Int64? = nil,
        psa7PriceCents: Int64? = nil,
        psa8PriceCents: Int64? = nil,
        psa9PriceCents: Int64? = nil,
        psa9_5PriceCents: Int64? = nil,
        psa10PriceCents: Int64? = nil,
        bgs10PriceCents: Int64? = nil,
        cgc10PriceCents: Int64? = nil,
        sgc10PriceCents: Int64? = nil,
        pptTCGPlayerId: String? = nil,
        pptURL: URL? = nil,
        ptAvgCents: Int64? = nil,
        ptLowCents: Int64? = nil,
        ptHighCents: Int64? = nil,
        ptAvg1dCents: Int64? = nil,
        ptAvg7dCents: Int64? = nil,
        ptAvg30dCents: Int64? = nil,
        ptMedian3dCents: Int64? = nil,
        ptMedian7dCents: Int64? = nil,
        ptMedian30dCents: Int64? = nil,
        ptTrend: String? = nil,
        ptConfidence: String? = nil,
        ptSaleCount: Int? = nil,
        poketraceCardId: String? = nil,
        priceHistoryJSON: String?,
        fetchedAt: Date,
        cacheHit: Bool,
        isStaleFallback: Bool
    ) {
        self.identityId = identityId
        self.gradingService = gradingService
        self.grade = grade
        self.source = source
        self.headlinePriceCents = headlinePriceCents
        self.loosePriceCents = loosePriceCents
        self.psa7PriceCents = psa7PriceCents
        self.psa8PriceCents = psa8PriceCents
        self.psa9PriceCents = psa9PriceCents
        self.psa9_5PriceCents = psa9_5PriceCents
        self.psa10PriceCents = psa10PriceCents
        self.bgs10PriceCents = bgs10PriceCents
        self.cgc10PriceCents = cgc10PriceCents
        self.sgc10PriceCents = sgc10PriceCents
        self.pptTCGPlayerId = pptTCGPlayerId
        self.pptURL = pptURL
        self.ptAvgCents = ptAvgCents
        self.ptLowCents = ptLowCents
        self.ptHighCents = ptHighCents
        self.ptAvg1dCents = ptAvg1dCents
        self.ptAvg7dCents = ptAvg7dCents
        self.ptAvg30dCents = ptAvg30dCents
        self.ptMedian3dCents = ptMedian3dCents
        self.ptMedian7dCents = ptMedian7dCents
        self.ptMedian30dCents = ptMedian30dCents
        self.ptTrend = ptTrend
        self.ptConfidence = ptConfidence
        self.ptSaleCount = ptSaleCount
        self.poketraceCardId = poketraceCardId
        self.priceHistoryJSON = priceHistoryJSON
        self.fetchedAt = fetchedAt
        self.cacheHit = cacheHit
        self.isStaleFallback = isStaleFallback
    }

    /// Decoded view of `priceHistoryJSON`. Returns `[]` when missing or
    /// malformed — the caller renders an empty sparkline.
    var priceHistory: [PriceHistoryPoint] {
        guard let json = priceHistoryJSON, let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PriceHistoryPoint].self, from: data)) ?? []
    }
}

extension GradedMarketSnapshot {
    static let sourcePPT = "pokemonpricetracker"
    static let sourcePoketrace = "poketrace"
}
