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
}
