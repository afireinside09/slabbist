import Foundation
import SwiftData

@Model
final class GradedMarketSnapshot {
    var identityId: UUID
    var gradingService: String
    var grade: String

    var headlinePriceCents: Int64?

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
        headlinePriceCents: Int64?,
        loosePriceCents: Int64?,
        psa7PriceCents: Int64?,
        psa8PriceCents: Int64?,
        psa9PriceCents: Int64?,
        psa9_5PriceCents: Int64?,
        psa10PriceCents: Int64?,
        bgs10PriceCents: Int64?,
        cgc10PriceCents: Int64?,
        sgc10PriceCents: Int64?,
        pptTCGPlayerId: String?,
        pptURL: URL?,
        priceHistoryJSON: String?,
        fetchedAt: Date,
        cacheHit: Bool,
        isStaleFallback: Bool
    ) {
        self.identityId = identityId
        self.gradingService = gradingService
        self.grade = grade
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
