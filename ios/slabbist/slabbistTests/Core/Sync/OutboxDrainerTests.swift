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

        // Allow the statusSink hop back to MainActor to flush.
        try? await Task.sleep(nanoseconds: 100_000_000)

        let inserted = await h.fakeScans.snapshotInsertedIds()
        let remaining = await h.outboxCount()
        #expect(inserted == [scanId])
        #expect(remaining == 0)
        #expect(h.status.pendingCount == 0)
        #expect(h.status.isDraining == false)
    }
}
