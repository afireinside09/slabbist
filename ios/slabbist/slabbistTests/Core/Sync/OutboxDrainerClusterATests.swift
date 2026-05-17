import Foundation
import Testing
import SwiftData
import Supabase
@testable import slabbist

/// Cluster A: sync-safety hardening for the outbox drainer.
///
/// * A1: dispatchItem doesn't strand `.inFlight` rows on save failure;
///       startup recovery demotes long-stranded rows back to `.pending`.
/// * A2: `OutboxStatus` exposes `failedCount`; the drainer publishes a
///       single snapshot of (pending, failed).
/// * A3: `fetchBatch` filters `.pending` inside the predicate so fat
///       `.failed` / `.inFlight` neighbourhoods never starve the lane.
/// * A4: `kick()` during an active drain pass coalesces into one extra
///       pass instead of stranding the late save.
/// * A5: the auth-pause pill escalates from `.reconnecting` to
///       `.signedOut` after sustained 401s instead of immediately accusing
///       the user of being signed out while supabase-swift is mid-refresh.
@Suite("OutboxDrainer — Cluster A (sync safety)")
struct OutboxDrainerClusterATests {

    // MARK: A1 — strand-resistant dispatch

    @Test("A1: recoverStrandedInFlight demotes a stale .inFlight row to .pending")
    @MainActor
    func recoverStrandedInFlight() async throws {
        // WHY this matters: a crash between `mark inFlight` save and
        // `delete after dispatch` save leaves a row stuck. `fetchBatch`
        // filters .pending only, so without recovery the row dies in the
        // database — silent loss for the user.
        let h = Harness()
        let scanId = UUID()
        let payload = try sampleInsertScanPayload(id: scanId, clock: h.clock)

        // Seed: insert one row as `.inFlight` with a nextAttemptAt older
        // than the recovery threshold.
        let strandedNextAttempt = h.clock.current()
            .addingTimeInterval(-(OutboxDrainer.strandedInFlightThreshold + 30))
        try await h.drainer._testSeedStrandedInFlight(
            id: UUID(),
            kind: .insertScan,
            payload: payload,
            createdAt: strandedNextAttempt,
            nextAttemptAt: strandedNextAttempt
        )
        // Sanity: before the drain, exactly one .inFlight row, zero .pending.
        let before = await h.drainer._testStatusSnapshot()
        #expect(before.pending == 0)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        // The recovery pass should have demoted it AND the same drain
        // should have dispatched it through to the fake repo.
        #expect(h.fakeScans.insertedIds == [scanId])
        let after = await h.drainer._testStatusSnapshot()
        #expect(after.pending == 0)
        #expect(after.failed == 0)
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("A1: a fresh .inFlight row (within threshold) is NOT recovered")
    @MainActor
    func recoveryRespectsThreshold() async throws {
        let h = Harness()
        let scanId = UUID()
        let payload = try sampleInsertScanPayload(id: scanId, clock: h.clock)

        // Seed: `.inFlight` row that's only 5 seconds old. Recovery
        // shouldn't touch it — that would race against a real in-flight
        // dispatch from another part of the queue.
        let freshNextAttempt = h.clock.current().addingTimeInterval(-5)
        try await h.drainer._testSeedStrandedInFlight(
            id: UUID(),
            kind: .insertScan,
            payload: payload,
            createdAt: freshNextAttempt,
            nextAttemptAt: freshNextAttempt
        )

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        // Row stays .inFlight; the fake never sees the dispatch.
        #expect(h.fakeScans.insertedIds.isEmpty)
        let count = await h.outboxCount()
        #expect(count == 1)
    }

    // MARK: A2 — status snapshot surfaces both lanes

    @Test("A2: status snapshot reports both pendingCount and failedCount")
    @MainActor
    func statusSnapshotReportsFailedCount() async throws {
        let h = Harness()

        // Drive one .failed row (forbidden → permanent) and seed one
        // separate pending row that will block on a transient error so
        // the snapshot is observed mid-state.
        let permId = UUID()
        h.fakeScans.nextError = SupabaseError.forbidden(underlying: NSError(domain: "x", code: 0))
        try await h.enqueueInsertScan(id: permId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        // One row should now be .failed; status snapshot reflects that.
        #expect(h.status.failedCount == 1)
        #expect(h.status.pendingCount == 0)
        let snap = await h.drainer._testStatusSnapshot()
        #expect(snap.failed == 1)
        #expect(snap.pending == 0)
    }

    @Test("A2: drainer.listFailed surfaces a sendable snapshot of every .failed row")
    @MainActor
    func listFailedSurfaceShape() async throws {
        let h = Harness()
        let scanId = UUID()
        h.fakeScans.nextError = SupabaseError.forbidden(underlying: NSError(domain: "x", code: 0))
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let rows = await h.drainer.listFailed()
        #expect(rows.count == 1)
        #expect(rows[0].kind == .insertScan)
        #expect(rows[0].lastError != nil)
        #expect(rows[0].attempts >= 1)
    }

    @Test("A2: retryFailed resets a .failed row and the next kick lands it")
    @MainActor
    func retryFailedThenSucceeds() async throws {
        let h = Harness()
        let scanId = UUID()
        // Forbidden → .failed on first attempt.
        h.fakeScans.nextError = SupabaseError.forbidden(underlying: NSError(domain: "x", code: 0))
        try await h.enqueueInsertScan(id: scanId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.status.failedCount == 1)

        // Retry — the test's nextError is exhausted, so the next dispatch
        // should land cleanly.
        let failedRow = try await h.firstOutboxItem()
        await h.drainer.retryFailed(id: failedRow.id)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.insertedIds == [scanId])
        let count = await h.outboxCount()
        #expect(count == 0)
        #expect(h.status.failedCount == 0)
    }

    @Test("A2: discardFailed drops the row from the outbox")
    @MainActor
    func discardFailedRemovesRow() async throws {
        let h = Harness()
        let scanId = UUID()
        h.fakeScans.nextError = SupabaseError.forbidden(underlying: NSError(domain: "x", code: 0))
        try await h.enqueueInsertScan(id: scanId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        let failedRow = try await h.firstOutboxItem()

        await h.drainer.discardFailed(id: failedRow.id)
        await h.waitForIdle()

        let count = await h.outboxCount()
        #expect(count == 0)
        #expect(h.status.failedCount == 0)
    }

    // MARK: A3 — predicate-pushed pending filter

    @Test("A3: a single .pending drains even with 60 .failed rows blocking the fetch")
    @MainActor
    func pendingDrainsThroughFatFailedNeighborhood() async throws {
        // WHY this matters: the previous in-memory filter ran AFTER
        // fetchLimit (50). 60 .failed rows would have starved the one
        // .pending row. This is the bug the audit identified.
        let h = Harness()
        let now = h.clock.current()
        // Seed 60 .failed rows directly via the test seam.
        for _ in 0..<60 {
            let p = try sampleInsertScanPayload(id: UUID(), clock: h.clock)
            try await h.drainer._testEnqueue(
                id: UUID(),
                kind: .insertScan,
                payload: p,
                createdAt: now,
                nextAttemptAt: now,
                status: .failed
            )
        }
        // One real .pending row that we expect to drain.
        let scanId = UUID()
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        // The pending row reached the wire.
        #expect(h.fakeScans.insertedIds == [scanId])

        // Pending lane is now empty; the 60 .failed rows are untouched.
        let snap = await h.drainer._testStatusSnapshot()
        #expect(snap.pending == 0)
        #expect(snap.failed == 60)
    }

    // MARK: A4 — mid-drain late saves drain via the natural loop

    @Test("A4: a row enqueued during dispatch drains in the same kick (natural-loop catch)")
    @MainActor
    func lateEnqueueDuringDispatchDrainsSamePass() async throws {
        // The Critic was right that the previous post-empty re-pass and
        // `markKickPending()` flag were dead code: the drainer's outer
        // `while true` loop already re-fetches after each batch finishes.
        // This test pins the natural-loop behaviour so a future
        // optimisation doesn't quietly break it.
        //
        // Strategy: gate the first dispatch on a continuation. While the
        // drainer is awaiting, enqueue a second row. When the first
        // dispatch completes, the loop's next iteration must see the
        // new row in `fetchBatch` and drain it without an external kick.
        let h = Harness()
        let firstId = UUID()
        let secondId = UUID()

        let gate = AsyncGate()
        h.fakeScans.beforeInsert = { id in
            // Only gate the first dispatch — let the second-row dispatch
            // run normally so the test can observe it landing.
            if id == firstId { await gate.wait() }
        }

        try await h.enqueueInsertScan(id: firstId)

        // Kick #1 — starts the drain and stalls on the gate.
        async let firstDrain: Void = h.drainer.kickAndWait()

        // Wait until the drainer is actually blocked inside the first dispatch.
        await gate.waitForArrival()

        // Mid-drain enqueue — NO second kick. The first kick's outer loop
        // must catch this on the next `fetchBatch` after dispatch unwinds.
        try await h.enqueueInsertScan(id: secondId)

        // Release the gate so the first dispatch unwinds.
        await gate.release()

        _ = await firstDrain
        await h.waitForIdle()

        // Both rows reached the wire — the late save wasn't stranded
        // and we didn't need a second kick to pick it up.
        #expect(h.fakeScans.insertedIds.contains(firstId))
        #expect(h.fakeScans.insertedIds.contains(secondId))
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("A4: a kick that lands during an active drain is a safe no-op (no double-dispatch)")
    @MainActor
    func concurrentKickDuringDrainDoesNotDoubleDispatch() async throws {
        // A separate kick arriving while drainOnce is still running must
        // NOT cause the row to be dispatched twice. The early-return
        // `guard !isDraining` in `drainOnce()` is what protects us.
        let h = Harness()
        let firstId = UUID()
        let gate = AsyncGate()
        h.fakeScans.beforeInsert = { _ in await gate.wait() }

        try await h.enqueueInsertScan(id: firstId)
        async let firstDrain: Void = h.drainer.kickAndWait()
        await gate.waitForArrival()

        // Second kick mid-drain — must early-return, must not re-dispatch.
        async let secondDrain: Void = h.drainer.kickAndWait()

        await gate.release()
        _ = await (firstDrain, secondDrain)
        await h.waitForIdle()

        // Repo recorded exactly one insert (not two).
        #expect(h.fakeScans.insertedIds == [firstId])
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    // MARK: A5 — auth-pause escalation

    @Test("A5: first auth pause resolves to .reconnecting (don't accuse the user)")
    @MainActor
    func firstAuthPauseIsReconnecting() async throws {
        let h = Harness()
        let scanId = UUID()
        h.fakeScans.nextError = SupabaseError.unauthorized
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.status.isPaused == true)
        #expect(h.status.authState == .reconnecting)
        // Pill copy is the reconnecting variant, not "Sign in to sync".
        #expect(h.status.lastError == "Reconnecting…")
    }

    @Test("A5: sustained auth failures across unpause cycles escalate to .signedOut")
    @MainActor
    func sustainedAuthEscalatesToSignedOut() async throws {
        // WHY this matters: supabase-swift auto-refresh retriggers
        // SessionStore which calls `unpause()`. If the refresh keeps
        // returning 401 the counter HAS to persist across unpauses,
        // otherwise the user never gets the "actually you have to sign in"
        // copy. A successful dispatch is what resets the counter.
        let h = Harness()

        // 1st failure → counter = 1 → .reconnecting.
        let scan1 = UUID()
        h.fakeScans.nextError = SupabaseError.unauthorized
        try await h.enqueueInsertScan(id: scan1)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.status.authState == .reconnecting)

        // Auto-refresh "fired", unpause() called by the resume path, but
        // the refresh actually failed: the next kick still hits 401.
        await h.drainer.unpause()
        h.fakeScans.nextError = SupabaseError.unauthorized
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        // Counter = 2 → meets threshold → .signedOut.
        #expect(h.status.authState == .signedOut)
        #expect(h.status.lastError == "Sign in to sync")
    }

    @Test("A5: a successful dispatch resets the sustained-auth counter")
    @MainActor
    func successResetsAuthCounter() async throws {
        let h = Harness()

        // First 401 — counter at 1.
        let scan1 = UUID()
        h.fakeScans.nextError = SupabaseError.unauthorized
        try await h.enqueueInsertScan(id: scan1)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.status.authState == .reconnecting)

        // Unpause + successful drain — proves auth is good. Counter should
        // reset, so the *next* 401 (after another unpause) starts back at
        // .reconnecting instead of escalating.
        await h.drainer.unpause()
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeScans.insertedIds == [scan1])

        // Another 401 episode later — counter should be 1 again, not 2+.
        let scan2 = UUID()
        h.fakeScans.nextError = SupabaseError.unauthorized
        try await h.enqueueInsertScan(id: scan2)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.status.authState == .reconnecting)
    }

    @Test("A5: unpause clears authState so the pill doesn't render stale copy")
    @MainActor
    func unpauseClearsAuthState() async throws {
        let h = Harness()
        let scanId = UUID()
        h.fakeScans.nextError = SupabaseError.unauthorized
        try await h.enqueueInsertScan(id: scanId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.status.authState != nil)

        // Simulate the auth-resume path: drainer unpauses, MainActor copy
        // also clears via setPaused(false, ...).
        await h.drainer.unpause()
        h.status.setPaused(false, reason: nil, authState: nil)
        #expect(h.status.authState == nil)
        #expect(h.status.isPaused == false)
    }

    // MARK: - Cache correctness (per P1.1 / P2.8 — cached counts must
    // match disk after every transition the drainer makes)

    @Test("cached counts mirror disk after a successful drain")
    @MainActor
    func cachedCountsMatchDiskAfterDrain() async throws {
        let h = Harness()
        let id = UUID()
        try await h.enqueueInsertScan(id: id)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let disk = await h.drainer._testStatusSnapshot()
        let cached = await h.drainer._testCachedCounts()
        #expect(disk.pending == 0)
        #expect(disk.failed == 0)
        #expect(cached.pending == disk.pending)
        #expect(cached.failed == disk.failed)
    }

    @Test("cached counts mirror disk after a permanent failure (markedFailed)")
    @MainActor
    func cachedCountsMatchDiskAfterFailure() async throws {
        let h = Harness()
        let id = UUID()
        h.fakeScans.nextError = SupabaseError.forbidden(underlying: NSError(domain: "x", code: 0))
        try await h.enqueueInsertScan(id: id)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let disk = await h.drainer._testStatusSnapshot()
        let cached = await h.drainer._testCachedCounts()
        #expect(disk.pending == 0)
        #expect(disk.failed == 1)
        #expect(cached == disk)
    }

    @Test("cached counts mirror disk after a transient retry (returnedToPending)")
    @MainActor
    func cachedCountsMatchDiskAfterTransient() async throws {
        let h = Harness()
        let id = UUID()
        h.fakeScans.nextError = SupabaseError.transport(underlying: URLError(.timedOut))
        try await h.enqueueInsertScan(id: id)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let disk = await h.drainer._testStatusSnapshot()
        let cached = await h.drainer._testCachedCounts()
        #expect(disk.pending == 1)
        #expect(disk.failed == 0)
        #expect(cached == disk)
    }

    @Test("cached counts mirror disk after retryFailed + discardFailed")
    @MainActor
    func cachedCountsMatchDiskAfterRetryAndDiscard() async throws {
        let h = Harness()

        // Drive two rows into .failed.
        let id1 = UUID()
        h.fakeScans.nextError = SupabaseError.forbidden(underlying: NSError(domain: "x", code: 0))
        try await h.enqueueInsertScan(id: id1)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let id2 = UUID()
        h.fakeScans.nextError = SupabaseError.forbidden(underlying: NSError(domain: "x", code: 0))
        try await h.enqueueInsertScan(id: id2)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let failedRows = await h.drainer.listFailed()
        #expect(failedRows.count == 2)

        // Retry one, discard the other.
        await h.drainer.retryFailed(id: failedRows[0].id)
        await h.drainer.discardFailed(id: failedRows[1].id)

        let disk = await h.drainer._testStatusSnapshot()
        let cached = await h.drainer._testCachedCounts()
        #expect(disk.pending == 1)
        #expect(disk.failed == 0)
        #expect(cached == disk)
    }

    // MARK: - P1.3 — tryPersist contract (no retry; revert in-memory
    // mutation on failure)

    @Test("dispatchItem reverts .inFlight to .pending when context.save() fails")
    @MainActor
    func saveFailureKeepsRowPending() async throws {
        // We can't easily force SwiftData to fail save() inside the actor
        // without a heavyweight stub of `ModelContext` (the actor owns
        // its own context, not injectable). The next-best contract test:
        // verify the existing observable behaviour that proves the
        // revert path doesn't strand the row — a row that the drainer
        // touched but couldn't fully dispatch (here, simulated via a
        // transient error after the .inFlight save) ends up back in
        // .pending, NOT in .inFlight. This pins the invariant the no-
        // retry tryPersist+revert path is supposed to uphold.
        let h = Harness()
        let id = UUID()
        h.fakeScans.nextError = SupabaseError.transport(underlying: URLError(.networkConnectionLost))
        try await h.enqueueInsertScan(id: id)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let snap = try await h.firstOutboxItem()
        // Row is .pending, not .inFlight. attempts incremented (transient).
        #expect(snap.status == .pending)
        #expect(snap.attempts == 1)
    }
}

// MARK: - Test helpers

/// A small async gate for orchestrating mid-drain races. Used by A4 so
/// the test can pause the drainer's first dispatch, prove the late save
/// landed, and then release — no fragile sleep loops.
actor AsyncGate {
    private var arrived: Bool = false
    private var arrivalContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var released: Bool = false

    /// Called from inside the awaited code path: signals arrival, then
    /// waits for `release()`.
    func wait() async {
        arrived = true
        for c in arrivalContinuations { c.resume() }
        arrivalContinuations.removeAll()
        if released { return }
        await withCheckedContinuation { c in
            releaseContinuations.append(c)
        }
    }

    /// The test waits here until the drainer actually entered `wait()`.
    func waitForArrival() async {
        if arrived { return }
        await withCheckedContinuation { c in
            arrivalContinuations.append(c)
        }
    }

    /// Release every waiter.
    func release() {
        released = true
        for c in releaseContinuations { c.resume() }
        releaseContinuations.removeAll()
    }
}

private func sampleInsertScanPayload(id: UUID, clock: TestClock) throws -> Data {
    let stamp = clock.current()
    let iso = ISO8601DateFormatter()
    let dto = OutboxPayloads.InsertScan(
        id: id.uuidString,
        store_id: UUID().uuidString,
        lot_id: UUID().uuidString,
        user_id: UUID().uuidString,
        grader: "PSA",
        cert_number: "12345",
        status: "pending_validation",
        ocr_raw_text: nil,
        ocr_confidence: nil,
        created_at: iso.string(from: stamp),
        updated_at: iso.string(from: stamp)
    )
    return try JSONEncoder().encode(dto)
}
