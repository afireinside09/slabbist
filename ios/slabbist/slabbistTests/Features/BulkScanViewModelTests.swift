import Foundation
import Testing
import SwiftData
@testable import slabbist

@Suite("BulkScanViewModel")
@MainActor
struct BulkScanViewModelTests {
    @Test("recordCapture inserts Scan + outbox item in the correct lot")
    func recordsCapture() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let lot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId,
                      name: "Test", createdAt: Date(), updatedAt: Date())
        context.insert(lot)
        try context.save()

        let vm = BulkScanViewModel(context: context, kicker: OutboxKicker { }, lot: lot, currentUserId: userId)
        let candidate = CertCandidate(grader: .PSA, certNumber: "12345678",
                                      confidence: 0.92, rawText: "PSA MINT 12345678")
        try vm.record(candidate: candidate)

        let scans = try context.fetch(FetchDescriptor<Scan>())
        #expect(scans.count == 1)
        #expect(scans[0].grader == .PSA)
        #expect(scans[0].certNumber == "12345678")
        #expect(scans[0].status == .pendingValidation)
        #expect(scans[0].lotId == lot.id)
        #expect(scans[0].storeId == storeId)
        #expect(scans[0].userId == userId)

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.count == 1)
        #expect(outbox[0].kind == .insertScan)
    }

    @Test("BulkScanViewModel records scan when candidate fields are set; payload roundtrips")
    func payloadRoundtrips() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let userId = UUID()
        let storeId = UUID()
        let lot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId,
                      name: "Test", createdAt: Date(), updatedAt: Date())
        context.insert(lot)
        try context.save()

        let vm = BulkScanViewModel(context: context, kicker: OutboxKicker { }, lot: lot, currentUserId: userId)
        let candidate = CertCandidate(grader: .BGS, certNumber: "0123456789", confidence: 0.91,
                                       rawText: "BECKETT 9.5 GEM MINT 0123456789")
        try vm.record(candidate: candidate)

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        let payload = try JSONDecoder().decode(OutboxPayloads.InsertScan.self, from: outbox[0].payload)

        #expect(payload.grader == "BGS")
        #expect(payload.cert_number == "0123456789")
        #expect(payload.status == "pending_validation")
        #expect(payload.ocr_confidence == 0.91)
        #expect(payload.ocr_raw_text == "BECKETT 9.5 GEM MINT 0123456789")
    }

    @Test("recordCapture is idempotent for duplicate cert in same lot (unique constraint simulation)")
    func duplicateCertInLot() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let lot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId,
                      name: "Test", createdAt: Date(), updatedAt: Date())
        context.insert(lot)
        try context.save()

        let vm = BulkScanViewModel(context: context, kicker: OutboxKicker { }, lot: lot, currentUserId: userId)
        let c = CertCandidate(grader: .PSA, certNumber: "12345678", confidence: 0.95, rawText: "PSA 12345678")
        try vm.record(candidate: c)
        try vm.record(candidate: c)

        let scans = try context.fetch(FetchDescriptor<Scan>())
        #expect(scans.count == 1)   // second call is a no-op locally
    }
}
