import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct StoreTransactionTests {
    @Test func insertAndFetch() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let txn = StoreTransaction(
            id: UUID(), storeId: UUID(), lotId: UUID(),
            vendorId: UUID(), vendorNameSnapshot: "Acme",
            totalBuyCents: 1500, paymentMethod: "cash",
            paymentReference: nil,
            paidAt: Date(), paidByUserId: UUID(),
            createdAt: Date()
        )
        context.insert(txn)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<StoreTransaction>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.totalBuyCents == 1500)
    }
}
