import Foundation
import SwiftData

/// Mutation surface for per-store configuration that lives on the
/// `stores` row (the per-store margin ladder today; room for future
/// settings later). Mirrors `VendorsRepository` / `OfferRepository`:
/// every write mutates SwiftData, enqueues an outbox patch, saves the
/// context, and kicks the drainer.
@MainActor
final class StoreSettingsRepository {
    private let context: ModelContext
    private let kicker: OutboxKicker
    let currentStoreId: UUID

    init(context: ModelContext, kicker: OutboxKicker, currentStoreId: UUID) {
        self.context = context
        self.kicker = kicker
        self.currentStoreId = currentStoreId
    }

    /// Replace the store's margin ladder with `tiers`. Canonicalizes
    /// (sort + clamp) before writing so the local cache and the outbox
    /// payload stay in lookup-ready shape.
    ///
    /// Throws when the local Store row can't be found — happens only if
    /// the hydrator hasn't run yet, in which case the caller should
    /// defer the edit until `LotsViewModel.resolve` succeeds.
    func updateMarginLadder(_ tiers: [MarginTier]) throws {
        let id = currentStoreId
        var descriptor = FetchDescriptor<Store>(
            predicate: #Predicate<Store> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let store = try context.fetch(descriptor).first else {
            throw Error.storeNotFound
        }

        let canonical = tiers.canonicalized()
        store.applyMarginLadder(canonical)

        let jsonData = try JSONEncoder().encode(canonical)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

        let payload = OutboxPayloads.UpdateStoreMargin(
            id: store.id.uuidString,
            margin_ladder_json: jsonString
        )
        let now = Date()
        let item = OutboxItem(
            id: UUID(),
            kind: .updateStoreMargin,
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

    enum Error: Swift.Error { case storeNotFound }
}
