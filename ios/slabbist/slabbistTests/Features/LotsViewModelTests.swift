import Foundation
import Testing
import SwiftData
@testable import slabbist

@Suite("LotsViewModel")
@MainActor
struct LotsViewModelTests {
    @Test("createLot inserts a Lot and outbox insertLot item in one transaction")
    func createsLotAndOutboxItem() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let vm = LotsViewModel(context: context, currentUserId: userId, currentStoreId: storeId)

        let lot = try vm.createLot(name: "Test Lot")

        #expect(lot.name == "Test Lot")
        #expect(lot.storeId == storeId)
        #expect(lot.createdByUserId == userId)
        #expect(lot.status == .open)

        let lots = try context.fetch(FetchDescriptor<Lot>())
        #expect(lots.count == 1)

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.count == 1)
        #expect(outbox[0].kind == .insertLot)
        #expect(outbox[0].status == .pending)

        let payload = try JSONDecoder().decode(OutboxPayloads.InsertLot.self, from: outbox[0].payload)
        #expect(payload.id == lot.id.uuidString)
        #expect(payload.name == "Test Lot")
        #expect(payload.notes == nil)
    }

    @Test("createLot preserves notes through the outbox payload")
    func preservesNotesInPayload() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let vm = LotsViewModel(context: context, currentUserId: UUID(), currentStoreId: UUID())
        try vm.createLot(name: "With Notes", notes: "Tagged from the stack at the back counter")

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        let payload = try JSONDecoder().decode(OutboxPayloads.InsertLot.self, from: outbox[0].payload)
        #expect(payload.notes == "Tagged from the stack at the back counter")
    }

    @Test("deleteScan removes the scan and enqueues a deleteScan outbox item")
    func deletesScanAndEnqueuesOutbox() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let lot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId,
                      name: "Lot", createdAt: Date(), updatedAt: Date())
        let scan = Scan(id: UUID(), storeId: storeId, lotId: lot.id, userId: userId,
                        grader: .PSA, certNumber: "12345678",
                        createdAt: Date(), updatedAt: Date())
        context.insert(lot)
        context.insert(scan)
        try context.save()

        let vm = LotsViewModel(context: context, currentUserId: userId, currentStoreId: storeId)
        try vm.deleteScan(scan)

        let scans = try context.fetch(FetchDescriptor<Scan>())
        #expect(scans.isEmpty)

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        let deleteItems = outbox.filter { $0.kind == .deleteScan }
        #expect(deleteItems.count == 1)
        let payload = try JSONDecoder().decode(OutboxPayloads.DeleteScan.self, from: deleteItems[0].payload)
        #expect(payload.id == scan.id.uuidString)
    }

    @Test("deleteLot cascades to all child scans and emits a deleteScan + deleteLot per row")
    func deleteLotCascadesScans() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let targetLot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId,
                            name: "Target", createdAt: Date(), updatedAt: Date())
        let bystanderLot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId,
                               name: "Bystander", createdAt: Date(), updatedAt: Date())
        let s1 = Scan(id: UUID(), storeId: storeId, lotId: targetLot.id, userId: userId,
                      grader: .PSA, certNumber: "11111111",
                      createdAt: Date(), updatedAt: Date())
        let s2 = Scan(id: UUID(), storeId: storeId, lotId: targetLot.id, userId: userId,
                      grader: .BGS, certNumber: "2222222222",
                      createdAt: Date(), updatedAt: Date())
        let bystanderScan = Scan(id: UUID(), storeId: storeId, lotId: bystanderLot.id, userId: userId,
                                 grader: .PSA, certNumber: "99999999",
                                 createdAt: Date(), updatedAt: Date())
        context.insert(targetLot)
        context.insert(bystanderLot)
        context.insert(s1)
        context.insert(s2)
        context.insert(bystanderScan)
        try context.save()

        let vm = LotsViewModel(context: context, currentUserId: userId, currentStoreId: storeId)
        try vm.deleteLot(targetLot)

        let lots = try context.fetch(FetchDescriptor<Lot>())
        #expect(lots.map(\.name) == ["Bystander"])

        let scans = try context.fetch(FetchDescriptor<Scan>())
        #expect(scans.count == 1)
        #expect(scans[0].certNumber == "99999999")

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        let scanDeletes = outbox.filter { $0.kind == .deleteScan }
        let lotDeletes = outbox.filter { $0.kind == .deleteLot }
        #expect(scanDeletes.count == 2)
        #expect(lotDeletes.count == 1)
        let lotPayload = try JSONDecoder().decode(OutboxPayloads.DeleteLot.self, from: lotDeletes[0].payload)
        #expect(lotPayload.id == targetLot.id.uuidString)
    }

    @Test("listOpenLots returns only open lots for the current store, newest first")
    func listsOpenLotsNewestFirst() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let otherStoreId = UUID()

        let older = Lot(id: UUID(), storeId: storeId, createdByUserId: userId, name: "older",
                        createdAt: Date(timeIntervalSinceNow: -1000), updatedAt: Date())
        let newer = Lot(id: UUID(), storeId: storeId, createdByUserId: userId, name: "newer",
                        createdAt: Date(), updatedAt: Date())
        let closed = Lot(id: UUID(), storeId: storeId, createdByUserId: userId, name: "closed",
                         status: .closed, createdAt: Date(), updatedAt: Date())
        let otherStore = Lot(id: UUID(), storeId: otherStoreId, createdByUserId: userId, name: "other",
                             createdAt: Date(), updatedAt: Date())

        [older, newer, closed, otherStore].forEach(context.insert)
        try context.save()

        let vm = LotsViewModel(context: context, currentUserId: userId, currentStoreId: storeId)
        let lots = try vm.listOpenLots()

        #expect(lots.map(\.name) == ["newer", "older"])
    }
}
