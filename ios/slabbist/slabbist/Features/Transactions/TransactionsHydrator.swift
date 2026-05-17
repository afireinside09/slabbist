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
        // D1: use `mainContext` so `@Query`-subscribed views (LotDetail's
        // frozen banner / receipt link) observe the write without needing
        // a follow-up render. Per-call `ModelContext(container)` would
        // commit to the store but iOS 17/18/26 `@Query` doesn't reliably
        // pick that up on already-mounted views.
        let context = container.mainContext
        let row = commitResponse.transaction

        // D1 (P1.3): all-or-nothing hydration. Validate EVERY UUID in the
        // response — including all line rows — BEFORE we touch the context.
        // A malformed line UUID partway through the loop would have left a
        // half-hydrated lot (transaction row inserted, lines missing) that
        // the user could never reconcile: retry replays the commit, server
        // returns 409 ALREADY_COMMITTED, drainer drains the outbox row as
        // success, lot is stuck forever. By validating up front we throw
        // before any `context.insert`, so the outbox row goes `.failed`
        // and a retry replays cleanly.
        //
        // Trade-off vs. the alternative ("keep `?? continue` for lines and
        // surface skipped count in lastError"): all-or-nothing is simpler,
        // deterministic, and matches the existing OutboxBridgeError contract.
        // The lines loop's UUIDs are server-generated; a bad value is a
        // server bug that should bubble out, not a per-row recoverable input.
        let txnId = try requireUUID(row.id, field: "transaction.id")
        let storeId = try requireUUID(row.store_id, field: "transaction.store_id")
        let lotId = try requireUUID(row.lot_id, field: "transaction.lot_id")
        let paidByUserId = try requireUUID(row.paid_by_user_id, field: "transaction.paid_by_user_id")

        // Pre-validate every line UUID into a parallel array. If any throws,
        // we exit before mutating the context — no partial state lands.
        struct ValidatedLine {
            let txId: UUID
            let scId: UUID
            let line: TransactionCommitResponse.LineRow
        }
        var validatedLines: [ValidatedLine] = []
        validatedLines.reserveCapacity(commitResponse.lines.count)
        for line in commitResponse.lines {
            let txId = try requireUUID(line.transaction_id, field: "line.transaction_id")
            let scId = try requireUUID(line.scan_id, field: "line.scan_id")
            validatedLines.append(ValidatedLine(txId: txId, scId: scId, line: line))
        }

        // ----- All validation passed; mutations below are atomic-on-save. -----

        let existing = try? context.fetch(
            FetchDescriptor<StoreTransaction>(predicate: #Predicate { $0.id == txnId })
        ).first
        let txn = existing ?? StoreTransaction(
            id: txnId,
            storeId: storeId,
            lotId: lotId,
            vendorId: row.vendor_id.flatMap(UUID.init(uuidString:)),
            vendorNameSnapshot: row.vendor_name_snapshot,
            totalBuyCents: row.total_buy_cents,
            paymentMethod: row.payment_method,
            paymentReference: row.payment_reference,
            paidAt: parseISO(row.paid_at) ?? Date(),
            paidByUserId: paidByUserId,
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
        for vl in validatedLines {
            let composite = "\(vl.txId.uuidString):\(vl.scId.uuidString)"
            let lineExisting = try? context.fetch(
                FetchDescriptor<TransactionLine>(predicate: #Predicate { $0.compositeKey == composite })
            ).first
            let snapshotData = encodeIdentitySnapshot(vl.line.identity_snapshot)
            if let lineExisting {
                lineExisting.buyPriceCents = vl.line.buy_price_cents
                lineExisting.lineIndex = vl.line.line_index
                lineExisting.identitySnapshotJSON = snapshotData
            } else {
                let lineRow = TransactionLine(
                    transactionId: vl.txId, scanId: vl.scId,
                    lineIndex: vl.line.line_index,
                    buyPriceCents: vl.line.buy_price_cents,
                    identitySnapshotJSON: snapshotData
                )
                context.insert(lineRow)
            }
        }

        // Flip the lot to paid + converted so the lots list immediately
        // reflects the new state without a refresh round-trip. `lotId` was
        // already validated above.
        if let lot = try? context.fetch(
            FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
        ).first {
            lot.lotOfferState = LotOfferState.paid.rawValue
            lot.lotOfferStateUpdatedAt = Date()
            lot.status = .converted
            lot.updatedAt = Date()
        }

        // P0.2: explicit `save()`. `mainContext` lives for the app
        // lifetime, so without an explicit save the writes ride on
        // SwiftData's runloop-tick autosave — which can be lost if the
        // process is killed in the millisecond gap between dispatch and
        // tick. After this returns, the outbox row is deleted (server
        // says committed); a lost autosave would leave the local lot
        // un-flipped with no replay path. Save synchronously and let
        // failure surface through the drainer's classifier.
        try context.save()
    }

    static func upsert(voidResponse: TransactionVoidResponse, container: ModelContainer) async throws {
        // The void response contains the NEW void row plus the original_id.
        // We hydrate the void row, mirror voidedAt onto the original (the
        // server already stamped it server-side), and flip the lot.
        //
        // D1: same `mainContext` + UUID validation rationale as the commit
        // path above.
        let context = container.mainContext

        let row = voidResponse.void_transaction
        // D1 (P1.3): all-or-nothing — validate `original_id` up front too,
        // not just where it's first used below. Otherwise a malformed
        // `original_id` would leave the void row inserted without the
        // mirror-back step on the original — the original stays without a
        // `voidedAt` stamp forever, the lot's banner is wrong, and there's
        // no replay path because the server has already committed.
        let voidId = try requireUUID(row.id, field: "void_transaction.id")
        let voidStoreId = try requireUUID(row.store_id, field: "void_transaction.store_id")
        let voidLotId = try requireUUID(row.lot_id, field: "void_transaction.lot_id")
        let voidPaidByUserId = try requireUUID(row.paid_by_user_id, field: "void_transaction.paid_by_user_id")
        let origId = try requireUUID(voidResponse.original_id, field: "original_id")

        // ----- All validation passed; mutations below are atomic-on-save. -----

        let voidExisting = try? context.fetch(
            FetchDescriptor<StoreTransaction>(predicate: #Predicate { $0.id == voidId })
        ).first
        if voidExisting == nil {
            let voidRow = StoreTransaction(
                id: voidId,
                storeId: voidStoreId,
                lotId: voidLotId,
                vendorId: row.vendor_id.flatMap(UUID.init(uuidString:)),
                vendorNameSnapshot: row.vendor_name_snapshot,
                totalBuyCents: row.total_buy_cents,
                paymentMethod: row.payment_method,
                paymentReference: row.payment_reference,
                paidAt: parseISO(row.paid_at) ?? Date(),
                paidByUserId: voidPaidByUserId,
                voidedAt: row.voided_at.flatMap(parseISO),
                voidedByUserId: row.voided_by_user_id.flatMap(UUID.init(uuidString:)),
                voidReason: row.void_reason,
                voidOfTransactionId: row.void_of_transaction_id.flatMap(UUID.init(uuidString:)),
                createdAt: Date()
            )
            context.insert(voidRow)
        }

        // Mirror the server's `voided_at` stamp onto the local original row.
        // Sourced from the void row's `voided_at` (the server stamps the
        // same timestamp on both the void row and the original) — using
        // `Date()` here would drift from the server truth by the network
        // round-trip. Falls back to `Date()` only when the server response
        // somehow omits the field, which shouldn't happen in practice.
        // `origId` was validated above.
        if let orig = try? context.fetch(
            FetchDescriptor<StoreTransaction>(predicate: #Predicate { $0.id == origId })
        ).first {
            orig.voidedAt = voidResponse.void_transaction.voided_at.flatMap(parseISO) ?? Date()
        }

        // Flip the lot back to voided so it can be re-opened by the seller.
        // `voidLotId` was already validated above.
        if let lot = try? context.fetch(
            FetchDescriptor<Lot>(predicate: #Predicate { $0.id == voidLotId })
        ).first {
            lot.lotOfferState = LotOfferState.voided.rawValue
            lot.lotOfferStateUpdatedAt = Date()
        }

        // P0.2: explicit `save()` — same rationale as the commit path. A
        // lost autosave after the outbox row is deleted leaves the void
        // permanently un-hydrated.
        try context.save()
    }

    // MARK: - Helpers

    private static func parseISO(_ s: String) -> Date? {
        ISO8601DateFormatter().date(from: s)
    }

    /// D1: validate a UUID string and throw a permanent outbox failure if
    /// it can't be parsed. Uses `OutboxBridgeError.malformedPayload` so the
    /// classifier (`OutboxDrainer.handle(error:item:)`) routes the row to
    /// `.failed` with the field name in `lastError` — visible to the user
    /// via the existing failures sheet.
    private static func requireUUID(_ value: String, field: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw OutboxBridgeError.malformedPayload(reason: "TransactionsHydrator: \(field) is not a valid UUID (\(value))")
        }
        return id
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
