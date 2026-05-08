import Foundation
import Testing
import SwiftData
import Supabase
@testable import slabbist

@Suite("OutboxDrainer")
struct OutboxDrainerTests {
    @Test("happy path: insertScan is dispatched and item deleted")
    @MainActor
    func happyPathInsertScan() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.insertedIds == [scanId])
        let count = await h.outboxCount()
        #expect(count == 0)
        #expect(h.status.pendingCount == 0)
        #expect(h.status.isDraining == false)
    }

    @Test("dispatches insertLot")
    @MainActor
    func dispatchesInsertLot() async throws {
        let h = Harness()
        let lotId = UUID()
        try await h.enqueueInsertLot(id: lotId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeLots.insertedIds == [lotId])
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("dispatches deleteScan")
    @MainActor
    func dispatchesDeleteScan() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueDeleteScan(id: scanId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeScans.deletedIds == [scanId])
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("dispatches deleteLot")
    @MainActor
    func dispatchesDeleteLot() async throws {
        let h = Harness()
        let lotId = UUID()
        try await h.enqueueDeleteLot(id: lotId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeLots.deletedIds == [lotId])
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("dispatches updateScan with patch fields")
    @MainActor
    func dispatchesUpdateScan() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueUpdateScan(id: scanId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeScans.patchCalls.count == 1)
        #expect(h.fakeScans.patchCalls[0].id == scanId)
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("updateScanOffer with cents: writes .integer(value)")
    @MainActor
    func dispatchesUpdateScanOfferWithCents() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueUpdateScanOffer(id: scanId, cents: 12500)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.patchCalls.count == 1)
        #expect(h.fakeScans.patchCalls[0].id == scanId)
        #expect(h.fakeScans.patchCalls[0].fields["offer_cents"] == .integer(12500))
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("updateScanOffer with cents nil: writes .null (clear semantic)")
    @MainActor
    func dispatchesUpdateScanOfferClearing() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueUpdateScanOffer(id: scanId, cents: nil)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.patchCalls.count == 1)
        #expect(h.fakeScans.patchCalls[0].id == scanId)
        #expect(h.fakeScans.patchCalls[0].fields["offer_cents"] == .null)
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("dispatches updateLot with patch fields")
    @MainActor
    func dispatchesUpdateLot() async throws {
        let h = Harness()
        let lotId = UUID()
        try await h.enqueueUpdateLot(id: lotId, name: "Renamed")
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeLots.patchCalls.count == 1)
        #expect(h.fakeLots.patchCalls[0].id == lotId)
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    // MARK: - 7.3 error-classifier tests

    @Test("409 (uniqueViolation) on insertScan deletes the item — idempotent success")
    @MainActor
    func conflictOnInsertIsSuccess() async throws {
        let h = Harness()
        let scanId = UUID()
        h.fakeScans.nextError = SupabaseError.uniqueViolation(
            message: "dup",
            underlying: NSError(domain: "x", code: 0)
        )
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let count = await h.outboxCount()
        #expect(count == 0)
        #expect(h.fakeScans.insertedIds.isEmpty)
    }

    @Test("transient error then success: backoff schedules retry, second kick after clock advance lands")
    @MainActor
    func transientThenSuccess() async throws {
        let h = Harness()
        let scanId = UUID()
        h.fakeScans.nextError = SupabaseError.transport(underlying: URLError(.timedOut))
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.insertedIds.isEmpty)
        let count1 = await h.outboxCount()
        #expect(count1 == 1)

        let item1 = try await h.firstOutboxItem()
        #expect(item1.attempts == 1)
        #expect(item1.status == .pending)
        #expect(item1.nextAttemptAt > h.clock.current())

        h.clock.advance(10) // jump past the backoff window
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.insertedIds == [scanId])
        let count2 = await h.outboxCount()
        #expect(count2 == 0)
    }

    @Test("401 pauses the queue; subsequent kicks no-op until unpause()")
    @MainActor
    func authErrorPausesQueue() async throws {
        let h = Harness()
        let scanId = UUID()
        h.fakeScans.nextError = SupabaseError.unauthorized
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.status.isPaused == true)
        #expect(h.fakeScans.insertedIds.isEmpty)
        let count = await h.outboxCount()
        #expect(count == 1)

        // Subsequent kick while paused: no repo call (the nextError was
        // consumed on the first attempt, so a second drain-pass would
        // succeed if it ran — proving it didn't).
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeScans.insertedIds.isEmpty)

        // Unpause and kick again — should drain.
        await h.drainer.unpause()
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeScans.insertedIds == [scanId])
    }

    @Test("permanent (forbidden / RLS) marks item .failed and stops retrying")
    @MainActor
    func permanentMarksFailed() async throws {
        let h = Harness()
        let scanId = UUID()
        h.fakeScans.nextError = SupabaseError.forbidden(underlying: NSError(domain: "x", code: 0))
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let item = try await h.firstOutboxItem()
        #expect(item.status == .failed)
        #expect(item.lastError != nil)

        // Re-kick: failed items are not re-fetched.
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeScans.insertedIds.isEmpty)
    }
}
