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
