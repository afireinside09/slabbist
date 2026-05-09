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

    @Test("vendor kinds exist with expected priorities")
    func vendorKindsExistWithExpectedPriorities() {
        #expect(OutboxKind.upsertVendor.priority < OutboxKind.insertScan.priority)
        #expect(OutboxKind.archiveVendor.priority == OutboxKind.upsertVendor.priority)
        #expect(OutboxKind.upsertVendor.priority > OutboxKind.updateLot.priority)
    }

    @Test("UpsertVendor payload encodes snake_case keys")
    func upsertVendorPayloadEncoding() throws {
        let payload = OutboxPayloads.UpsertVendor(
            id: "22222222-2222-2222-2222-222222222222",
            store_id: "33333333-3333-3333-3333-333333333333",
            display_name: "Acme Cards",
            contact_method: "phone",
            contact_value: "555-0100",
            notes: "preferred dealer",
            archived_at: "2026-05-08T12:00:00Z",
            updated_at: "2026-05-08T12:00:00Z"
        )
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"id\":\"22222222-2222-2222-2222-222222222222\""))
        #expect(json.contains("\"store_id\":\"33333333-3333-3333-3333-333333333333\""))
        #expect(json.contains("\"display_name\":\"Acme Cards\""))
        #expect(json.contains("\"contact_method\":\"phone\""))
        #expect(json.contains("\"contact_value\":\"555-0100\""))
        #expect(json.contains("\"notes\":\"preferred dealer\""))
        #expect(json.contains("\"archived_at\":\"2026-05-08T12:00:00Z\""))
        #expect(json.contains("\"updated_at\":\"2026-05-08T12:00:00Z\""))
    }

    @Test("ArchiveVendor payload encodes id and archived_at")
    func archiveVendorPayloadEncoding() throws {
        let payload = OutboxPayloads.ArchiveVendor(
            id: "44444444-4444-4444-4444-444444444444",
            archived_at: "2026-05-08T12:00:00Z"
        )
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"id\":\"44444444-4444-4444-4444-444444444444\""))
        #expect(json.contains("\"archived_at\":\"2026-05-08T12:00:00Z\""))
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
