import Foundation
import SwiftData

@Model
final class GradedMarketSnapshot {
    var identityId: UUID
    var gradingService: String
    var grade: String

    var blendedPriceCents: Int64
    var meanPriceCents: Int64
    var trimmedMeanPriceCents: Int64
    var medianPriceCents: Int64
    var lowPriceCents: Int64
    var highPriceCents: Int64
    var confidence: Double
    var sampleCount: Int
    var sampleWindowDays: Int
    var velocity7d: Int
    var velocity30d: Int
    var velocity90d: Int
    var fetchedAt: Date
    var cacheHit: Bool
    var isStaleFallback: Bool

    @Relationship(deleteRule: .cascade)
    var soldListings: [SoldListingMirror]

    init(
        identityId: UUID,
        gradingService: String,
        grade: String,
        blendedPriceCents: Int64,
        meanPriceCents: Int64,
        trimmedMeanPriceCents: Int64,
        medianPriceCents: Int64,
        lowPriceCents: Int64,
        highPriceCents: Int64,
        confidence: Double,
        sampleCount: Int,
        sampleWindowDays: Int,
        velocity7d: Int,
        velocity30d: Int,
        velocity90d: Int,
        fetchedAt: Date,
        cacheHit: Bool,
        isStaleFallback: Bool,
        soldListings: [SoldListingMirror] = []
    ) {
        self.identityId = identityId
        self.gradingService = gradingService
        self.grade = grade
        self.blendedPriceCents = blendedPriceCents
        self.meanPriceCents = meanPriceCents
        self.trimmedMeanPriceCents = trimmedMeanPriceCents
        self.medianPriceCents = medianPriceCents
        self.lowPriceCents = lowPriceCents
        self.highPriceCents = highPriceCents
        self.confidence = confidence
        self.sampleCount = sampleCount
        self.sampleWindowDays = sampleWindowDays
        self.velocity7d = velocity7d
        self.velocity30d = velocity30d
        self.velocity90d = velocity90d
        self.fetchedAt = fetchedAt
        self.cacheHit = cacheHit
        self.isStaleFallback = isStaleFallback
        self.soldListings = soldListings
    }
}
