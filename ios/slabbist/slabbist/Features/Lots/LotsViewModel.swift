import Foundation
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
        // SwiftData's #Predicate macro can't capture enum values directly.
        // Fetch by store + sort, filter .open in-memory. With fetchLimit=200
        // this is still bounded and fine for Plan 1's scale.
        var descriptor = FetchDescriptor<Lot>(
            predicate: #Predicate<Lot> { $0.storeId == storeId },
            sortBy: [SortDescriptor(\Lot.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        let all = try context.fetch(descriptor)
        return all.filter { $0.status == .open }
    }
}
