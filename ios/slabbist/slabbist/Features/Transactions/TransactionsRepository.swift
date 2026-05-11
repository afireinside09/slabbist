import Foundation
import SwiftData

/// Read-side repository for `StoreTransaction` rows. Queries are scoped to
/// the active store and ordered for the views that consume them:
/// - `listAll` powers the global Transactions tab.
/// - `listForVendor` powers the vendor purchase-history detail.
/// - `listRecent` backs the "Recent transactions" rail on `LotsListView`.
/// - `linesFor` hydrates the line items for the transaction detail screen.
///
/// The repository deliberately stays read-only. Writes for commit/void flow
/// through `OfferRepository` and `TransactionsHydrator` so the outbox stays
/// the single producer of server-mutating effects.
@MainActor
final class TransactionsRepository {
    private let context: ModelContext
    private let kicker: OutboxKicker
    let currentStoreId: UUID

    init(context: ModelContext, kicker: OutboxKicker, currentStoreId: UUID) {
        self.context = context
        self.kicker = kicker
        self.currentStoreId = currentStoreId
    }

    func listAll() throws -> [StoreTransaction] {
        let storeId = currentStoreId
        let descriptor = FetchDescriptor<StoreTransaction>(
            predicate: #Predicate<StoreTransaction> { $0.storeId == storeId },
            sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func listForVendor(_ vendorId: UUID) throws -> [StoreTransaction] {
        let storeId = currentStoreId
        let descriptor = FetchDescriptor<StoreTransaction>(
            predicate: #Predicate<StoreTransaction> {
                $0.storeId == storeId && $0.vendorId == vendorId
            },
            sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func linesFor(_ txn: StoreTransaction) throws -> [TransactionLine] {
        let txnId = txn.id
        let descriptor = FetchDescriptor<TransactionLine>(
            predicate: #Predicate<TransactionLine> { $0.transactionId == txnId },
            sortBy: [SortDescriptor(\.lineIndex)]
        )
        return try context.fetch(descriptor)
    }

    /// Returns transactions paid in the last `days` days, scoped to the store.
    /// Used by the "Recent transactions" section on `LotsListView`.
    func listRecent(days: Int) throws -> [StoreTransaction] {
        let storeId = currentStoreId
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        let descriptor = FetchDescriptor<StoreTransaction>(
            predicate: #Predicate<StoreTransaction> {
                $0.storeId == storeId && $0.paidAt >= since
            },
            sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }
}
