import Foundation
import SwiftData
import Testing
@testable import slabbist

/// Coverage for the Plan 3 commit/void surface on `OfferRepository`:
/// enqueueing the right outbox kinds, refusing to commit non-accepted lots,
/// and keeping the lot in `.accepted` until the drainer + hydrator confirm.
@MainActor
struct OfferRepositoryCommitTests {
    @Test func commitEnqueuesOutboxItemAndKeepsLotAccepted() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let kicker = OutboxKicker { /* no-op */ }
        let lot = Lot(
            id: UUID(),
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "L",
            createdAt: Date(),
            updatedAt: Date()
        )
        lot.lotOfferState = LotOfferState.accepted.rawValue
        context.insert(lot)
        try context.save()

        let repo = OfferRepository(
            context: context,
            kicker: kicker,
            currentStoreId: lot.storeId,
            currentUserId: UUID()
        )
        try repo.commit(lot: lot, paymentMethod: "cash", paymentReference: nil)
        // Lot stays accepted until the worker round-trips and the hydrator flips to .paid.
        #expect(lot.lotOfferState == LotOfferState.accepted.rawValue)
        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.contains(where: { $0.kind == .commitTransaction }))
    }

    @Test func commitRejectsNonAcceptedLots() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let kicker = OutboxKicker { /* no-op */ }
        let lot = Lot(
            id: UUID(),
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "L",
            createdAt: Date(),
            updatedAt: Date()
        )
        lot.lotOfferState = LotOfferState.priced.rawValue
        context.insert(lot)
        try context.save()
        let repo = OfferRepository(
            context: context,
            kicker: kicker,
            currentStoreId: lot.storeId,
            currentUserId: UUID()
        )
        #expect(throws: OfferRepository.InvalidTransition.self) {
            try repo.commit(lot: lot, paymentMethod: "cash", paymentReference: nil)
        }
    }

    @Test func reopenVoidedTransitionsToPriced() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let kicker = OutboxKicker { /* no-op */ }
        let lot = Lot(
            id: UUID(),
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "L",
            createdAt: Date(),
            updatedAt: Date()
        )
        lot.lotOfferState = LotOfferState.voided.rawValue
        context.insert(lot)
        try context.save()
        let repo = OfferRepository(
            context: context,
            kicker: kicker,
            currentStoreId: lot.storeId,
            currentUserId: UUID()
        )
        try repo.reopenVoided(lot)
        #expect(lot.lotOfferState == LotOfferState.priced.rawValue)
    }

    @Test func voidTransactionEnqueuesItem() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let kicker = OutboxKicker { /* no-op */ }
        let txn = StoreTransaction(
            id: UUID(),
            storeId: UUID(),
            lotId: UUID(),
            vendorId: nil,
            vendorNameSnapshot: "X",
            totalBuyCents: 100,
            paymentMethod: "cash",
            paymentReference: nil,
            paidAt: Date(),
            paidByUserId: UUID(),
            createdAt: Date()
        )
        context.insert(txn)
        try context.save()
        let repo = OfferRepository(
            context: context,
            kicker: kicker,
            currentStoreId: txn.storeId,
            currentUserId: UUID()
        )
        try repo.voidTransaction(txn, reason: "tester")
        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.contains(where: { $0.kind == .voidTransaction }))
    }
}
