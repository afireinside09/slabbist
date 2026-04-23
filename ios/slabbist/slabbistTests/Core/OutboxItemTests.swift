import Foundation
import Testing
import SwiftData
@testable import slabbist

@Suite("OutboxItem")
struct OutboxItemTests {
    @Test("round-trips kind, payload, and status through SwiftData")
    func roundTrip() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let payload = try JSONEncoder().encode(["scanId": "abc"])
        let item = OutboxItem(
            id: UUID(),
            kind: .insertScan,
            payload: payload,
            status: .pending,
            attempts: 0,
            createdAt: Date(),
            nextAttemptAt: Date()
        )

        context.insert(item)
        try context.save()

        let fetch = FetchDescriptor<OutboxItem>()
        let loaded = try context.fetch(fetch)

        #expect(loaded.count == 1)
        #expect(loaded[0].kind == .insertScan)
        #expect(loaded[0].status == .pending)
        #expect(loaded[0].payload == payload)
    }

    @Test("priority ordering favors validation jobs")
    func priorityOrdering() {
        #expect(OutboxKind.certLookupJob.priority > OutboxKind.priceCompJob.priority)
        #expect(OutboxKind.priceCompJob.priority > OutboxKind.insertScan.priority)
        #expect(OutboxKind.insertScan.priority > OutboxKind.updateScan.priority)
    }
}
