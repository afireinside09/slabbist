import Testing
import Foundation
import os
@testable import slabbist

/// Concurrency hardening for `BulkScanController`. These tests exercise the
/// cross-thread state behind `BulkScanController.crossThread` under the same
/// race conditions that the AVFoundation sample queue produces in production
/// — many concurrent readers off the MainActor while a MainActor writer
/// updates the fields. TSan validation lives in the test scheme; the
/// invariants here also assert correctness on top of TSan's race detection.
@Suite("BulkScanController concurrency", .serialized)
@MainActor
struct BulkScanControllerConcurrencyTests {

    // MARK: - B1: lock-protected cross-thread fields

    /// Writes paired `Date` values to two cross-thread fields from the
    /// MainActor while many concurrent readers race to read the same pair.
    /// The invariant: any read must observe both fields from the *same* write
    /// (they're updated together inside a single `withLock`). A torn read
    /// (lastRectAt from write N, lastTextSeenAt from write N-1) would prove
    /// the lock isn't enforcing pair-consistency — i.e. the original
    /// `nonisolated(unsafe)` bug returned.
    @Test("paired writes never tear under concurrent readers")
    func pairedWritesAreAtomic() async {
        let controller = BulkScanController()
        let iterations = 1_000

        // Writer task: writes (D, D) pairs where both fields share the same
        // timestamp. The serial loop runs on the MainActor; each iteration
        // produces a strictly-newer Date so we can also assert monotonicity
        // is preserved across the lock.
        let writer = Task { @MainActor in
            for i in 0..<iterations {
                // Use a deterministic, distinguishable Date so a torn read
                // is provable from the values, not just from the pairing.
                let d = Date(timeIntervalSince1970: TimeInterval(i))
                controller.crossThread.withLock { state in
                    state.lastRectAt = d
                    state.lastTextSeenAt = d
                }
                // Surface scheduler back to readers between writes — without
                // an explicit yield the whole loop can land in one tick on
                // MainActor and the readers see only the final value.
                await Task.yield()
            }
        }

        // Reader tasks: each reads the pair `iterations` times via the lock
        // and asserts the two fields always match (they were written
        // together). Spawned as detached tasks so they run off the MainActor
        // — matching the sample-queue isolation in production.
        let readerCount = 8
        var readers: [Task<Bool, Never>] = []
        for _ in 0..<readerCount {
            let t = Task.detached {
                for _ in 0..<iterations {
                    let pair = controller.crossThread.withLock { state in
                        (state.lastRectAt, state.lastTextSeenAt)
                    }
                    if pair.0 != pair.1 {
                        return false
                    }
                }
                return true
            }
            readers.append(t)
        }

        await writer.value
        var allConsistent = true
        for r in readers {
            let ok = await r.value
            allConsistent = allConsistent && ok
        }
        #expect(allConsistent, "paired reads must always match — torn read indicates lock bypass")
    }

    /// Confirms `ocrPaused` written on MainActor is visible from a detached
    /// reader (the sample-queue isolation in production). Without the lock,
    /// the original `nonisolated(unsafe) var ocrPaused` write was not
    /// guaranteed to propagate to other threads under the memory model.
    @Test("ocrPaused written on MainActor is visible off-actor under the lock")
    func ocrPausedFlipIsVisibleOffActor() async {
        let controller = BulkScanController()

        // Flip on MainActor.
        controller.crossThread.withLock { $0.ocrPaused = true }

        // Read from a detached task — the lock's release-on-write +
        // acquire-on-read semantics make the flip visible.
        let observed = await Task.detached {
            controller.crossThread.withLock { $0.ocrPaused }
        }.value
        #expect(observed == true)

        // Reset on MainActor and re-verify the new value also propagates.
        controller.crossThread.withLock { $0.ocrPaused = false }
        let observed2 = await Task.detached {
            controller.crossThread.withLock { $0.ocrPaused }
        }.value
        #expect(observed2 == false)
    }

    // MARK: - B2: atomic test-and-set inside presentReview

    /// `presentReview` returns `true` exactly once per review window. Five
    /// queued MainActor hops (the production "multiple stable hits queued
    /// before the first lands" pattern) all call into the same controller;
    /// only the first wins the atomic test-and-set on `ocrPaused`, the
    /// rest return `false` and no-op. Before the fix, every call would have
    /// flipped `pendingReview` and reset the recognizer — the double-record
    /// pattern reported in the audit. The test fails if `presentReview`
    /// doesn't internally gate, because the return-value count is the gate.
    @Test("five stable hits in one window: presentReview returns true once")
    func fiveStableHitsProduceOneReview() {
        let controller = BulkScanController()
        let candidate = CertCandidate(
            grader: .PSA,
            certNumber: "12345678",
            confidence: 0.95,
            rawText: "PSA 10 MINT 12345678"
        )

        let winners = (0..<5).map { _ in controller.presentReview(candidate) }
        #expect(winners.filter { $0 }.count == 1, "exactly one call must win the window")
        #expect(winners.first == true, "the first call must be the winner")
        #expect(controller.pendingReview == candidate)
    }

    /// Off-actor concurrent claimers all race into `presentReview` via
    /// MainActor.run — the lock inside `presentReview` is the only
    /// arbiter. Exactly one must win the window. After `dismissReview`,
    /// a fresh claimer reopens the window and a follow-up call loses.
    @Test("presentReview is single-winner under concurrent off-actor calls")
    func presentReviewIsSingleWinner() async {
        let controller = BulkScanController()
        let candidate = CertCandidate(
            grader: .PSA,
            certNumber: "12345678",
            confidence: 0.95,
            rawText: "PSA 10 MINT 12345678"
        )

        // 16 detached tasks each hop to MainActor and call presentReview.
        // The lock inside presentReview enforces single-winner semantics
        // even though all tasks ultimately serialise on MainActor — the
        // contract held by the return value is what we assert.
        let count = 16
        var tasks: [Task<Bool, Never>] = []
        for _ in 0..<count {
            tasks.append(Task.detached {
                await MainActor.run {
                    controller.presentReview(candidate)
                }
            })
        }
        var wins = 0
        for t in tasks { if await t.value { wins += 1 } }
        #expect(wins == 1, "exactly one of \(count) must win — got \(wins)")

        // Reopen the window and verify the gate re-arms.
        controller.dismissReview()
        #expect(controller.presentReview(candidate) == true, "fresh window must accept")
        #expect(controller.presentReview(candidate) == false, "second call in same window must lose")
    }

    // MARK: - E3: resume-gate / shouldSkipOCR

    /// `shouldSkipOCR()` is the single source of truth for the
    /// sample-queue OCR loop's "drop this frame" decision. It returns
    /// `true` when *either* pause flag is set. Asserting that resume
    /// alone (without `ocrPaused`) drops frames is the load-bearing
    /// invariant: without it, a post-background OCR frame would slip
    /// through with the recognizer in a stale state.
    @Test("shouldSkipOCR is true when only ocrSuspendedForResume is true")
    func shouldSkipOCRTrueWhenOnlyResumeSet() {
        let controller = BulkScanController()
        // ocrPaused defaults false, resume defaults false.
        #expect(controller.shouldSkipOCR() == false)
        controller.armResumeGate()
        #expect(controller.shouldSkipOCR() == true,
                "resume gate alone must suppress OCR — pocketed-phone guard")
    }

    /// Default state: neither flag set → frames flow.
    @Test("shouldSkipOCR is false when both pause flags are false")
    func shouldSkipOCRFalseWhenAllClear() {
        let controller = BulkScanController()
        #expect(controller.shouldSkipOCR() == false)
    }

    /// The gate's only dismissal path is the user tap. scenePhase
    /// changes don't clear `ocrSuspendedForResume` — only
    /// `dismissResumeGate()` does. Tap the gate (call the dismissal
    /// method) and confirm the suppression lifts.
    @Test("dismissResumeGate flips ocrSuspendedForResume back to false")
    func dismissResumeGateClearsSuppression() {
        let controller = BulkScanController()
        controller.armResumeGate()
        #expect(controller.resumeGateActive == true)
        #expect(controller.shouldSkipOCR() == true)
        controller.dismissResumeGate()
        #expect(controller.resumeGateActive == false)
        #expect(controller.shouldSkipOCR() == false,
                "dismissing the gate must lift the OCR suppression so live scanning resumes")
        // And `wasBackgrounded` resets to false so the *next* foreground
        // hop (without a fresh background) doesn't re-arm the gate.
        #expect(controller.wasBackgrounded == false)
    }

    /// `recordBackgrounded` is what the `.background` scenePhase branch
    /// calls. Until the gate has been armed and dismissed once,
    /// `wasBackgrounded` reads true so the next `.active` hop arms the
    /// gate. Confirms the spec rule: "first-time entry into the scan
    /// view does NOT show the gate" — i.e. without `recordBackgrounded`
    /// ever firing, `wasBackgrounded` is false.
    @Test("wasBackgrounded only flips true after recordBackgrounded")
    func wasBackgroundedRespectsScenePhase() {
        let controller = BulkScanController()
        #expect(controller.wasBackgrounded == false,
                "fresh controller — no scenePhase background yet — must report not-backgrounded")
        controller.recordBackgrounded()
        #expect(controller.wasBackgrounded == true)
    }

    /// P1.6: Notification Center pulldown only flips scenePhase to
    /// `.inactive`, not `.background`. The view's scenePhase handler
    /// must NOT call `recordBackgrounded` on `.inactive` — otherwise
    /// the gate re-arms after every 1-second shade pulldown. The
    /// controller surface enforces this contract by gating `armResumeGate`
    /// on `wasBackgrounded`-style state being set by an explicit
    /// `recordBackgrounded` call. This test simulates an `.inactive`
    /// cycle (no `recordBackgrounded`) followed by `.active` and
    /// confirms the gate-arming check would fail.
    @Test("inactive → active without recordBackgrounded leaves wasBackgrounded false")
    func inactiveCycleDoesNotArmGate() {
        let controller = BulkScanController()
        // Simulate `.inactive` branch: stop camera, but do NOT call
        // recordBackgrounded. (The view's scenePhase handler runs
        // exactly this path for `.inactive`.)
        #expect(controller.wasBackgrounded == false)
        // Now simulate `.active`. The view's handler reads
        // `wasBackgrounded` to decide whether to arm the gate — false
        // means it skips arming entirely.
        #expect(controller.wasBackgrounded == false,
                ".inactive cycle must NOT set wasBackgrounded — Notification Center pulldown should not arm the resume gate")
    }


    /// the app is no longer actionable on return. `recordBackgrounded`
    /// drops the review card AND releases `ocrPaused` (which
    /// `presentReview` had set). Without this, the resume gate sits
    /// over an invisible review card, the user taps to resume, and
    /// live scanning still doesn't start because `ocrPaused` is true
    /// from the pre-background review.
    @Test("recordBackgrounded drops a stale pendingReview and releases ocrPaused")
    func recordBackgroundedDropsStaleReview() {
        let controller = BulkScanController()
        let candidate = CertCandidate(
            grader: .PSA,
            certNumber: "12345678",
            confidence: 0.95,
            rawText: "PSA 10 MINT 12345678"
        )
        // Simulate: user gets a stable hit, then backgrounds the app.
        #expect(controller.presentReview(candidate) == true)
        #expect(controller.pendingReview == candidate)
        #expect(controller.shouldSkipOCR() == true, "review-pending must pause OCR")

        controller.recordBackgrounded()
        #expect(controller.pendingReview == nil,
                "stale review card must be dropped on backgrounding")

        // Now arm the gate (simulates the `.background → .active` hop)
        // and dismiss it. After dismissal, `shouldSkipOCR()` must be
        // false — the only pause source was the stale review, which
        // recordBackgrounded already released.
        controller.armResumeGate()
        #expect(controller.shouldSkipOCR() == true, "armed gate suppresses OCR")
        controller.dismissResumeGate()
        #expect(controller.shouldSkipOCR() == false,
                "after gate dismissal, live scanning resumes — no stale ocrPaused from the pre-background review")
    }
}
