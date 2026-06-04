import Testing
import Foundation
import SwiftData
@testable import slabbist

/// Unit tests for `CompCardView`'s hero-value fallback logic. Snapshot
/// rendering lives in `CompCardViewSnapshotTests`; these tests assert
/// the *intent* of the fallback — i.e. when `reconciledHeadlinePriceCents`
/// is nil but the ptTierPricesCents ladder has cells, the hero surfaces the
/// nearest grade as an explicit `.estimated`.
///
/// **Poketrace-only (post-PPT-removal).** All fixtures use a single
/// Poketrace snapshot and the new `CompCardView(scan:snapshot:)` API.
@Suite("CompCardView hero fallback", .serialized)
@MainActor
struct CompCardViewTests {

    // MARK: - Fixtures

    private static let identityId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let baseDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private static func makeContainer() throws -> ModelContainer {
        try InMemoryModelContainer.make(for: [Scan.self, GradedMarketSnapshot.self])
    }

    private static func makeScan(
        grader: Grader,
        grade: String,
        reconciled: Int64?,
        in context: ModelContext
    ) -> Scan {
        let scan = Scan(
            id: UUID(),
            storeId: UUID(),
            lotId: UUID(),
            userId: UUID(),
            grader: grader,
            certNumber: "12345678",
            grade: grade,
            gradedCardIdentityId: identityId,
            status: .validated,
            createdAt: baseDate,
            updatedAt: baseDate
        )
        scan.reconciledHeadlinePriceCents = reconciled
        context.insert(scan)
        return scan
    }

    /// Poketrace snapshot with tier prices encoded in `ptTierPricesJSON`.
    /// `headlinePriceCents` is nil to exercise the adjacency-walk path.
    private static func makeSnapshot(
        gradingService: String,
        grade: String,
        tierPrices: [String: Int64],
        in context: ModelContext
    ) -> GradedMarketSnapshot {
        let tierJSON = String(
            data: (try? JSONEncoder().encode(tierPrices)) ?? Data(),
            encoding: .utf8
        )
        let snap = GradedMarketSnapshot(
            identityId: identityId,
            gradingService: gradingService,
            grade: grade,
            source: GradedMarketSnapshot.sourcePoketrace,
            headlinePriceCents: nil,   // hero is nil — that's the scenario
            ptTierPricesJSON: tierJSON,
            priceHistoryJSON: nil,
            fetchedAt: baseDate,
            cacheHit: false
        )
        context.insert(snap)
        return snap
    }

    // MARK: - heroValue states

    /// When `reconciledHeadlinePriceCents` is set, hero is confident
    /// regardless of what the ladder says.
    @Test("heroValue is .confident when reconciled is non-nil")
    func confidentWhenReconciled() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "10", reconciled: 18_750, in: container.mainContext)
        let snapshot = Self.makeSnapshot(
            gradingService: "PSA", grade: "10",
            tierPrices: ["psa_9": 6_800, "psa_10": 18_500],
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, snapshot: snapshot)
        #expect(view.heroValue == .confident(cents: 18_750))
    }

    /// PSA 10 with no reconciled price but PSA 9 in the ladder: hero is
    /// `.estimated` from PSA 9. This is the headline bug — without the
    /// fallback, the user sees "—" while the ladder has a real number.
    @Test("heroValue is .estimated when reconciled is nil and a sibling tier exists")
    func estimatedWhenReconciledNilButLadderHasSibling() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "10", reconciled: nil, in: container.mainContext)
        let snapshot = Self.makeSnapshot(
            gradingService: "PSA", grade: "10",
            tierPrices: ["psa_9": 6_800],
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, snapshot: snapshot)
        #expect(view.heroValue == .estimated(cents: 6_800, sourceTier: "PSA 9"))
    }

    /// Empty snapshot + nil reconciled: hero is `.unavailable`.
    @Test("heroValue is .unavailable when neither reconciled nor ladder has values")
    func unavailableWhenEverythingIsEmpty() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "10", reconciled: nil, in: container.mainContext)
        let view = CompCardView(scan: scan, snapshot: nil)
        #expect(view.heroValue == .unavailable)
    }

    // MARK: - nearestLadderTier adjacency table
    //
    // The adjacency rule is **intra-grader only**: a PSA 10 estimate
    // walks PSA 9.5 → PSA 9 → PSA 8 → PSA 7. It never crosses into
    // CGC / BGS / SGC because graders trade at different premiums.
    // BGS / CGC / SGC ladders only carry the top tier in our schema,
    // so there is no same-grader sibling — those cases fall through
    // to `.unavailable` (dealer sets manual price / refreshes comp).

    /// PSA 10: prefers PSA 9.5, then PSA 9, then PSA 8, then PSA 7.
    @Test("PSA 10 adjacency walk descends within PSA: 9.5 > 9 > 8 > 7")
    func psa10AdjacencyWalk() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "10", reconciled: nil, in: container.mainContext)

        // Has all PSA tiers — picks PSA 9.5 (highest preference).
        let snapAll = Self.makeSnapshot(
            gradingService: "PSA", grade: "10",
            tierPrices: ["psa_7": 2_400, "psa_8": 3_400, "psa_9": 6_800, "psa_9_5": 11_200],
            in: container.mainContext
        )
        var view = CompCardView(scan: scan, snapshot: snapAll)
        #expect(view.nearestLadderTier()?.label == "PSA 9.5")
        #expect(view.nearestLadderTier()?.cents == 11_200)

        // No 9.5 → PSA 9 wins.
        let snapNo9_5 = Self.makeSnapshot(
            gradingService: "PSA", grade: "10",
            tierPrices: ["psa_7": 2_400, "psa_8": 3_400, "psa_9": 6_800],
            in: container.mainContext
        )
        view = CompCardView(scan: scan, snapshot: snapNo9_5)
        #expect(view.nearestLadderTier()?.label == "PSA 9")

        // No 9.5, no 9 → PSA 8 wins.
        let snapPSA8 = Self.makeSnapshot(
            gradingService: "PSA", grade: "10",
            tierPrices: ["psa_7": 2_400, "psa_8": 3_400],
            in: container.mainContext
        )
        view = CompCardView(scan: scan, snapshot: snapPSA8)
        #expect(view.nearestLadderTier()?.label == "PSA 8")

        // Only PSA 7 left → PSA 7.
        let snapPSA7 = Self.makeSnapshot(
            gradingService: "PSA", grade: "10",
            tierPrices: ["psa_7": 2_400],
            in: container.mainContext
        )
        view = CompCardView(scan: scan, snapshot: snapPSA7)
        #expect(view.nearestLadderTier()?.label == "PSA 7")
    }

    /// PSA 10 estimate MUST NOT use a populated BGS 10 / CGC 10 cell —
    /// even though both are in the snapshot, the dealer-safe direction
    /// is "no estimate" rather than "wrong-grader estimate" that would
    /// undervalue a BGS Black Label scan.
    @Test("PSA 10 with only BGS/CGC siblings returns nil — no cross-grader walk")
    func psa10NeverCrossesIntoBgsOrCgc() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "10", reconciled: nil, in: container.mainContext)
        let snapshot = Self.makeSnapshot(
            gradingService: "PSA", grade: "10",
            tierPrices: ["bgs_10": 21_500, "cgc_10": 16_800],
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, snapshot: snapshot)
        #expect(view.nearestLadderTier() == nil,
                "intra-grader rule: PSA 10 must not estimate from BGS 10 or CGC 10")
        #expect(view.heroValue == .unavailable)
    }

    /// PSA 9 walks PSA 9.5 → PSA 8 → PSA 7. Intra-grader only.
    @Test("PSA 9 adjacency walk descends within PSA: 9.5 > 8 > 7")
    func psa9AdjacencyWalk() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "9", reconciled: nil, in: container.mainContext)
        let snapshot = Self.makeSnapshot(
            gradingService: "PSA", grade: "9",
            tierPrices: ["psa_9_5": 11_200],
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, snapshot: snapshot)
        #expect(view.nearestLadderTier()?.label == "PSA 9.5")
    }

    /// BGS 10 has no intra-grader sibling. Returns nil even when PSA tiers
    /// are populated — the dealer-safe direction.
    @Test("BGS 10 returns nil — no intra-grader sibling, never crosses to PSA")
    func bgs10HasNoSiblingDoesNotCrossToPsa() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .BGS, grade: "10", reconciled: nil, in: container.mainContext)
        let snapshot = Self.makeSnapshot(
            gradingService: "BGS", grade: "10",
            tierPrices: ["psa_9_5": 11_200, "psa_10": 18_500],
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, snapshot: snapshot)
        #expect(view.nearestLadderTier() == nil)
        #expect(view.heroValue == .unavailable)
    }

    /// CGC 10 likewise has no intra-grader sibling.
    @Test("CGC 10 returns nil — no intra-grader sibling, never crosses graders")
    func cgc10HasNoSiblingDoesNotCrossGraders() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .CGC, grade: "10", reconciled: nil, in: container.mainContext)
        let snapshot = Self.makeSnapshot(
            gradingService: "CGC", grade: "10",
            tierPrices: ["psa_9_5": 11_200, "bgs_10": 21_500],
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, snapshot: snapshot)
        #expect(view.nearestLadderTier() == nil)
        #expect(view.heroValue == .unavailable)
    }

    /// SGC 10: same as BGS/CGC — no intra-grader sibling, no cross-grader
    /// fallback.
    @Test("SGC 10 returns nil — no intra-grader sibling, no cross-grader fallback")
    func sgcHasNoFallback() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .SGC, grade: "10", reconciled: nil, in: container.mainContext)
        let snapshot = Self.makeSnapshot(
            gradingService: "SGC", grade: "10",
            tierPrices: ["psa_9": 6_800, "psa_10": 18_500],
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, snapshot: snapshot)
        #expect(view.nearestLadderTier() == nil)
    }

    /// No ladder data on any tier → nil.
    @Test("nearestLadderTier returns nil when no tier exists")
    func nilWhenNoTierExists() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "10", reconciled: nil, in: container.mainContext)
        let view = CompCardView(scan: scan, snapshot: nil)
        #expect(view.nearestLadderTier() == nil)
    }

    /// With the ladder populated AND `reconciledHeadlinePriceCents == nil`,
    /// the hero MUST land on `.estimated` (not `.unavailable`). This is
    /// the load-bearing regression guard for the adjacency-walk path.
    @Test("populated ladder + nil reconciled produces .estimated, not .unavailable")
    func ladderPopulatedReconciledNilProducesEstimated() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "10", reconciled: nil, in: container.mainContext)
        let snapshot = Self.makeSnapshot(
            gradingService: "PSA", grade: "10",
            tierPrices: ["psa_9": 6_800],
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, snapshot: snapshot)
        switch view.heroValue {
        case .estimated(let cents, let source):
            #expect(cents == 6_800)
            #expect(source == "PSA 9")
        case .confident, .unavailable:
            Issue.record("hero must be .estimated, got \(view.heroValue)")
        }
    }
}
