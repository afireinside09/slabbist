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

    @Test("UpsertVendor payload encodes snake_case keys and round-trips created_at")
    func upsertVendorPayloadEncoding() throws {
        let payload = OutboxPayloads.UpsertVendor(
            id: "22222222-2222-2222-2222-222222222222",
            store_id: "33333333-3333-3333-3333-333333333333",
            display_name: "Acme Cards",
            contact_method: "phone",
            contact_value: "555-0100",
            notes: "preferred dealer",
            archived_at: "2026-05-08T12:00:00Z",
            created_at: "2026-05-01T08:00:00Z",
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
        #expect(json.contains("\"created_at\":\"2026-05-01T08:00:00Z\""))
        #expect(json.contains("\"updated_at\":\"2026-05-08T12:00:00Z\""))

        // Round-trip: created_at decodes back as an independent value
        // (distinct from updated_at) so the upsert path can preserve it.
        let decoded = try JSONDecoder().decode(OutboxPayloads.UpsertVendor.self, from: data)
        #expect(decoded.created_at == "2026-05-01T08:00:00Z")
        #expect(decoded.updated_at == "2026-05-08T12:00:00Z")
        #expect(decoded.created_at != decoded.updated_at)
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

    @Test("UpdateLotOffer payload encodes snake_case keys and round-trips margin_pct")
    func updateLotOfferPayloadEncoding() throws {
        let payload = OutboxPayloads.UpdateLotOffer(
            id: "11111111-1111-1111-1111-111111111111",
            vendor_id: "22222222-2222-2222-2222-222222222222",
            vendor_name_snapshot: "Acme Cards",
            margin_pct_snapshot: 0.18,
            lot_offer_state: "offered",
            lot_offer_state_updated_at: "2026-05-08T12:00:00Z",
            updated_at: "2026-05-08T12:00:00Z"
        )
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"id\":\"11111111-1111-1111-1111-111111111111\""))
        #expect(json.contains("\"vendor_id\":\"22222222-2222-2222-2222-222222222222\""))
        #expect(json.contains("\"vendor_name_snapshot\":\"Acme Cards\""))
        #expect(json.contains("\"margin_pct_snapshot\":0.18"))
        #expect(json.contains("\"lot_offer_state\":\"offered\""))
        #expect(json.contains("\"lot_offer_state_updated_at\":\"2026-05-08T12:00:00Z\""))
        #expect(json.contains("\"updated_at\":\"2026-05-08T12:00:00Z\""))

        let decoded = try JSONDecoder().decode(OutboxPayloads.UpdateLotOffer.self, from: data)
        #expect(decoded.vendor_id == "22222222-2222-2222-2222-222222222222")
        #expect(decoded.margin_pct_snapshot == 0.18)
        #expect(decoded.lot_offer_state == "offered")
    }

    @Test("RecomputeLotOffer payload carries lot_id only")
    func recomputeLotOfferPayloadEncoding() throws {
        let payload = OutboxPayloads.RecomputeLotOffer(
            lot_id: "55555555-5555-5555-5555-555555555555"
        )
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"lot_id\":\"55555555-5555-5555-5555-555555555555\""))
        let decoded = try JSONDecoder().decode(OutboxPayloads.RecomputeLotOffer.self, from: data)
        #expect(decoded.lot_id == "55555555-5555-5555-5555-555555555555")
    }

    @Test("CommitTransaction payload encodes snake_case keys")
    func commitTransactionPayloadEncoding() throws {
        let p = OutboxPayloads.CommitTransaction(
            lot_id: "11111111-1111-1111-1111-111111111111",
            payment_method: "cash",
            payment_reference: "check #123",
            vendor_id: "22222222-2222-2222-2222-222222222222",
            vendor_name_override: nil
        )
        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"lot_id\":\"11111111-1111-1111-1111-111111111111\""))
        #expect(json.contains("\"payment_method\":\"cash\""))
        #expect(json.contains("\"payment_reference\":\"check #123\""))
        #expect(json.contains("\"vendor_id\":\"22222222-2222-2222-2222-222222222222\""))
    }

    @Test("VoidTransaction payload encodes id and reason")
    func voidTransactionPayloadEncoding() throws {
        let p = OutboxPayloads.VoidTransaction(
            transaction_id: "33333333-3333-3333-3333-333333333333",
            reason: "vendor returned"
        )
        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"transaction_id\":\"33333333-3333-3333-3333-333333333333\""))
        #expect(json.contains("\"reason\":\"vendor returned\""))
    }

    @Test("UpdateScanBuyPrice payload encodes cents, overridden flag, and updated_at")
    func updateScanBuyPricePayloadEncoding() throws {
        let payload = OutboxPayloads.UpdateScanBuyPrice(
            id: "66666666-6666-6666-6666-666666666666",
            buy_price_cents: 7500,
            buy_price_overridden: true,
            updated_at: "2026-05-08T12:00:00Z"
        )
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"id\":\"66666666-6666-6666-6666-666666666666\""))
        #expect(json.contains("\"buy_price_cents\":7500"))
        #expect(json.contains("\"buy_price_overridden\":true"))
        #expect(json.contains("\"updated_at\":\"2026-05-08T12:00:00Z\""))

        // Clearing: cents nil — JSONEncoder omits nil optionals from the wire
        // shape; the drainer dispatch path is what writes `.null` into the
        // server patch (covered by OutboxDrainerTests.dispatchesUpdateScanBuyPriceClearing).
        let clearPayload = OutboxPayloads.UpdateScanBuyPrice(
            id: "66666666-6666-6666-6666-666666666666",
            buy_price_cents: nil,
            buy_price_overridden: false,
            updated_at: "2026-05-08T12:00:00Z"
        )
        let clearData = try JSONEncoder().encode(clearPayload)
        let clearJson = String(data: clearData, encoding: .utf8) ?? ""
        #expect(!clearJson.contains("buy_price_cents"))
        #expect(clearJson.contains("\"buy_price_overridden\":false"))

        // Round-trip the cleared payload to confirm `nil` survives decode.
        let decoded = try JSONDecoder().decode(OutboxPayloads.UpdateScanBuyPrice.self, from: clearData)
        #expect(decoded.buy_price_cents == nil)
        #expect(decoded.buy_price_overridden == false)
    }
}
