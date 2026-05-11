import Foundation
import SwiftData
import Supabase

/// Persists the result of a `/transaction-commit` or `/transaction-void`
/// round-trip into the iOS SwiftData store. Runs on the MainActor since
/// SwiftData `@Model` instances aren't `Sendable` — the drainer hops
/// here after the network call lands.
///
/// The hydrator is intentionally idempotent: re-applying the same response
/// against an already-hydrated row is a no-op. That matters because the
/// outbox can replay the same item after a retry, and the dedupe path on
/// the server returns the same shape as a fresh commit (`deduped: true`)
/// — we don't want a replay to duplicate any local state.
@MainActor
enum TransactionsHydrator {
    static func upsert(commitResponse: TransactionCommitResponse, container: ModelContainer) async throws {
        let context = ModelContext(container)
        let row = commitResponse.transaction
        guard let txnId = UUID(uuidString: row.id) else { return }
        let existing = try? context.fetch(
            FetchDescriptor<StoreTransaction>(predicate: #Predicate { $0.id == txnId })
        ).first
        let txn = existing ?? StoreTransaction(
            id: txnId,
            storeId: UUID(uuidString: row.store_id) ?? UUID(),
            lotId: UUID(uuidString: row.lot_id) ?? UUID(),
            vendorId: row.vendor_id.flatMap(UUID.init(uuidString:)),
            vendorNameSnapshot: row.vendor_name_snapshot,
            totalBuyCents: row.total_buy_cents,
            paymentMethod: row.payment_method,
            paymentReference: row.payment_reference,
            paidAt: parseISO(row.paid_at) ?? Date(),
            paidByUserId: UUID(uuidString: row.paid_by_user_id) ?? UUID(),
            createdAt: Date()
        )
        if existing == nil {
            context.insert(txn)
        } else {
            // Update mutable fields on the existing instance — server is the
            // authority for any drift after the row was last hydrated.
            txn.vendorNameSnapshot = row.vendor_name_snapshot
            txn.totalBuyCents = row.total_buy_cents
            txn.paymentMethod = row.payment_method
            txn.paymentReference = row.payment_reference
            txn.voidedAt = row.voided_at.flatMap(parseISO)
            txn.voidedByUserId = row.voided_by_user_id.flatMap(UUID.init(uuidString:))
            txn.voidReason = row.void_reason
            txn.voidOfTransactionId = row.void_of_transaction_id.flatMap(UUID.init(uuidString:))
        }

        // Upsert lines. The unique key is (transaction_id, scan_id) server-side;
        // we mirror that as `compositeKey` on the SwiftData model.
        for line in commitResponse.lines {
            guard let txId = UUID(uuidString: line.transaction_id),
                  let scId = UUID(uuidString: line.scan_id) else { continue }
            let composite = "\(txId.uuidString):\(scId.uuidString)"
            let lineExisting = try? context.fetch(
                FetchDescriptor<TransactionLine>(predicate: #Predicate { $0.compositeKey == composite })
            ).first
            let snapshotData = encodeIdentitySnapshot(line.identity_snapshot)
            if let lineExisting {
                lineExisting.buyPriceCents = line.buy_price_cents
                lineExisting.lineIndex = line.line_index
                lineExisting.identitySnapshotJSON = snapshotData
            } else {
                let lineRow = TransactionLine(
                    transactionId: txId, scanId: scId,
                    lineIndex: line.line_index,
                    buyPriceCents: line.buy_price_cents,
                    identitySnapshotJSON: snapshotData
                )
                context.insert(lineRow)
            }
        }

        // Flip the lot to paid + converted so the lots list immediately
        // reflects the new state without a refresh round-trip.
        let lotId = txn.lotId
        if let lot = try? context.fetch(
            FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
        ).first {
            lot.lotOfferState = LotOfferState.paid.rawValue
            lot.lotOfferStateUpdatedAt = Date()
            lot.status = .converted
            lot.updatedAt = Date()
        }

        try context.save()
    }

    static func upsert(voidResponse: TransactionVoidResponse, container: ModelContainer) async throws {
        // The void response contains the NEW void row plus the original_id.
        // We hydrate the void row, mirror voidedAt onto the original (the
        // server already stamped it server-side), and flip the lot.
        let context = ModelContext(container)

        let row = voidResponse.void_transaction
        guard let voidId = UUID(uuidString: row.id) else { return }
        let voidExisting = try? context.fetch(
            FetchDescriptor<StoreTransaction>(predicate: #Predicate { $0.id == voidId })
        ).first
        if voidExisting == nil {
            let voidRow = StoreTransaction(
                id: voidId,
                storeId: UUID(uuidString: row.store_id) ?? UUID(),
                lotId: UUID(uuidString: row.lot_id) ?? UUID(),
                vendorId: row.vendor_id.flatMap(UUID.init(uuidString:)),
                vendorNameSnapshot: row.vendor_name_snapshot,
                totalBuyCents: row.total_buy_cents,
                paymentMethod: row.payment_method,
                paymentReference: row.payment_reference,
                paidAt: parseISO(row.paid_at) ?? Date(),
                paidByUserId: UUID(uuidString: row.paid_by_user_id) ?? UUID(),
                voidedAt: parseISO(row.voided_at ?? ""),
                voidedByUserId: row.voided_by_user_id.flatMap(UUID.init(uuidString:)),
                voidReason: row.void_reason,
                voidOfTransactionId: row.void_of_transaction_id.flatMap(UUID.init(uuidString:)),
                createdAt: Date()
            )
            context.insert(voidRow)
        }

        // Mirror the server's `voided_at` stamp onto the local original row.
        // The void row's `voidReason` carries the human text — we don't have
        // it broken out separately here, but consumers reading the original
        // can look it up via `voidOfTransactionId` on the void row.
        if let origId = UUID(uuidString: voidResponse.original_id),
           let orig = try? context.fetch(
               FetchDescriptor<StoreTransaction>(predicate: #Predicate { $0.id == origId })
           ).first {
            orig.voidedAt = Date()
        }

        // Flip the lot back to voided so it can be re-opened by the seller.
        if let lotId = UUID(uuidString: row.lot_id),
           let lot = try? context.fetch(
               FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
           ).first {
            lot.lotOfferState = LotOfferState.voided.rawValue
            lot.lotOfferStateUpdatedAt = Date()
        }

        try context.save()
    }

    // MARK: - Helpers

    private static func parseISO(_ s: String) -> Date? {
        ISO8601DateFormatter().date(from: s)
    }

    /// Re-encode the `identity_snapshot` JSON object into bytes for SwiftData.
    /// Falls back to an empty `{}` object if encoding fails — this is a
    /// best-effort snapshot so the lot detail can display card identity
    /// metadata; failing to encode it should not block the commit.
    private static func encodeIdentitySnapshot(_ snapshot: AnyJSON?) -> Data {
        guard let snapshot else {
            return Data("{}".utf8)
        }
        do {
            return try JSONEncoder().encode(snapshot)
        } catch {
            return Data("{}".utf8)
        }
    }
}
