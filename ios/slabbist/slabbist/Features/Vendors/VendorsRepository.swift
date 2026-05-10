import Foundation
import SwiftData

/// View-model-facing facade for the local `Vendor` SwiftData store and the
/// outbox queue. Mirrors the pattern in `LotsViewModel` (insert / patch +
/// `OutboxKicker.kick()` after `context.save()`) but encapsulates the writes
/// on a repository so multiple call sites — list, picker, edit sheet, scan
/// detail — share one source of truth.
///
/// Distinct from `VendorRepository` (singular) under `Core/Data/Repositories/`
/// which speaks to Supabase via the network. This local-side type never
/// reaches the server directly; the outbox worker (Plan 2) drains the
/// enqueued items and PATCHes Postgres.
@MainActor
final class VendorsRepository {
    private let context: ModelContext
    private let kicker: OutboxKicker
    let currentStoreId: UUID

    init(context: ModelContext, kicker: OutboxKicker, currentStoreId: UUID) {
        self.context = context
        self.kicker = kicker
        self.currentStoreId = currentStoreId
    }

    /// Insert-or-update by primary key. Pass `nil` for `id` to create a new
    /// row; pass an existing `vendor.id` to patch in place. Either path
    /// emits exactly one `upsertVendor` outbox item carrying the full row
    /// (server-side UPSERT semantics — no separate "patch" payload).
    @discardableResult
    func upsert(
        id: UUID?,
        displayName: String,
        contactMethod: String?,
        contactValue: String?,
        notes: String?
    ) throws -> Vendor {
        let now = Date()
        let resolvedId = id ?? UUID()
        let predicate = #Predicate<Vendor> { $0.id == resolvedId }
        let existing = try context.fetch(FetchDescriptor<Vendor>(predicate: predicate)).first

        let vendor: Vendor
        if let existing {
            existing.displayName = displayName
            existing.contactMethod = contactMethod
            existing.contactValue = contactValue
            existing.notes = notes
            existing.updatedAt = now
            vendor = existing
        } else {
            vendor = Vendor(
                id: resolvedId,
                storeId: currentStoreId,
                displayName: displayName,
                contactMethod: contactMethod,
                contactValue: contactValue,
                notes: notes,
                createdAt: now,
                updatedAt: now
            )
            context.insert(vendor)
        }

        try enqueueUpsert(vendor, now: now)
        try context.save()
        kicker.kick()
        return vendor
    }

    /// Soft-archive — flips `archivedAt` and emits a dedicated payload so the
    /// worker can patch a single column instead of rewriting the whole row.
    /// Idempotent: re-archiving an already-archived row pushes a fresh
    /// timestamp through and re-enqueues, which is fine for the worker.
    func archive(_ vendor: Vendor) throws {
        let now = Date()
        vendor.archivedAt = now
        vendor.updatedAt = now
        let payload = OutboxPayloads.ArchiveVendor(
            id: vendor.id.uuidString,
            archived_at: ISO8601DateFormatter.shared.string(from: now)
        )
        let item = OutboxItem(
            id: UUID(),
            kind: .archiveVendor,
            payload: try JSONEncoder().encode(payload),
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        )
        context.insert(item)
        try context.save()
        kicker.kick()
    }

    /// Reactivate an archived vendor. Goes through the full upsert path so
    /// the outbox worker rewrites every column — `archived_at` lands as
    /// `null` and `updated_at` advances.
    func reactivate(_ vendor: Vendor) throws {
        let now = Date()
        vendor.archivedAt = nil
        vendor.updatedAt = now
        try enqueueUpsert(vendor, now: now)
        try context.save()
        kicker.kick()
    }

    /// Active vendors for the current store, alphabetised by display name —
    /// the order pickers and the settings list both want.
    func listActive() throws -> [Vendor] {
        let storeId = currentStoreId
        let descriptor = FetchDescriptor<Vendor>(
            predicate: #Predicate<Vendor> { $0.storeId == storeId && $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.displayName, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    /// Archived vendors for the current store — surfaced in a separate
    /// "Archived" section so the user can reactivate without losing history.
    func listArchived() throws -> [Vendor] {
        let storeId = currentStoreId
        let descriptor = FetchDescriptor<Vendor>(
            predicate: #Predicate<Vendor> { $0.storeId == storeId && $0.archivedAt != nil },
            sortBy: [SortDescriptor(\.displayName, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Outbox encoding

    private func enqueueUpsert(_ v: Vendor, now: Date) throws {
        let payload = OutboxPayloads.UpsertVendor(
            id: v.id.uuidString,
            store_id: v.storeId.uuidString,
            display_name: v.displayName,
            contact_method: v.contactMethod,
            contact_value: v.contactValue,
            notes: v.notes,
            archived_at: v.archivedAt.map { ISO8601DateFormatter.shared.string(from: $0) },
            created_at: ISO8601DateFormatter.shared.string(from: v.createdAt),
            updated_at: ISO8601DateFormatter.shared.string(from: v.updatedAt)
        )
        let item = OutboxItem(
            id: UUID(),
            kind: .upsertVendor,
            payload: try JSONEncoder().encode(payload),
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        )
        context.insert(item)
    }
}
