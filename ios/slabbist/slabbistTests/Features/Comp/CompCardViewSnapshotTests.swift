import Testing
import SwiftUI
import SwiftData
import SnapshotTesting
@testable import slabbist

/// Snapshot tests for `CompCardView` (Poketrace-only, post-PPT-removal).
///
/// **Simulator:** iPhone 17 / iOS 26.x. Fixed 380×640 frame (taller than
/// the prior 560 to accommodate the sold-listings section).
///
/// Each test case captures light + dark, `precision: 0.99`.
/// `.serialized` because `assertSnapshot` shares a reference-image
/// directory.
///
/// **Snapshot cases:**
///   1. `poketraceWithSoldListings_psa10`  — Poketrace ladder + aggregates + sold-comps section
///   2. `poketraceNoSoldListings_psa9`     — Poketrace data, empty sold-listings (non-Scale degrade)
///   3. `bgs10Headline`                    — BGS 10 gold border on BGS cell
///   4. `rawOnlyNoGraded`                  — only "loose" tier in the map, no grade tiers
///   5. `noSnapshot`                       — nil snapshot, hero = "—"
@Suite("CompCardView snapshots", .serialized)
@MainActor
struct CompCardViewSnapshotTests {

    // MARK: - Container

    private static func makeContainer() throws -> ModelContainer {
        try InMemoryModelContainer.make(for: [Scan.self, GradedMarketSnapshot.self])
    }

    // MARK: - Encoding helpers

    private static func encodeHistory(_ history: [PriceHistoryPoint]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(data: (try? encoder.encode(history)) ?? Data(), encoding: .utf8) ?? "[]"
    }

    private static func encodeTierPrices(_ prices: [String: Int64]) -> String {
        String(data: (try? JSONEncoder().encode(prices)) ?? Data(), encoding: .utf8) ?? "{}"
    }

    private static func encodeSoldListings(_ listings: [SoldListing]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(data: (try? encoder.encode(listings)) ?? Data(), encoding: .utf8) ?? "[]"
    }

    /// Anchor date for deterministic price-history timestamps.
    private static let baseDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

    /// Stable identity UUID so every fixture references the same slab.
    private static let identityId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    // MARK: - Fixture builders

    private static func makeScan(
        grader: Grader = .PSA,
        grade: String = "10",
        reconciledHeadlinePriceCents: Int64?,
        in context: ModelContext
    ) -> Scan {
        let scan = Scan(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            storeId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            lotId: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            userId: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            grader: grader,
            certNumber: "12345678",
            grade: grade,
            gradedCardIdentityId: identityId,
            status: .validated,
            createdAt: baseDate,
            updatedAt: baseDate
        )
        scan.reconciledHeadlinePriceCents = reconciledHeadlinePriceCents
        context.insert(scan)
        return scan
    }

    /// Builds a Poketrace-shaped snapshot with optional tier prices,
    /// price history, and sold listings.
    private static func makePoketrace(
        gradingService: String = "PSA",
        grade: String = "10",
        avgCents: Int64? = 18_750,
        lowCents: Int64? = 17_500,
        highCents: Int64? = 21_000,
        trend: String? = "up",
        confidence: String? = "high",
        saleCount: Int? = 14,
        tierPrices: [String: Int64]? = nil,
        priceHistory: [PriceHistoryPoint]? = nil,
        soldListings: [SoldListing]? = nil,
        marketplaceURL: URL? = nil,
        in context: ModelContext
    ) -> GradedMarketSnapshot {
        let historyJSON = priceHistory.map { encodeHistory($0) }
        let tierJSON = tierPrices.map { encodeTierPrices($0) }
        let soldJSON = soldListings.map { encodeSoldListings($0) }
        let snap = GradedMarketSnapshot(
            identityId: identityId,
            gradingService: gradingService,
            grade: grade,
            source: GradedMarketSnapshot.sourcePoketrace,
            headlinePriceCents: avgCents,
            ptAvgCents: avgCents,
            ptLowCents: lowCents,
            ptHighCents: highCents,
            ptTrend: trend,
            ptConfidence: confidence,
            ptSaleCount: saleCount,
            poketraceCardId: "pt-card-id-placeholder",
            ptTierPricesJSON: tierJSON,
            priceHistoryJSON: historyJSON,
            marketplaceURL: marketplaceURL,
            soldListingsJSON: soldJSON,
            fetchedAt: baseDate,
            cacheHit: false
        )
        context.insert(snap)
        return snap
    }

    /// Wraps `CompCardView` in a deterministic container.
    private static func host(scan: Scan, snapshot: GradedMarketSnapshot?) -> some View {
        CompCardView(scan: scan, snapshot: snapshot)
            .padding(Spacing.l)
            .background(AppColor.ink)
    }

    /// Common snapshot configuration: fixed 380×640 frame, light + dark,
    /// 0.99 precision.
    private static func assertLightDark(
        _ view: some View,
        named name: String,
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let layout: SwiftUISnapshotLayout = .fixed(width: 380, height: 640)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.99,
                layout: layout,
                traits: .init(userInterfaceStyle: .light)
            ),
            named: "\(name)-light",
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.99,
                layout: layout,
                traits: .init(userInterfaceStyle: .dark)
            ),
            named: "\(name)-dark",
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }

    // MARK: - Stable history series

    private static func sampleHistory(start cents: Int64) -> [PriceHistoryPoint] {
        (0..<12).map { i in
            let ts = baseDate.addingTimeInterval(Double(i) * 86_400 * 14)
            let value = Int64(cents + Int64(sin(Double(i) / 3) * 1_400) + Int64(i * 250))
            return PriceHistoryPoint(ts: ts, priceCents: value)
        }
    }

    // MARK: - Stable sold listings

    private static let sampleSoldListings: [SoldListing] = [
        SoldListing(
            sourceListingId: "e1",
            title: "Charizard Base Set PSA 10 Gem Mint",
            priceCents: 18_200,
            soldAt: Date(timeIntervalSince1970: 700_000_000 - 86_400 * 2),
            grader: "PSA", grade: "10", condition: "Graded",
            url: URL(string: "https://www.ebay.com/itm/111"),
            anomalyFlag: nil
        ),
        SoldListing(
            sourceListingId: "e2",
            title: "Pokemon Charizard WOTC PSA 10",
            priceCents: 19_800,
            soldAt: Date(timeIntervalSince1970: 700_000_000 - 86_400 * 5),
            grader: "PSA", grade: "10", condition: "Graded",
            url: URL(string: "https://www.ebay.com/itm/222"),
            anomalyFlag: "outlier_high"
        ),
    ]

    // MARK: - 1. Poketrace with sold listings (PSA 10)

    @Test("Poketrace PSA 10 — ladder + aggregates + sold listings section")
    func poketraceWithSoldListings_psa10() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .PSA, grade: "10",
            reconciledHeadlinePriceCents: 18_750,
            in: context
        )
        let tierPrices: [String: Int64] = [
            "loose": 400, "psa_7": 2_400, "psa_8": 3_400, "psa_9": 6_800,
            "psa_9_5": 11_200, "psa_10": 18_500, "bgs_10": 21_500,
            "cgc_10": 16_800, "sgc_10": 16_500,
        ]
        let pt = Self.makePoketrace(
            tierPrices: tierPrices,
            priceHistory: Self.sampleHistory(start: 15_500),
            soldListings: Self.sampleSoldListings,
            marketplaceURL: URL(string: "https://www.ebay.com/sch/i.html?_nkw=charizard+psa+10"),
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, snapshot: pt),
            named: "poketrace-with-sold-listings-psa10"
        )
    }

    // MARK: - 2. Poketrace, no sold listings (non-Scale plan degrade)

    @Test("Poketrace PSA 9 — no sold listings — compact empty state")
    func poketraceNoSoldListings_psa9() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .PSA, grade: "9",
            reconciledHeadlinePriceCents: 6_800,
            in: context
        )
        let tierPrices: [String: Int64] = [
            "loose": 350, "psa_7": 1_800, "psa_8": 2_900, "psa_9": 6_800,
        ]
        let pt = Self.makePoketrace(
            grade: "9",
            avgCents: 6_800,
            lowCents: 6_100,
            highCents: 7_400,
            trend: "stable",
            confidence: "medium",
            saleCount: 6,
            tierPrices: tierPrices,
            priceHistory: Self.sampleHistory(start: 6_200),
            soldListings: [],  // empty — non-Scale degrade path
            marketplaceURL: URL(string: "https://www.ebay.com/sch/i.html?_nkw=charizard+psa+9"),
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, snapshot: pt),
            named: "poketrace-no-sold-listings-psa9"
        )
    }

    // MARK: - 3. BGS 10 headline (gold border on BGS cell)

    @Test("BGS 10 — gold border lands on BGS cell, not PSA")
    func bgs10Headline() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .BGS, grade: "10",
            reconciledHeadlinePriceCents: 21_500,
            in: context
        )
        let tierPrices: [String: Int64] = [
            "loose": 400, "psa_10": 18_500, "bgs_10": 21_500, "cgc_10": 16_800,
        ]
        let pt = Self.makePoketrace(
            gradingService: "BGS", grade: "10",
            avgCents: 21_500,
            lowCents: 20_000,
            highCents: 23_000,
            trend: nil,
            confidence: "medium",
            saleCount: 4,
            tierPrices: tierPrices,
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, snapshot: pt),
            named: "bgs10"
        )
    }

    // MARK: - 4. Raw-only (loose tier only, no grade tiers)

    @Test("Raw only — only 'loose' tier in the map, all grade tiers absent")
    func rawOnlyNoGraded() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .PSA, grade: "10",
            reconciledHeadlinePriceCents: nil,
            in: context
        )
        let pt = Self.makePoketrace(
            avgCents: nil,
            lowCents: nil,
            highCents: nil,
            trend: nil,
            confidence: nil,
            saleCount: nil,
            tierPrices: ["loose": 350],
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, snapshot: pt),
            named: "raw-only"
        )
    }

    // MARK: - 5. No snapshot

    @Test("No snapshot — hero shows '—', sold listings shows empty state")
    func noSnapshot() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .PSA, grade: "10",
            reconciledHeadlinePriceCents: nil,
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, snapshot: nil),
            named: "no-snapshot"
        )
    }
}
