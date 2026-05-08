import Testing
import SwiftUI
import SnapshotTesting
@testable import slabbist

/// Snapshot tests for `CompSparklineView`.
///
/// Recommended simulator: **iPhone 17 / iOS 26.x**. Snapshots are
/// pixel-compared at `precision: 0.99` so minor antialiasing differences
/// between machines should not flake — but a different simulator scale
/// or OS version may. Re-record with `withSnapshotTesting(record: .all)`
/// or by setting `SNAPSHOT_TESTING_RECORD=1` in the test scheme's env.
///
/// Each case uses a fixed-frame container (320x32) with a black
/// background so the gold stroke renders against a deterministic field.
/// Dates are pinned to a constant epoch so the x-axis layout is stable
/// across runs.
///
/// `.serialized` because `assertSnapshot` writes reference images on
/// first run; running cases in parallel would race the same suite-level
/// `__Snapshots__` directory.
@Suite("CompSparklineView snapshots", .serialized)
@MainActor
struct CompSparklineViewSnapshotTests {

    /// Anchor date — pinned to a fixed reference-time so the rendered
    /// path geometry is stable across machines / clocks.
    private static let baseDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

    /// Wraps a sparkline in a fixed-frame, black-background container
    /// so its `GeometryReader` resolves to a known size and the gold
    /// stroke contrasts deterministically.
    private static func host(_ points: [PriceHistoryPoint]) -> some View {
        CompSparklineView(points: points)
            .frame(width: 320, height: 32)
            .background(Color.black)
    }

    // MARK: - 1. 30-point series across 6 months (typical EN card)

    @Test("30-point series — typical EN card with curved trend")
    func thirtyPointEnglishCard() {
        let points: [PriceHistoryPoint] = (0..<30).map { i in
            // ~6 days between each point ≈ ~6 months total span.
            let ts = Self.baseDate.addingTimeInterval(Double(i) * 86_400 * 6)
            let cents = Int64(15_000 + Int(sin(Double(i) / 5) * 2_500) + i * 80)
            return PriceHistoryPoint(ts: ts, priceCents: cents)
        }
        assertSnapshot(of: Self.host(points), as: .image(precision: 0.99))
    }

    // MARK: - 2. 7-point series (typical JP card)

    @Test("7-point series — sparser JP-card-style data")
    func sevenPointJapaneseCard() {
        let prices: [Int64] = [9_800, 10_200, 9_500, 11_400, 12_100, 11_700, 12_900]
        let points: [PriceHistoryPoint] = prices.enumerated().map { (i, cents) in
            let ts = Self.baseDate.addingTimeInterval(Double(i) * 86_400 * 14)
            return PriceHistoryPoint(ts: ts, priceCents: cents)
        }
        assertSnapshot(of: Self.host(points), as: .image(precision: 0.99))
    }

    // MARK: - 3. 2-point series (minimum that draws)

    @Test("2-point series — minimum that draws a line")
    func twoPointMinimum() {
        let points: [PriceHistoryPoint] = [
            PriceHistoryPoint(ts: Self.baseDate, priceCents: 5_000),
            PriceHistoryPoint(ts: Self.baseDate.addingTimeInterval(86_400 * 30),
                              priceCents: 8_500)
        ]
        assertSnapshot(of: Self.host(points), as: .image(precision: 0.99))
    }

    // MARK: - 4. 1-point series (hidden — view collapses to background)

    @Test("1-point series — view hides path entirely")
    func onePointHidden() {
        let points: [PriceHistoryPoint] = [
            PriceHistoryPoint(ts: Self.baseDate, priceCents: 5_000)
        ]
        // Expect: black background only. The path branch never executes
        // because `points.count >= 2` is false.
        assertSnapshot(of: Self.host(points), as: .image(precision: 0.99))
    }

    // MARK: - 5. Empty series (hidden)

    @Test("empty series — view hides path entirely")
    func emptyHidden() {
        assertSnapshot(of: Self.host([]), as: .image(precision: 0.99))
    }

    // MARK: - 6. Flat-price series (all same value — flat-price guard)

    @Test("flat-price series — min == max, path hidden by guard")
    func flatPriceSeries() {
        let points: [PriceHistoryPoint] = (0..<10).map { i in
            let ts = Self.baseDate.addingTimeInterval(Double(i) * 86_400 * 3)
            return PriceHistoryPoint(ts: ts, priceCents: 7_500)
        }
        // The view's `minPrice < maxPrice` guard returns Path() so
        // nothing strokes; expect the same black background as the
        // empty / 1-point cases.
        assertSnapshot(of: Self.host(points), as: .image(precision: 0.99))
    }
}
