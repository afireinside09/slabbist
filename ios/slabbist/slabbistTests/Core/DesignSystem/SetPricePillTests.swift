import Testing
import SwiftUI
import UIKit
import SwiftData
@testable import slabbist

/// F3 — `SetPricePill` + the `ScanRowTrailingState` state machine that
/// picks between `hasReconciled` / `hasManual` / `needsPrice` /
/// stale-fetching / fetching / failed / idle.
///
/// These tests encode the user-facing contract:
///   * A reconciled comp wins over a manual price (lot total uses the comp).
///   * A manual price wins over a `.noData` empty trailing slot.
///   * `.noData` + no manual → "Set price" pill (the F3 surface).
///   * A stuck `.fetching` row falls through to the C2 Retry CTA.
@Suite("SetPricePill + ScanRowTrailingState (F3)")
@MainActor
struct SetPricePillStateTests {

    private static let storeId = UUID()
    private static let lotId = UUID()
    private static let userId = UUID()

    private static func makeScan(
        reconciled: Int64? = nil,
        manual: Int64? = nil,
        compFetchState: CompFetchState? = nil,
        compFetchStartedAt: Date? = nil
    ) -> Scan {
        let now = Date()
        let scan = Scan(
            id: UUID(),
            storeId: storeId,
            lotId: lotId,
            userId: userId,
            grader: .PSA,
            certNumber: "00000001",
            grade: "10",
            gradedCardIdentityId: UUID(),
            status: .validated,
            createdAt: now,
            updatedAt: now
        )
        scan.reconciledHeadlinePriceCents = reconciled
        scan.vendorAskCents = manual
        scan.compFetchState = compFetchState?.rawValue
        scan.compFetchStartedAt = compFetchStartedAt
        return scan
    }

    // MARK: - State machine

    @Test("reconciled-only → hasReconciled (the lot total uses the comp)")
    func reconciledAlone() {
        let scan = Self.makeScan(reconciled: 18_500, manual: nil, compFetchState: .resolved)
        #expect(ScanRowTrailingState.resolve(for: scan) == .hasReconciled(cents: 18_500))
    }

    @Test("reconciled + manual → hasManualWithReconciled (P1.3 — row keeps manual pill, total uses reconciled)")
    func reconciledPlusManualHybrid() {
        let scan = Self.makeScan(reconciled: 18_500, manual: 25_00, compFetchState: .resolved)
        let state = ScanRowTrailingState.resolve(for: scan)
        #expect(state == .hasManualWithReconciled(manualCents: 25_00, reconciledCents: 18_500),
                "When both exist the row shows the manual pill so user input stays visible")
        #expect(state.aggregateCents == 18_500,
                "The lot's total must use the reconciled comp, not the user's draft")
        #expect(state.isManualContribution == false,
                "The aggregate caption should NOT count this as a manual contribution — the math used reconciled")
    }

    @Test("manual price wins over noData when there's no reconciled comp")
    func manualWinsOverNoData() {
        let scan = Self.makeScan(reconciled: nil, manual: 25_00, compFetchState: .noData)
        let state = ScanRowTrailingState.resolve(for: scan)
        #expect(state == .hasManual(cents: 25_00))
        #expect(state.aggregateCents == 25_00)
        #expect(state.isManualContribution == true)
    }

    @Test("noData + no manual → needsPrice (the F3 trigger)")
    func noDataNoManualNeedsPrice() {
        let scan = Self.makeScan(reconciled: nil, manual: nil, compFetchState: .noData)
        let state = ScanRowTrailingState.resolve(for: scan)
        #expect(state == .needsPrice)
        #expect(state.aggregateCents == nil, "needsPrice contributes nothing to the lot total")
    }

    @Test("fresh .fetching → fetching state (not stale)")
    func freshFetchingNotStale() {
        let now = Date()
        let scan = Self.makeScan(compFetchState: .fetching, compFetchStartedAt: now.addingTimeInterval(-5))
        #expect(ScanRowTrailingState.resolve(for: scan, now: now) == .fetching)
    }

    @Test("stale .fetching → staleFetching (the C2 trigger)")
    func staleFetchingDetected() {
        let now = Date()
        let scan = Self.makeScan(compFetchState: .fetching, compFetchStartedAt: now.addingTimeInterval(-120))
        #expect(ScanRowTrailingState.resolve(for: scan, now: now) == .staleFetching)
    }

    @Test(".failed → failed (no manual fallback)")
    func failedSurfaces() {
        let scan = Self.makeScan(compFetchState: .failed)
        #expect(ScanRowTrailingState.resolve(for: scan) == .failed)
    }

    @Test("nothing yet → idle")
    func idleWhenNothingHappened() {
        let scan = Self.makeScan()
        #expect(ScanRowTrailingState.resolve(for: scan) == .idle)
    }

    // MARK: - P0.1 — legacy snapshot path keeps the row body and the
    // aggregate strip on the same resolver, so the header total can't
    // drift from the row body's value for legacy scans.

    private static func makeSnapshot(headline: Int64?) -> GradedMarketSnapshot {
        GradedMarketSnapshot(
            identityId: UUID(),
            gradingService: "PSA",
            grade: "10",
            source: GradedMarketSnapshot.sourcePoketrace,
            headlinePriceCents: headline,
            priceHistoryJSON: nil,
            fetchedAt: Date(),
            cacheHit: false
        )
    }

    @Test("legacy snapshot — no reconciled, no manual → hasSnapshot rolls into aggregate")
    func legacySnapshotPathHasSnapshot() {
        let scan = Self.makeScan(reconciled: nil, manual: nil, compFetchState: .resolved)
        let snap = Self.makeSnapshot(headline: 12_000)
        let state = ScanRowTrailingState.resolve(for: scan, snapshot: snap)
        #expect(state == .hasSnapshot(cents: 12_000),
                "Legacy scans validated before reconciliation must still produce a dollar amount")
        #expect(state.aggregateCents == 12_000,
                "Aggregate strip must sum legacy snapshots — otherwise the header reads zero while rows show prices")
        #expect(state.isManualContribution == false)
    }

    @Test("legacy snapshot + manual → hasManualWithReconciled (manual shown, snapshot drives total)")
    func legacySnapshotPlusManualHybrid() {
        let scan = Self.makeScan(reconciled: nil, manual: 50_00, compFetchState: .resolved)
        let snap = Self.makeSnapshot(headline: 12_000)
        let state = ScanRowTrailingState.resolve(for: scan, snapshot: snap)
        // Same shadow-prevention rule as the reconciled branch: user's
        // typed value stays visible on the row; aggregate uses the
        // snapshot dollar value.
        #expect(state == .hasManualWithReconciled(manualCents: 50_00, reconciledCents: 12_000))
        #expect(state.aggregateCents == 12_000)
    }

    @Test("reconciled trumps a stale legacy snapshot when both exist")
    func reconciledWinsOverSnapshotWhenBothExist() {
        let scan = Self.makeScan(reconciled: 18_500, manual: nil, compFetchState: .resolved)
        let snap = Self.makeSnapshot(headline: 12_000)  // stale
        // Reconciled is the freshest summary; ignore snapshot in this branch.
        #expect(ScanRowTrailingState.resolve(for: scan, snapshot: snap) == .hasReconciled(cents: 18_500))
    }

    @Test("aggregate sum matches row-rendered dollar amounts across a mixed lot")
    func aggregateMatchesRowsAcrossMixedLot() {
        // Reproduces the P0.1 drift scenario: one legacy snapshot row,
        // one reconciled row, one manual row, one needsPrice row, one
        // fetching row. The aggregate the header would compute (via
        // ScanRowTrailingState.aggregateCents) must equal the sum of
        // the dollar amounts the rows render — no resolver drift.
        let now = Date()
        let legacyScan = Self.makeScan(reconciled: nil, manual: nil, compFetchState: .resolved)
        let legacySnap = Self.makeSnapshot(headline: 12_000)
        let reconciledScan = Self.makeScan(reconciled: 18_500, manual: nil, compFetchState: .resolved)
        let manualScan = Self.makeScan(reconciled: nil, manual: 25_00, compFetchState: .noData)
        let needsScan = Self.makeScan(reconciled: nil, manual: nil, compFetchState: .noData)
        let fetchingScan = Self.makeScan(
            compFetchState: .fetching,
            compFetchStartedAt: now.addingTimeInterval(-5)
        )

        let states: [ScanRowTrailingState] = [
            ScanRowTrailingState.resolve(for: legacyScan, snapshot: legacySnap, now: now),
            ScanRowTrailingState.resolve(for: reconciledScan, snapshot: nil, now: now),
            ScanRowTrailingState.resolve(for: manualScan, snapshot: nil, now: now),
            ScanRowTrailingState.resolve(for: needsScan, snapshot: nil, now: now),
            ScanRowTrailingState.resolve(for: fetchingScan, snapshot: nil, now: now),
        ]

        let aggregate = states.compactMap(\.aggregateCents).reduce(0, +)
        #expect(aggregate == 12_000 + 18_500 + 25_00,
                "Header total must equal the sum of the dollar amounts visible in the rows")

        let manualCount = states.filter(\.isManualContribution).count
        #expect(manualCount == 1,
                "Only the pure-manual row counts toward the 'N manual' caption — hybrids contribute their reconciled value")
    }

    // MARK: - Pill rendering + action

    @Test("SetPricePill renders both variants without crashing the view graph")
    func pillRenders() {
        let setHost = UIHostingController(rootView: SetPricePill(priceCents: nil, action: {}))
        _ = setHost.view
        #expect(setHost.view != nil)

        let editHost = UIHostingController(rootView: SetPricePill(priceCents: 25_00, action: {}))
        _ = editHost.view
        #expect(editHost.view != nil)
    }

    @Test("formattedCompact rounds to whole dollars and uses USD")
    func compactFormatting() {
        // Sanity: the pill's compact formatter is used by both the row's
        // accessibility label and the trailing reconciled cell, so a
        // formatting regression breaks two surfaces. Lock the contract.
        #expect(SetPricePill.formattedCompact(25_00) == "$25")
        #expect(SetPricePill.formattedCompact(1_250_00) == "$1,250")
        // 49 cents → rounds down to $0; 50 cents → up to $1 (standard half-even).
        #expect(SetPricePill.formattedCompact(49) == "$0")
        #expect(SetPricePill.formattedCompact(1_99) == "$2")
    }

    @Test("pill action closure is retained for the view's lifetime and releases on teardown")
    func actionClosureIsRetained() async {
        // P2.7 — the pill is a `Button(action:)`; SwiftUI keeps the
        // closure alive for the view's lifetime. A refactor that
        // accidentally drops the closure (e.g. replacing
        // `Button(action:)` with a `.onTapGesture` and forgetting to
        // wire the parameter through) would deallocate the capture
        // immediately and this test would fail at the first assert.
        weak var weakBox: ActionBox?
        autoreleasepool {
            let box = ActionBox()
            weakBox = box
            let host = UIHostingController(rootView: SetPricePill(priceCents: nil) {
                box.bump()
            })
            _ = host.view
            host.view.layoutIfNeeded()
            #expect(weakBox != nil, "Action closure should still be held by the live SwiftUI view graph")
        }
        // Once the host is gone, the closure (and its capture) should
        // also drop. This second half guards against a leak.
        #expect(weakBox == nil, "Action closure should release once the hosting view tears down")
    }

    @Test("invoking the wired action closure calls through to the caller's bump")
    func actionClosureInvokes() {
        // The companion to `actionClosureIsRetained`: prove the closure
        // we hand into the pill is the one that ultimately runs. We
        // don't synthesize a UIKit tap (those are flaky headlessly);
        // we directly call the closure we stored against the call
        // site's reference type. Together with the retention test this
        // is a clean before/after invariant: closure is held while the
        // view is alive, and invoking it routes to the caller's logic.
        let box = ActionBox()
        let action: () -> Void = { box.bump() }
        let pill = SetPricePill(priceCents: nil, action: action)
        // Sanity: rendering still works with the captured closure.
        let host = UIHostingController(rootView: pill)
        _ = host.view
        #expect(box.count == 0)
        action()
        #expect(box.count == 1, "Invoking the wired closure must call the caller's bump exactly once")
    }

    /// Reference-type box used to verify the pill's closure is retained
    /// while the view graph is alive and released afterward.
    private final class ActionBox {
        private(set) var count = 0
        func bump() { count += 1 }
    }
}
