import Testing
import Foundation
import SwiftData
@testable import slabbist

@Suite("CompFetchService.persist")
@MainActor
struct CompFetchServicePersistTests {
    static let identityId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let storeId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let lotId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let userId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    /// Builds a `Decoded` populated with both PPT ladder data and a
    /// Poketrace block, using the same numbers as the v2-both-sources
    /// fixture in `CompRepositoryTests.decodesV2BothSources`. PPT headline
    /// is 18500, Poketrace avg is 19500, reconciled headline is 19000.
    static func makeBothSourcesDecoded() -> CompRepository.Decoded {
        let pt = CompRepository.Decoded.SourceComp(
            cardId: "22222222-2222-2222-2222-222222222222",
            tier: "PSA_10",
            avgCents: 19500,
            lowCents: 18000,
            highCents: 21000,
            avg1dCents: nil,
            avg7dCents: 19400,
            avg30dCents: 19200,
            median3dCents: 19500,
            median7dCents: 19350,
            median30dCents: 19000,
            trend: "stable",
            confidence: "high",
            saleCount: 24,
            tierPricesCents: [
                "loose": 400, "psa_8": 3400, "psa_9": 6800, "psa_9_5": 11200,
                "psa_10": 19500, "bgs_10": 22000, "cgc_10": 17000,
            ],
            priceHistory: [
                PriceHistoryPoint(ts: ISO8601DateFormatter().date(from: "2026-04-30T00:00:00Z")!, priceCents: 19200),
            ],
            fetchedAt: ISO8601DateFormatter().date(from: "2026-05-07T22:14:03Z")!
        )
        return CompRepository.Decoded(
            headlinePriceCents: 18500,
            gradingService: "PSA",
            grade: "10",
            loosePriceCents: 400,
            psa7PriceCents: 2400,
            psa8PriceCents: 3400,
            psa9PriceCents: 6800,
            psa9_5PriceCents: 11200,
            psa10PriceCents: 18500,
            bgs10PriceCents: 21500,
            cgc10PriceCents: 16800,
            sgc10PriceCents: 16500,
            priceHistory: [
                PriceHistoryPoint(ts: ISO8601DateFormatter().date(from: "2025-11-08T00:00:00Z")!, priceCents: 16200),
            ],
            pptTCGPlayerId: "243172",
            pptURL: URL(string: "https://www.pokemonpricetracker.com/card/charizard"),
            fetchedAt: ISO8601DateFormatter().date(from: "2026-05-07T22:14:03Z")!,
            cacheHit: false,
            isStaleFallback: false,
            poketrace: pt,
            reconciledHeadlineCents: 19000,
            reconciledSource: "avg"
        )
    }

    /// A validated `Scan` that matches the fixture identity/grade — wired
    /// into the in-memory context the same way `BulkScanViewModel` would
    /// after cert-lookup succeeds.
    static func makeScan() -> Scan {
        let now = Date()
        return Scan(
            id: UUID(),
            storeId: storeId,
            lotId: lotId,
            userId: userId,
            grader: .PSA,
            certNumber: "00000001",
            grade: "10",
            gradedCardIdentityId: identityId,
            status: .validated,
            createdAt: now,
            updatedAt: now
        )
    }

    @Test("persists two snapshots — PPT and Poketrace — when both are present")
    func persistsBothSnapshots() async throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let service = CompFetchService(context: context)
        let decoded = Self.makeBothSourcesDecoded()
        let scan = Self.makeScan()
        context.insert(scan)
        try context.save()

        try await service.persist(scan: scan, decoded: decoded)

        let fetched: [GradedMarketSnapshot] = try context.fetch(FetchDescriptor<GradedMarketSnapshot>())
        #expect(fetched.count == 2)
        #expect(fetched.contains { $0.source == GradedMarketSnapshot.sourcePPT && $0.psa10PriceCents == 18500 })
        #expect(fetched.contains { $0.source == GradedMarketSnapshot.sourcePoketrace && $0.ptAvgCents == 19500 })
        #expect(scan.reconciledHeadlinePriceCents == 19000)
    }
}

@Suite("CompFetchService.classify")
struct CompFetchServiceClassifyTests {
    @Test("noMarketData maps to no_data with a Pokemon Price Tracker-flavored message")
    func mapsNoMarketData() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.noMarketData)
        #expect(state == .noData)
        #expect(message.localizedCaseInsensitiveContains("pokemon price tracker"))
    }

    @Test("productNotResolved also maps to no_data, with distinct copy")
    func mapsProductNotResolved() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.productNotResolved)
        #expect(state == .noData)
        #expect(message.localizedCaseInsensitiveContains("couldn't find"))
    }

    @Test("upstreamUnavailable maps to failed with Pokemon Price Tracker wording")
    func mapsUpstream() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.upstreamUnavailable)
        #expect(state == .failed)
        #expect(message.localizedCaseInsensitiveContains("pokemon price tracker"))
    }

    @Test("authInvalid maps to failed with operator-actionable copy")
    func mapsAuthInvalid() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.authInvalid)
        #expect(state == .failed)
        #expect(message.localizedCaseInsensitiveContains("misconfigured"))
    }

    @Test("identityNotFound suggests re-scanning the cert")
    func mapsIdentityNotFound() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.identityNotFound)
        #expect(state == .failed)
        #expect(message.localizedCaseInsensitiveContains("re-scan"))
    }

    @Test("httpStatus surfaces the status code in the message")
    func mapsHttpStatus() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.httpStatus(502))
        #expect(state == .failed)
        #expect(message.contains("502"))
    }

    @Test("decoding error includes the underlying detail")
    func mapsDecoding() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.decoding("missing key 'headline_price_cents'"))
        #expect(state == .failed)
        #expect(message.contains("headline_price_cents"))
    }

    @Test("unknown errors fall through to localizedDescription")
    func fallsThroughToLocalized() {
        struct Bogus: Error, LocalizedError {
            var errorDescription: String? { "something exploded" }
        }
        let (state, message) = CompFetchService.classify(Bogus())
        #expect(state == .failed)
        #expect(message == "something exploded")
    }
}
