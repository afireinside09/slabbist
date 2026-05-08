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

    /// Persist the user-entered manual price for a scan. Pass `nil` to
    /// clear it (revert to whatever Pokemon Price Tracker eventually
    /// returns). Mutates the scan in place and enqueues an
    /// `updateScanOffer` outbox item so the value survives sync.
    func setOfferCents(scan: Scan, cents: Int64?) throws {
        let now = Date()
        scan.offerCents = cents
        scan.updatedAt = now

        let dto = OutboxPayloads.UpdateScanOffer(
            id: scan.id.uuidString,
            offer_cents: cents,
            updated_at: ISO8601DateFormatter.shared.string(from: now)
        )
        let encoded = try JSONEncoder().encode(dto)
        context.insert(OutboxItem(
            id: UUID(),
            kind: .updateScanOffer,
            payload: encoded,
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        ))
        try context.save()
    }

    /// Delete a single scan locally and enqueue the server-side delete.
    /// Idempotent — repeat calls find nothing to remove and exit cleanly.
    func deleteScan(_ scan: Scan) throws {
        let scanId = scan.id
        let now = Date()

        // Local-first: remove from SwiftData. The cert-lookup snapshot (if
        // any) lives keyed on `gradedCardIdentityId`, not `scan.id`, and is
        // deliberately retained — other scans of the same product still
        // benefit from the cached comp.
        context.delete(scan)

        let dto = OutboxPayloads.DeleteScan(
            id: scanId.uuidString,
            deleted_at: ISO8601DateFormatter.shared.string(from: now)
        )
        let encoded = try JSONEncoder().encode(dto)

        let outboxItem = OutboxItem(
            id: UUID(),
            kind: .deleteScan,
            payload: encoded,
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        )
        context.insert(outboxItem)
        try context.save()
    }

    /// Delete an entire lot — cascades to all of its scans locally so the
    /// queue view immediately reflects the removal. Each cascaded scan
    /// emits its own `DeleteScan` outbox item so the server reconciles
    /// piece by piece (no server-side cascade is wired today; see the
    /// `DeleteLot` payload doc-comment).
    func deleteLot(_ lot: Lot) throws {
        let lotId = lot.id
        let now = Date()

        // Cascade scans first so we can encode their delete payloads while
        // the rows are still attached to the context.
        var scanDescriptor = FetchDescriptor<Scan>(
            predicate: #Predicate<Scan> { $0.lotId == lotId }
        )
        scanDescriptor.fetchLimit = 1_000
        let scans = (try? context.fetch(scanDescriptor)) ?? []

        for scan in scans {
            let dto = OutboxPayloads.DeleteScan(
                id: scan.id.uuidString,
                deleted_at: ISO8601DateFormatter.shared.string(from: now)
            )
            let encoded = try JSONEncoder().encode(dto)
            context.insert(OutboxItem(
                id: UUID(),
                kind: .deleteScan,
                payload: encoded,
                status: .pending,
                attempts: 0,
                createdAt: now,
                nextAttemptAt: now
            ))
            context.delete(scan)
        }

        let lotDto = OutboxPayloads.DeleteLot(
            id: lotId.uuidString,
            deleted_at: ISO8601DateFormatter.shared.string(from: now)
        )
        let encoded = try JSONEncoder().encode(lotDto)
        context.insert(OutboxItem(
            id: UUID(),
            kind: .deleteLot,
            payload: encoded,
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        ))
        context.delete(lot)

        try context.save()
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
