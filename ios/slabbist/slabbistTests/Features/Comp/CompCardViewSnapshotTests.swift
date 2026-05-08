import Testing
import SwiftUI
import SwiftData
import SnapshotTesting
@testable import slabbist

/// Snapshot tests for `CompCardView`.
///
/// Recommended simulator: **iPhone 17 / iOS 26.x**. The card uses
/// `Spacing.l` padding and a custom serif font (`SlabFont`) that loads
/// from the host app bundle, so font availability + scaling depend on
/// the simulator. `precision: 0.99` absorbs minor antialiasing drift.
///
/// Each case is rendered at a fixed 380x560 frame (close to an iPhone
/// 17's content width minus the page padding; taller than the prior
/// 480 because the side-by-side sources strip + sparkline toggle
/// together stretch the card vertically) and snapshotted in both light
/// and dark color schemes — that's the SnapshotTesting trait hook.
/// `.serialized` because `assertSnapshot` writes a single
/// reference-image directory and parallel runs would race it.
///
/// **Two snapshots per slab.** Since Task 12, a single
/// `(identityId, service, grade)` can have up to two snapshot rows —
/// one with `source == "pokemonpricetracker"` and one with `source == "poketrace"`.
/// `CompCardView` now takes both as separate optionals (plus the
/// originating `Scan` for the reconciled headline) so we build a
/// matched pair of fixtures in each test, mirroring how
/// `ScanDetailView` partitions its `@Query` results in production.
///
/// **SwiftData note:** `GradedMarketSnapshot` is `@Model`. Constructing
/// an instance ad-hoc (without inserting into a `ModelContext`) works
/// for read-only rendering but the `priceHistoryJSON → priceHistory`
/// derived property still decodes JSON via the model's accessor. We
/// build each fixture inside an in-memory `ModelContainer` (via
/// `InMemoryModelContainer.make()`) so that the `@Model` lifecycle
/// matches production usage and no observation wiring is missing.
@Suite("CompCardView snapshots", .serialized)
@MainActor
struct CompCardViewSnapshotTests {

    // MARK: - Container

    /// Fresh in-memory container per case, so model state can't leak
    /// between snapshots.
    private static func makeContainer() throws -> ModelContainer {
        try InMemoryModelContainer.make(for: [Scan.self, GradedMarketSnapshot.self])
    }

    /// Encodes a `[PriceHistoryPoint]` into the on-disk JSON shape that
    /// `GradedMarketSnapshot.priceHistoryJSON` uses (ISO-8601 dates,
    /// snake_case keys via `PriceHistoryPoint.CodingKeys`).
    private static func encodeHistory(_ history: [PriceHistoryPoint]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(data: (try? encoder.encode(history)) ?? Data(), encoding: .utf8) ?? "[]"
    }

    /// Anchor date for deterministic price-history timestamps. Pinned
    /// to a constant reference-time so the sparkline path is stable.
    private static let baseDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

    /// Stable identity UUID so every fixture references the same slab.
    private static let identityId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    /// Builds a synthetic `Scan` with deterministic fields. The scan's
    /// `reconciledHeadlinePriceCents` is the hero number — we set it
    /// explicitly so the test asserts the rendered hero, not whatever
    /// the production reconciliation logic happens to compute.
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

    /// Builds a PPT-shaped snapshot. Defaults match the prior single-
    /// source fixture so existing-feel assertions stay close to the
    /// shipped baseline.
    private static func makePPT(
        gradingService: String = "PSA",
        grade: String = "10",
        headlinePriceCents: Int64? = 18_500,
        loosePriceCents: Int64? = 400,
        psa7: Int64? = 2_400,
        psa8: Int64? = 3_400,
        psa9: Int64? = 6_800,
        psa9_5: Int64? = 11_200,
        psa10: Int64? = 18_500,
        bgs10: Int64? = 21_500,
        cgc10: Int64? = 16_800,
        sgc10: Int64? = 16_500,
        priceHistory: [PriceHistoryPoint]? = nil,
        isStaleFallback: Bool = false,
        pptURL: URL? = URL(string: "https://www.pokemonpricetracker.com/card/charizard-base-set"),
        in context: ModelContext
    ) -> GradedMarketSnapshot {
        let json = priceHistory.map { encodeHistory($0) }
        let snap = GradedMarketSnapshot(
            identityId: identityId,
            gradingService: gradingService,
            grade: grade,
            source: GradedMarketSnapshot.sourcePPT,
            headlinePriceCents: headlinePriceCents,
            loosePriceCents: loosePriceCents,
            psa7PriceCents: psa7,
            psa8PriceCents: psa8,
            psa9PriceCents: psa9,
            psa9_5PriceCents: psa9_5,
            psa10PriceCents: psa10,
            bgs10PriceCents: bgs10,
            cgc10PriceCents: cgc10,
            sgc10PriceCents: sgc10,
            pptTCGPlayerId: "243172",
            pptURL: pptURL,
            priceHistoryJSON: json,
            fetchedAt: baseDate,
            cacheHit: false,
            isStaleFallback: isStaleFallback
        )
        context.insert(snap)
        return snap
    }

    /// Builds a Poketrace-shaped snapshot. `ptAvgCents` mirrors
    /// `headlinePriceCents` to mirror the production
    /// `CompFetchService.persistSnapshots` write path.
    private static func makePoketrace(
        gradingService: String = "PSA",
        grade: String = "10",
        avgCents: Int64? = 19_000,
        lowCents: Int64? = 17_500,
        highCents: Int64? = 21_000,
        trend: String? = "up",
        confidence: String? = "high",
        saleCount: Int? = 14,
        priceHistory: [PriceHistoryPoint]? = nil,
        in context: ModelContext
    ) -> GradedMarketSnapshot {
        let json = priceHistory.map { encodeHistory($0) }
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
            priceHistoryJSON: json,
            fetchedAt: baseDate,
            cacheHit: false,
            isStaleFallback: false
        )
        context.insert(snap)
        return snap
    }

    /// Wraps `CompCardView` in a deterministic-size container with
    /// the app's dark background so layout doesn't bleed.
    private static func host(
        scan: Scan,
        ppt: GradedMarketSnapshot?,
        poketrace: GradedMarketSnapshot?
    ) -> some View {
        CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: poketrace)
            .padding(Spacing.l)
            .background(AppColor.ink)
    }

    /// Common snapshot configuration: a 380x560 fixed frame, both
    /// light and dark color schemes, 0.99 precision tolerance.
    private static func assertLightDark(
        _ view: some View,
        named name: String,
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let layout: SwiftUISnapshotLayout = .fixed(width: 380, height: 560)
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

    /// Synthesised price history used in cases that exercise the
    /// sparkline. Pinned to `baseDate` so the rendered chart path is
    /// byte-stable across runs.
    private static func sampleHistory(start cents: Int64) -> [PriceHistoryPoint] {
        (0..<12).map { i in
            let ts = baseDate.addingTimeInterval(Double(i) * 86_400 * 14)
            let value = Int64(cents + Int64(sin(Double(i) / 3) * 1_400) + Int64(i * 250))
            return PriceHistoryPoint(ts: ts, priceCents: value)
        }
    }

    // MARK: - 1. Both sources populated (avg of 2 sources)

    @Test("both sources — PPT + Poketrace side-by-side, 'avg of 2 sources' caption")
    func bothSources_psa10() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .PSA, grade: "10",
            reconciledHeadlinePriceCents: 18_750, // (18_500 + 19_000) / 2
            in: context
        )
        let ppt = Self.makePPT(
            priceHistory: Self.sampleHistory(start: 15_500),
            in: context
        )
        let pt = Self.makePoketrace(
            priceHistory: Self.sampleHistory(start: 16_200),
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, ppt: ppt, poketrace: pt),
            named: "both-sources-psa10"
        )
    }

    // MARK: - 2. PPT only (Poketrace cell shows "no data", caption "PPT only")

    @Test("PPT only — Poketrace cell shows 'no data', caption 'PPT only'")
    func pptOnly_psa10() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .PSA, grade: "10",
            reconciledHeadlinePriceCents: 18_500,
            in: context
        )
        let ppt = Self.makePPT(
            priceHistory: Self.sampleHistory(start: 15_500),
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, ppt: ppt, poketrace: nil),
            named: "ppt-only-psa10"
        )
    }

    // MARK: - 3. Poketrace only (PPT cell shows "no data", caption "Poketrace only")

    @Test("Poketrace only — PPT cell shows 'no data', caption 'Poketrace only'")
    func poketraceOnly_psa9() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .PSA, grade: "9",
            reconciledHeadlinePriceCents: 6_800,
            in: context
        )
        let pt = Self.makePoketrace(
            grade: "9",
            avgCents: 6_800,
            lowCents: 6_100,
            highCents: 7_400,
            trend: "stable",
            confidence: "medium",
            saleCount: 6,
            priceHistory: Self.sampleHistory(start: 6_200),
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, ppt: nil, poketrace: pt),
            named: "poketrace-only-psa9"
        )
    }

    // MARK: - 4. BGS 10 headline (gold border on BGS cell)

    @Test("BGS 10 — gold border lands on BGS cell, not PSA")
    func bgs10Headline() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .BGS, grade: "10",
            reconciledHeadlinePriceCents: 21_500,
            in: context
        )
        let ppt = Self.makePPT(
            gradingService: "BGS", grade: "10",
            headlinePriceCents: 21_500,
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, ppt: ppt, poketrace: nil),
            named: "bgs10"
        )
    }

    // MARK: - 5. JP card (raw only, every tier nil)

    @Test("JP card — raw only, all PSA/BGS/CGC/SGC tiers nil")
    func japaneseRawOnly() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .PSA, grade: "10",
            reconciledHeadlinePriceCents: nil,
            in: context
        )
        let ppt = Self.makePPT(
            gradingService: "PSA", grade: "10",
            headlinePriceCents: nil,
            loosePriceCents: 350,
            psa7: nil, psa8: nil, psa9: nil, psa9_5: nil, psa10: nil,
            bgs10: nil, cgc10: nil, sgc10: nil,
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, ppt: ppt, poketrace: nil),
            named: "jp-raw-only"
        )
    }

    // MARK: - 6. Stale fallback (caveat row visible)

    @Test("stale fallback — caveat row with offline chip")
    func staleFallback() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .PSA, grade: "10",
            reconciledHeadlinePriceCents: 18_500,
            in: context
        )
        let ppt = Self.makePPT(
            priceHistory: Self.sampleHistory(start: 14_500),
            isStaleFallback: true,
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, ppt: ppt, poketrace: nil),
            named: "stale-fallback"
        )
    }

    // MARK: - 7. Unsupported tier (TAG 10)

    @Test("unsupported tier — TAG 10 with caveat copy")
    func unsupportedTagTier() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .TAG, grade: "10",
            reconciledHeadlinePriceCents: nil,
            in: context
        )
        let ppt = Self.makePPT(
            gradingService: "TAG", grade: "10",
            headlinePriceCents: nil,
            psa10: 18_500,
            bgs10: nil, cgc10: nil, sgc10: nil,
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, ppt: ppt, poketrace: nil),
            named: "tag10-unsupported"
        )
    }

    // MARK: - 8. Empty state (no snapshots, no history, no URL)

    @Test("empty state — every tier nil, no history")
    func emptyState() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let scan = Self.makeScan(
            grader: .PSA, grade: "10",
            reconciledHeadlinePriceCents: nil,
            in: context
        )
        let ppt = Self.makePPT(
            gradingService: "PSA", grade: "10",
            headlinePriceCents: nil,
            loosePriceCents: nil,
            psa7: nil, psa8: nil, psa9: nil, psa9_5: nil, psa10: nil,
            bgs10: nil, cgc10: nil, sgc10: nil,
            pptURL: nil,
            in: context
        )
        try context.save()
        Self.assertLightDark(
            Self.host(scan: scan, ppt: ppt, poketrace: nil),
            named: "empty"
        )
    }
}
