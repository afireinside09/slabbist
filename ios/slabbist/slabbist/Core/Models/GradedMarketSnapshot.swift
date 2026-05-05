import Foundation
import SwiftData

@Model
final class GradedMarketSnapshot {
    var identityId: UUID
    var gradingService: String
    var grade: String

    var headlinePriceCents: Int64?

    var loosePriceCents: Int64?
    var grade7PriceCents: Int64?
    var grade8PriceCents: Int64?
    var grade9PriceCents: Int64?
    var grade9_5PriceCents: Int64?
    var psa10PriceCents: Int64?
    var bgs10PriceCents: Int64?
    var cgc10PriceCents: Int64?
    var sgc10PriceCents: Int64?

    var pricechartingProductId: String?
    var pricechartingURL: URL?

    var fetchedAt: Date
    var cacheHit: Bool
    var isStaleFallback: Bool

    init(
        identityId: UUID,
        gradingService: String,
        grade: String,
        headlinePriceCents: Int64?,
        loosePriceCents: Int64?,
        grade7PriceCents: Int64?,
        grade8PriceCents: Int64?,
        grade9PriceCents: Int64?,
        grade9_5PriceCents: Int64?,
        psa10PriceCents: Int64?,
        bgs10PriceCents: Int64?,
        cgc10PriceCents: Int64?,
        sgc10PriceCents: Int64?,
        pricechartingProductId: String?,
        pricechartingURL: URL?,
        fetchedAt: Date,
        cacheHit: Bool,
        isStaleFallback: Bool
    ) {
        self.identityId = identityId
        self.gradingService = gradingService
        self.grade = grade
        self.headlinePriceCents = headlinePriceCents
        self.loosePriceCents = loosePriceCents
        self.grade7PriceCents = grade7PriceCents
        self.grade8PriceCents = grade8PriceCents
        self.grade9PriceCents = grade9PriceCents
        self.grade9_5PriceCents = grade9_5PriceCents
        self.psa10PriceCents = psa10PriceCents
        self.bgs10PriceCents = bgs10PriceCents
        self.cgc10PriceCents = cgc10PriceCents
        self.sgc10PriceCents = sgc10PriceCents
        self.pricechartingProductId = pricechartingProductId
        self.pricechartingURL = pricechartingURL
        self.fetchedAt = fetchedAt
        self.cacheHit = cacheHit
        self.isStaleFallback = isStaleFallback
    }
}
