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
/// Each case is rendered at a fixed 380x480 frame (close to an iPhone
/// 17's content width minus the page padding) and snapshotted in both
/// light and dark color schemes — that's the SnapshotTesting trait
/// hook. `.serialized` because `assertSnapshot` writes a single
/// reference-image directory and parallel runs would race it.
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
        try InMemoryModelContainer.make(for: [GradedMarketSnapshot.self])
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

    /// Builds + inserts a `GradedMarketSnapshot` in a fresh in-memory
    /// container and returns both. Tests keep the container alive for
    /// the duration of the snapshot render so the `@Model` instance
    /// stays valid.
    private static func makeSnapshot(
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
        pptURL: URL? = URL(string: "https://www.pokemonpricetracker.com/card/charizard-base-set")
    ) throws -> (ModelContainer, GradedMarketSnapshot) {
        let container = try makeContainer()
        let context = ModelContext(container)
        let json = priceHistory.map { encodeHistory($0) }
        let snap = GradedMarketSnapshot(
            identityId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
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
        try context.save()
        return (container, snap)
    }

    /// Wraps `CompCardView` in a deterministic-size container with
    /// the app's dark background so layout doesn't bleed.
    private static func host(_ snap: GradedMarketSnapshot) -> some View {
        CompCardView(snapshot: snap)
            .padding(Spacing.l)
            .background(AppColor.ink)
    }

    /// Common snapshot configuration: a 380x480 fixed frame, both
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
        let layout: SwiftUISnapshotLayout = .fixed(width: 380, height: 480)
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

    // MARK: - 1. PSA 10 full ladder + sparkline + good headline

    @Test("PSA 10 — full ladder + sparkline + headline")
    func psa10FullLadder() throws {
        let history: [PriceHistoryPoint] = (0..<12).map { i in
            let ts = Self.baseDate.addingTimeInterval(Double(i) * 86_400 * 14)
            let cents = Int64(15_500 + Int(sin(Double(i) / 3) * 1_400) + i * 250)
            return PriceHistoryPoint(ts: ts, priceCents: cents)
        }
        let (_, snap) = try Self.makeSnapshot(priceHistory: history)
        Self.assertLightDark(Self.host(snap), named: "psa10-full")
    }

    // MARK: - 2. BGS 10 headline (gold border on BGS cell)

    @Test("BGS 10 — gold border lands on BGS cell, not PSA")
    func bgs10Headline() throws {
        let (_, snap) = try Self.makeSnapshot(
            gradingService: "BGS",
            grade: "10",
            headlinePriceCents: 21_500,
            priceHistory: nil
        )
        Self.assertLightDark(Self.host(snap), named: "bgs10")
    }

    // MARK: - 3. JP card (raw only)

    @Test("JP card — raw only, all PSA/BGS/CGC/SGC tiers nil")
    func japaneseRawOnly() throws {
        let (_, snap) = try Self.makeSnapshot(
            gradingService: "PSA",
            grade: "10",
            headlinePriceCents: nil,
            loosePriceCents: 350,
            psa7: nil, psa8: nil, psa9: nil, psa9_5: nil, psa10: nil,
            bgs10: nil, cgc10: nil, sgc10: nil,
            priceHistory: nil
        )
        Self.assertLightDark(Self.host(snap), named: "jp-raw-only")
    }

    // MARK: - 4. Stale fallback (caveat row visible)

    @Test("stale fallback — caveat row with offline chip")
    func staleFallback() throws {
        let history: [PriceHistoryPoint] = (0..<6).map { i in
            let ts = Self.baseDate.addingTimeInterval(Double(i) * 86_400 * 21)
            return PriceHistoryPoint(ts: ts, priceCents: Int64(14_500 + i * 350))
        }
        let (_, snap) = try Self.makeSnapshot(
            priceHistory: history,
            isStaleFallback: true
        )
        Self.assertLightDark(Self.host(snap), named: "stale-fallback")
    }

    // MARK: - 5. Unsupported tier (TAG 10)

    @Test("unsupported tier — TAG 10 with caveat copy")
    func unsupportedTagTier() throws {
        let (_, snap) = try Self.makeSnapshot(
            gradingService: "TAG",
            grade: "10",
            headlinePriceCents: nil,
            psa10: 18_500,
            bgs10: nil, cgc10: nil, sgc10: nil,
            priceHistory: nil
        )
        Self.assertLightDark(Self.host(snap), named: "tag10-unsupported")
    }

    // MARK: - 6. Empty state (every tier nil, no history)

    @Test("empty state — every tier nil, no history")
    func emptyState() throws {
        let (_, snap) = try Self.makeSnapshot(
            gradingService: "PSA",
            grade: "10",
            headlinePriceCents: nil,
            loosePriceCents: nil,
            psa7: nil, psa8: nil, psa9: nil, psa9_5: nil, psa10: nil,
            bgs10: nil, cgc10: nil, sgc10: nil,
            priceHistory: nil,
            pptURL: nil
        )
        Self.assertLightDark(Self.host(snap), named: "empty")
    }
}
