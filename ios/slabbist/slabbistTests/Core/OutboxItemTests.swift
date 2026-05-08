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

    @Test("UpdateLot payload encodes optional fields as nulls and snake_case keys")
    func updateLotPayloadEncoding() throws {
        let payload = OutboxPayloads.UpdateLot(
            id: "11111111-1111-1111-1111-111111111111",
            name: "Renamed Lot",
            notes: nil,
            status: nil,
            updated_at: "2026-05-07T12:00:00Z"
        )
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"id\":\"11111111-1111-1111-1111-111111111111\""))
        #expect(json.contains("\"name\":\"Renamed Lot\""))
        #expect(json.contains("\"notes\":null"))
        #expect(json.contains("\"updated_at\":\"2026-05-07T12:00:00Z\""))
    }
}
