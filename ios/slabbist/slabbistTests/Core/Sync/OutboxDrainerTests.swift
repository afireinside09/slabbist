import Foundation
import Testing
import SwiftData
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
}
