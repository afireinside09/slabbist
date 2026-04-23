import Foundation
import OSLog
import SwiftData

@MainActor
@Observable
final class LotsViewModel {
    private let context: ModelContext
    let currentUserId: UUID
    let currentStoreId: UUID

    init(context: ModelContext, currentUserId: UUID, currentStoreId: UUID) {
        self.context = context
        self.currentUserId = currentUserId
        self.currentStoreId = currentStoreId
    }

    /// Resolves the signed-in user's `Store` from the local model context
    /// and returns a configured view model. Returns `nil` when the user
    /// is signed out or their `Store` hasn't synced yet (e.g. fresh
    /// signup waiting for the outbox worker). The call site decides
    /// what to show while this is `nil`.
    static func resolve(context: ModelContext, session: SessionStore) -> LotsViewModel? {
        guard let userId = session.userId else { return nil }
        let ownerId = userId
        var descriptor = FetchDescriptor<Store>(
            predicate: #Predicate<Store> { $0.ownerUserId == ownerId }
        )
        descriptor.fetchLimit = 1
        guard let store = try? context.fetch(descriptor).first else {
            AppLog.lots.warning("no local Store for user \(userId, privacy: .public); view model deferred")
            return nil
        }
        return LotsViewModel(context: context, currentUserId: userId, currentStoreId: store.id)
    }

    @discardableResult
    func createLot(name: String, notes: String? = nil) throws -> Lot {
        let now = Date()
        let lot = Lot(
            id: UUID(),
            storeId: currentStoreId,
            createdByUserId: currentUserId,
            name: name,
            notes: notes,
            createdAt: now,
            updatedAt: now
        )
        context.insert(lot)

        let dto = OutboxPayloads.InsertLot(
            id: lot.id.uuidString,
            store_id: lot.storeId.uuidString,
            created_by_user_id: lot.createdByUserId.uuidString,
            name: lot.name,
            notes: lot.notes,
            status: lot.status.rawValue,
            created_at: ISO8601DateFormatter.shared.string(from: lot.createdAt),
            updated_at: ISO8601DateFormatter.shared.string(from: lot.updatedAt)
        )
        let encoded = try JSONEncoder().encode(dto)

        let outboxItem = OutboxItem(
            id: UUID(),
            kind: .insertLot,
            payload: encoded,
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        )
        context.insert(outboxItem)

        try context.save()
        return lot
    }

    func listOpenLots() throws -> [Lot] {
        let storeId = currentStoreId
        // SwiftData's `#Predicate` macro doesn't translate enum equality
        // against a stored `LotStatus` property to SQL at fetch time
        // (confirmed against iOS 26 SDK — the predicate returns zero rows
        // when we include `$0.status == .open`). Fetch by store + sort,
        // then filter `.open` in-memory. `fetchLimit = 200` keeps this
        // bounded; a store with more lots than that at Plan 1 scale is
        // unexpected, and we'd switch to keyset pagination anyway.
        var descriptor = FetchDescriptor<Lot>(
            predicate: #Predicate<Lot> { $0.storeId == storeId },
            sortBy: [SortDescriptor(\Lot.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        return try context.fetch(descriptor).filter { $0.status == .open }
    }
}
