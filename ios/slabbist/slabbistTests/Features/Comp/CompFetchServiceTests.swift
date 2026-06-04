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

    /// Builds a `Decoded` populated with a Poketrace block and two sold
    /// listings. Poketrace avg is 19500, headline is 19500. Mirrors the
    /// v3-full fixture in `CompRepositoryTests`.
    static func makeDecodedWithPoketraceAndListings() -> CompRepository.Decoded {
        let now = ISO8601DateFormatter().date(from: "2026-05-07T22:14:03Z")!
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
                "psa_9": 6800, "psa_10": 19500, "bgs_10": 22000,
            ],
            priceHistory: [
                PriceHistoryPoint(ts: ISO8601DateFormatter().date(from: "2026-04-30T00:00:00Z")!, priceCents: 19200),
            ],
            fetchedAt: now
        )
        let soldListings = [
            SoldListing(
                sourceListingId: "ebay-001",
                title: "Charizard PSA 10",
                priceCents: 19500,
                soldAt: ISO8601DateFormatter().date(from: "2026-04-28T10:00:00Z")!,
                grader: "PSA",
                grade: "10",
                condition: "Graded",
                url: URL(string: "https://www.ebay.com/itm/001"),
                anomalyFlag: nil
            ),
            SoldListing(
                sourceListingId: "ebay-002",
                title: "Charizard PSA 10 Base",
                priceCents: 20000,
                soldAt: ISO8601DateFormatter().date(from: "2026-04-25T14:00:00Z")!,
                grader: "PSA",
                grade: "10",
                condition: "Graded",
                url: URL(string: "https://www.ebay.com/itm/002"),
                anomalyFlag: nil
            ),
        ]
        return CompRepository.Decoded(
            gradingService: "PSA",
            grade: "10",
            headlinePriceCents: 19500,
            poketrace: pt,
            soldListings: soldListings,
            marketplaceURL: URL(string: "https://www.ebay.com/sch/i.html?_nkw=charizard+psa+10"),
            tcgplayerProductId: nil,
            fetchedAt: now,
            cacheHit: false
        )
    }

    /// A `Decoded` with poketrace nil and empty sold listings.
    static func makeDecodedEmpty() -> CompRepository.Decoded {
        let now = ISO8601DateFormatter().date(from: "2026-05-07T22:14:03Z")!
        return CompRepository.Decoded(
            gradingService: "PSA",
            grade: "10",
            headlinePriceCents: nil,
            poketrace: nil,
            soldListings: [],
            marketplaceURL: nil,
            tcgplayerProductId: nil,
            fetchedAt: now,
            cacheHit: false
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

    @Test("persists a single poketrace snapshot with soldListingsJSON when both are present")
    func persistsSinglePoketraceSnapshot() async throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let service = CompFetchService(context: context)
        let decoded = Self.makeDecodedWithPoketraceAndListings()
        let scan = Self.makeScan()
        context.insert(scan)
        try context.save()

        try await service.persist(scan: scan, decoded: decoded)

        let fetched: [GradedMarketSnapshot] = try context.fetch(FetchDescriptor<GradedMarketSnapshot>())
        // Single snapshot only — no PPT row.
        #expect(fetched.count == 1)
        let snap = try #require(fetched.first)
        #expect(snap.source == GradedMarketSnapshot.sourcePoketrace)
        #expect(snap.ptAvgCents == 19500)
        #expect(snap.headlinePriceCents == 19500)
        #expect(snap.poketraceCardId == "22222222-2222-2222-2222-222222222222")
        #expect(snap.cacheHit == false)
        // Sold listings persisted as JSON blob and round-trip correctly.
        #expect(snap.soldListingsJSON != nil)
        #expect(snap.soldListings.count == 2)
        #expect(snap.soldListings[0].sourceListingId == "ebay-001")
        // Marketplace URL
        #expect(snap.marketplaceURL != nil)
        // Scan headline mirrored.
        #expect(scan.reconciledHeadlinePriceCents == 19500)
        #expect(scan.reconciledSource == "poketrace")
    }

    @Test("persists minimal snapshot when poketrace is nil but soldListings non-empty")
    func persistsMinimalSnapshotForSoldListingsOnly() async throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let service = CompFetchService(context: context)
        let now = ISO8601DateFormatter().date(from: "2026-05-07T22:14:03Z")!
        let decoded = CompRepository.Decoded(
            gradingService: "PSA",
            grade: "10",
            headlinePriceCents: nil,
            poketrace: nil,
            soldListings: [
                SoldListing(
                    sourceListingId: "ebay-003",
                    title: "Sold only",
                    priceCents: 15000,
                    soldAt: now,
                    grader: "PSA",
                    grade: "10",
                    condition: nil,
                    url: nil,
                    anomalyFlag: nil
                )
            ],
            marketplaceURL: nil,
            tcgplayerProductId: nil,
            fetchedAt: now,
            cacheHit: false
        )
        let scan = Self.makeScan()
        context.insert(scan)
        try context.save()

        try await service.persist(scan: scan, decoded: decoded)

        let fetched: [GradedMarketSnapshot] = try context.fetch(FetchDescriptor<GradedMarketSnapshot>())
        #expect(fetched.count == 1)
        let snap = try #require(fetched.first)
        #expect(snap.ptAvgCents == nil)
        #expect(snap.headlinePriceCents == nil)
        #expect(snap.soldListings.count == 1)
        #expect(snap.soldListings[0].sourceListingId == "ebay-003")
    }

    @Test("inserts no snapshot when both poketrace and soldListings are absent")
    func insertsNoSnapshotWhenBothAbsent() async throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let service = CompFetchService(context: context)
        let decoded = Self.makeDecodedEmpty()
        let scan = Self.makeScan()
        context.insert(scan)
        try context.save()

        try await service.persist(scan: scan, decoded: decoded)

        let fetched: [GradedMarketSnapshot] = try context.fetch(FetchDescriptor<GradedMarketSnapshot>())
        #expect(fetched.isEmpty)
    }

    @Test("refetch replaces prior snapshot, not appends")
    func refetchReplacesSnapshot() async throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let service = CompFetchService(context: context)
        let decoded = Self.makeDecodedWithPoketraceAndListings()
        let scan = Self.makeScan()
        context.insert(scan)
        try context.save()

        // Two successive persists — should yield exactly 1 snapshot row.
        try await service.persist(scan: scan, decoded: decoded)
        try await service.persist(scan: scan, decoded: decoded)

        let fetched: [GradedMarketSnapshot] = try context.fetch(FetchDescriptor<GradedMarketSnapshot>())
        #expect(fetched.count == 1)
    }
}

@Suite("CompFetchService.classify")
struct CompFetchServiceClassifyTests {
    @Test("noMarketData maps to no_data with Poketrace-flavored message")
    func mapsNoMarketData() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.noMarketData)
        #expect(state == .noData)
        #expect(message.localizedCaseInsensitiveContains("poketrace"))
    }

    @Test("productNotResolved also maps to no_data, with distinct copy")
    func mapsProductNotResolved() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.productNotResolved)
        #expect(state == .noData)
        #expect(message.localizedCaseInsensitiveContains("couldn't find"))
    }

    @Test("upstreamUnavailable maps to failed with Poketrace wording")
    func mapsUpstream() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.upstreamUnavailable)
        #expect(state == .failed)
        #expect(message.localizedCaseInsensitiveContains("poketrace"))
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
