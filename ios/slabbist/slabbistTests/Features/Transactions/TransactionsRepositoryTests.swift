import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct TransactionsRepositoryTests {
    private func seed() -> (TransactionsRepository, ModelContext, UUID) {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let storeId = UUID()
        let kicker = OutboxKicker { /* no-op */ }
        let repo = TransactionsRepository(context: context, kicker: kicker, currentStoreId: storeId)
        return (repo, context, storeId)
    }

    @Test func listSortsByPaidAtDesc() throws {
        let (repo, context, storeId) = seed()
        let now = Date()
        let txnOld = StoreTransaction(id: UUID(), storeId: storeId, lotId: UUID(), vendorId: nil, vendorNameSnapshot: "Old", totalBuyCents: 100, paymentMethod: "cash", paymentReference: nil, paidAt: now.addingTimeInterval(-100), paidByUserId: UUID(), createdAt: now)
        let txnNew = StoreTransaction(id: UUID(), storeId: storeId, lotId: UUID(), vendorId: nil, vendorNameSnapshot: "New", totalBuyCents: 200, paymentMethod: "cash", paymentReference: nil, paidAt: now, paidByUserId: UUID(), createdAt: now)
        context.insert(txnOld); context.insert(txnNew); try context.save()
        let listed = try repo.listAll()
        #expect(listed.first?.id == txnNew.id)
    }

    @Test func listForVendorScopesByVendorId() throws {
        let (repo, context, storeId) = seed()
        let v1 = UUID(); let v2 = UUID()
        let now = Date()
        context.insert(StoreTransaction(id: UUID(), storeId: storeId, lotId: UUID(), vendorId: v1, vendorNameSnapshot: "A", totalBuyCents: 100, paymentMethod: "cash", paymentReference: nil, paidAt: now, paidByUserId: UUID(), createdAt: now))
        context.insert(StoreTransaction(id: UUID(), storeId: storeId, lotId: UUID(), vendorId: v2, vendorNameSnapshot: "B", totalBuyCents: 200, paymentMethod: "cash", paymentReference: nil, paidAt: now, paidByUserId: UUID(), createdAt: now))
        try context.save()
        let listed = try repo.listForVendor(v1)
        #expect(listed.count == 1)
        #expect(listed.first?.vendorNameSnapshot == "A")
    }
}
