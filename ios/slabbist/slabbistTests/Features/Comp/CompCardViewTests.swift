import Testing
import Foundation
import SwiftData
@testable import slabbist

/// Unit tests for `CompCardView`'s hero-value fallback logic. Snapshot
/// rendering lives in `CompCardViewSnapshotTests`; these tests assert
/// the *intent* of the fallback — i.e. when `reconciledHeadlinePriceCents`
/// is nil but the ladder has cells, the hero surfaces the nearest grade
/// as an explicit `.estimated`. The fixture-table form makes the
/// adjacency rules legible alongside the code under test.
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

    /// PPT snapshot with optional per-tier cents. Mirrors the
    /// production write shape (one `@Model` row per source).
    private static func makePPT(
        gradingService: String,
        grade: String,
        psa7: Int64? = nil,
        psa8: Int64? = nil,
        psa9: Int64? = nil,
        psa9_5: Int64? = nil,
        psa10: Int64? = nil,
        bgs10: Int64? = nil,
        cgc10: Int64? = nil,
        sgc10: Int64? = nil,
        in context: ModelContext
    ) -> GradedMarketSnapshot {
        let snap = GradedMarketSnapshot(
            identityId: identityId,
            gradingService: gradingService,
            grade: grade,
            source: GradedMarketSnapshot.sourcePPT,
            headlinePriceCents: nil,           // hero is nil — that's the scenario
            loosePriceCents: nil,
            psa7PriceCents: psa7,
            psa8PriceCents: psa8,
            psa9PriceCents: psa9,
            psa9_5PriceCents: psa9_5,
            psa10PriceCents: psa10,
            bgs10PriceCents: bgs10,
            cgc10PriceCents: cgc10,
            sgc10PriceCents: sgc10,
            priceHistoryJSON: nil,
            fetchedAt: baseDate,
            cacheHit: false,
            isStaleFallback: false
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
        let ppt = Self.makePPT(gradingService: "PSA", grade: "10", psa9: 6_800, psa10: 18_500, in: container.mainContext)
        let view = CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: nil)
        #expect(view.heroValue == .confident(cents: 18_750))
    }

    /// PSA 10 with no reconciled price but PSA 9 in the ladder: hero is
    /// `.estimated` from PSA 9. This is the headline bug — without the
    /// fallback, the user sees "—" while the ladder has a real number.
    @Test("heroValue is .estimated when reconciled is nil and a sibling tier exists")
    func estimatedWhenReconciledNilButLadderHasSibling() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "10", reconciled: nil, in: container.mainContext)
        let ppt = Self.makePPT(gradingService: "PSA", grade: "10", psa9: 6_800, in: container.mainContext)
        let view = CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: nil)
        #expect(view.heroValue == .estimated(cents: 6_800, sourceTier: "PSA 9"))
    }

    /// Empty ladder + nil reconciled: hero is `.unavailable`. This is
    /// the "no data at all" floor — preserves the existing em-dash.
    @Test("heroValue is .unavailable when neither reconciled nor ladder has values")
    func unavailableWhenEverythingIsEmpty() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "10", reconciled: nil, in: container.mainContext)
        let view = CompCardView(scan: scan, pptSnapshot: nil, poketraceSnapshot: nil)
        #expect(view.heroValue == .unavailable)
    }

    // MARK: - nearestLadderTier adjacency table
    //
    // The adjacency rule is **intra-grader only**: a PSA 10 estimate
    // walks PSA 9.5 → PSA 9 → PSA 8 → PSA 7. It never crosses into
    // CGC / BGS / SGC because graders trade at different premiums
    // (BGS Black Label ≫ PSA 10 ≫ CGC 10 for the same card), and a
    // cross-grader walk would silently lowball the dealer's offer.
    // BGS / CGC / SGC ladders only carry the top tier in our schema,
    // so there is no same-grader sibling — those cases fall through
    // to `.unavailable` (dealer sets manual price / refreshes comp).

    /// PSA 10: prefers PSA 9.5, then PSA 9, then PSA 8, then PSA 7.
    /// Walk each step by knocking out the higher-preference tiers.
    @Test("PSA 10 adjacency walk descends within PSA: 9.5 > 9 > 8 > 7")
    func psa10AdjacencyWalk() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "10", reconciled: nil, in: container.mainContext)

        // Has all PSA tiers — picks PSA 9.5 (highest preference).
        let pptAll = Self.makePPT(
            gradingService: "PSA", grade: "10",
            psa7: 2_400, psa8: 3_400, psa9: 6_800, psa9_5: 11_200,
            in: container.mainContext
        )
        var view = CompCardView(scan: scan, pptSnapshot: pptAll, poketraceSnapshot: nil)
        #expect(view.nearestLadderTier()?.label == "PSA 9.5")
        #expect(view.nearestLadderTier()?.cents == 11_200)

        // No 9.5 → PSA 9 wins.
        let pptNo9_5 = Self.makePPT(
            gradingService: "PSA", grade: "10",
            psa7: 2_400, psa8: 3_400, psa9: 6_800,
            in: container.mainContext
        )
        view = CompCardView(scan: scan, pptSnapshot: pptNo9_5, poketraceSnapshot: nil)
        #expect(view.nearestLadderTier()?.label == "PSA 9")

        // No 9.5, no 9 → PSA 8 wins.
        let pptPSA8 = Self.makePPT(
            gradingService: "PSA", grade: "10",
            psa7: 2_400, psa8: 3_400,
            in: container.mainContext
        )
        view = CompCardView(scan: scan, pptSnapshot: pptPSA8, poketraceSnapshot: nil)
        #expect(view.nearestLadderTier()?.label == "PSA 8")

        // Only PSA 7 left → PSA 7.
        let pptPSA7 = Self.makePPT(
            gradingService: "PSA", grade: "10",
            psa7: 2_400,
            in: container.mainContext
        )
        view = CompCardView(scan: scan, pptSnapshot: pptPSA7, poketraceSnapshot: nil)
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
        let ppt = Self.makePPT(
            gradingService: "PSA", grade: "10",
            bgs10: 21_500, cgc10: 16_800,
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: nil)
        #expect(view.nearestLadderTier() == nil,
                "intra-grader rule: PSA 10 must not estimate from BGS 10 or CGC 10")
        #expect(view.heroValue == .unavailable)
    }

    /// PSA 9 walks PSA 9.5 → PSA 8 → PSA 7. Intra-grader only.
    @Test("PSA 9 adjacency walk descends within PSA: 9.5 > 8 > 7")
    func psa9AdjacencyWalk() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "9", reconciled: nil, in: container.mainContext)
        let ppt = Self.makePPT(
            gradingService: "PSA", grade: "9",
            psa9_5: 11_200,
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: nil)
        #expect(view.nearestLadderTier()?.label == "PSA 9.5")
    }

    /// BGS 10 has no intra-grader sibling in our schema (no `bgs_9_5`
    /// column on the snapshot). Returns nil even when PSA tiers are
    /// populated — the dealer-safe direction.
    @Test("BGS 10 returns nil — no intra-grader sibling, never crosses to PSA")
    func bgs10HasNoSiblingDoesNotCrossToPsa() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .BGS, grade: "10", reconciled: nil, in: container.mainContext)
        let ppt = Self.makePPT(
            gradingService: "BGS", grade: "10",
            psa9_5: 11_200, psa10: 18_500,
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: nil)
        #expect(view.nearestLadderTier() == nil)
        #expect(view.heroValue == .unavailable)
    }

    /// CGC 10 likewise has no intra-grader sibling — never falls back
    /// to PSA / BGS, even when they're populated.
    @Test("CGC 10 returns nil — no intra-grader sibling, never crosses graders")
    func cgc10HasNoSiblingDoesNotCrossGraders() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .CGC, grade: "10", reconciled: nil, in: container.mainContext)
        let ppt = Self.makePPT(
            gradingService: "CGC", grade: "10",
            psa9_5: 11_200, bgs10: 21_500,
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: nil)
        #expect(view.nearestLadderTier() == nil)
        #expect(view.heroValue == .unavailable)
    }

    /// SGC 10 / TAG: same as BGS/CGC — no intra-grader sibling, no
    /// cross-grader fallback. Conservative default.
    @Test("SGC 10 returns nil — no intra-grader sibling, no cross-grader fallback")
    func sgcHasNoFallback() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .SGC, grade: "10", reconciled: nil, in: container.mainContext)
        let ppt = Self.makePPT(
            gradingService: "SGC", grade: "10",
            psa9: 6_800, psa10: 18_500,
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: nil)
        #expect(view.nearestLadderTier() == nil)
    }

    /// No ladder data on any tier → nil.
    @Test("nearestLadderTier returns nil when no tier exists")
    func nilWhenNoTierExists() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "10", reconciled: nil, in: container.mainContext)
        let view = CompCardView(scan: scan, pptSnapshot: nil, poketraceSnapshot: nil)
        #expect(view.nearestLadderTier() == nil)
    }

    /// P2.9: explicit walk-vs-no-walk anchor. With the ladder populated
    /// AND `reconciledHeadlinePriceCents == nil`, the hero MUST land
    /// on `.estimated` (not `.unavailable`). This is the load-bearing
    /// regression guard: if a future refactor of `heroValue` swallows
    /// the `nearestLadderTier()` branch, this test fires.
    @Test("populated ladder + nil reconciled produces .estimated, not .unavailable")
    func ladderPopulatedReconciledNilProducesEstimated() throws {
        let container = try Self.makeContainer()
        let scan = Self.makeScan(grader: .PSA, grade: "10", reconciled: nil, in: container.mainContext)
        let ppt = Self.makePPT(
            gradingService: "PSA", grade: "10",
            psa9: 6_800,
            in: container.mainContext
        )
        let view = CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: nil)
        switch view.heroValue {
        case .estimated(let cents, let source):
            #expect(cents == 6_800)
            #expect(source == "PSA 9")
        case .confident, .unavailable:
            Issue.record("hero must be .estimated, got \(view.heroValue)")
        }
    }
}
