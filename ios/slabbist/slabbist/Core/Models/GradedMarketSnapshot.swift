import Foundation
import SwiftData

@Model
final class GradedMarketSnapshot {
    var identityId: UUID
    var gradingService: String
    var grade: String

    /// "poketrace". A single snapshot per (identity, service, grade) is now
    /// written — Poketrace is the sole pricing source.
    ///
    /// The default literal matters: SwiftData's lightweight migration uses it
    /// to backfill existing rows. Pre-PPT-removal rows carried
    /// "pokemonpricetracker"; the migration deletes those rows server-side, so
    /// any surviving on-device rows that survive without a store reset will be
    /// treated as the Poketrace source on next read. The store-reset catch path
    /// in ModelContainer.swift handles the destructive column removal if
    /// lightweight migration cannot proceed.
    var source: String = "poketrace"

    var headlinePriceCents: Int64?

    // Poketrace-shaped fields.
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

    /// JSON-encoded `[String: Int64]` map of Poketrace's per-tier
    /// average prices in cents, keyed by snake_case tier ids
    /// ("loose"/"psa_7".."sgc_10"). Same string-encoded-blob convention
    /// as `priceHistoryJSON` — SwiftData lightweight migration handles a
    /// String? field cleanly, whereas a Codable dictionary property risks
    /// migration failures.
    var ptTierPricesJSON: String?

    /// JSON-encoded `[PriceHistoryPoint]`. Decoded on demand for the
    /// sparkline view; SwiftData prefers a single primitive blob over
    /// a Codable property of a value-array type, which can fail lightweight
    /// migration.
    var priceHistoryJSON: String?

    /// Deep-link to the eBay sold-results page for this card + grade.
    /// Populated from the v3 `marketplace_url` field.
    var marketplaceURL: URL?

    /// JSON-encoded `[SoldListing]`; decoded on demand via `soldListings`.
    /// Same blob convention as `priceHistoryJSON`.
    var soldListingsJSON: String?

    var fetchedAt: Date
    var cacheHit: Bool

    init(
        identityId: UUID,
        gradingService: String,
        grade: String,
        source: String = "poketrace",
        headlinePriceCents: Int64?,
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
        ptTierPricesJSON: String? = nil,
        priceHistoryJSON: String?,
        marketplaceURL: URL? = nil,
        soldListingsJSON: String? = nil,
        fetchedAt: Date,
        cacheHit: Bool
    ) {
        self.identityId = identityId
        self.gradingService = gradingService
        self.grade = grade
        self.source = source
        self.headlinePriceCents = headlinePriceCents
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
        self.ptTierPricesJSON = ptTierPricesJSON
        self.priceHistoryJSON = priceHistoryJSON
        self.marketplaceURL = marketplaceURL
        self.soldListingsJSON = soldListingsJSON
        self.fetchedAt = fetchedAt
        self.cacheHit = cacheHit
    }

    /// Decoded view of `priceHistoryJSON`. Returns `[]` when missing or
    /// malformed — the caller renders an empty sparkline.
    var priceHistory: [PriceHistoryPoint] {
        guard let json = priceHistoryJSON, let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PriceHistoryPoint].self, from: data)) ?? []
    }

    /// Decoded view of `ptTierPricesJSON`. Keys are snake_case ladder ids
    /// ("loose"/"psa_7".."sgc_10"); values are integer cents. Empty
    /// dictionary when missing or malformed — `CompCardView` treats
    /// missing keys as "no data" for that ladder cell.
    var ptTierPricesCents: [String: Int64] {
        guard let json = ptTierPricesJSON, let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Int64].self, from: data)) ?? [:]
    }

    /// Decoded view of `soldListingsJSON`. Returns `[]` when missing or
    /// malformed — UI shows empty/degraded state.
    var soldListings: [SoldListing] {
        guard let json = soldListingsJSON, let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SoldListing].self, from: data)) ?? []
    }
}

extension GradedMarketSnapshot {
    static let sourcePoketrace = "poketrace"
}
