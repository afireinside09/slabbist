import Foundation
import SwiftData
import Supabase
import Testing
@testable import slabbist

/// D1: cover the regressions the hydrator hardening fixes.
///
/// 1. **mainContext is the receiver** — the hydrator must commit through
///    `container.mainContext`, not a fresh `ModelContext(container)`, so
///    `@Query`-subscribed views observe the change without a re-render.
///    A naive read-back can't distinguish the two (the store is shared);
///    `commitFlushesPreExistingMainContextDirtyState` is the real
///    discriminator — it pre-dirties mainContext, then asserts the SUT
///    cleaned it (which only happens if the SUT called
///    `mainContext.save()`).
/// 2. **Explicit save** — P0.2 closes the autosave-race window where a
///    process kill between SUT-return and runloop-tick would silently
///    discard the hydration. The test asserts `mainContext.hasChanges`
///    is false immediately after the call.
/// 3. **UUID validation throws** — malformed UUIDs become
///    `OutboxBridgeError.malformedPayload` so the drainer routes the row
///    to `.failed` (visible via Cluster A's failures sheet) instead of
///    silently inserting rows pointing at fake UUIDs.
/// 4. **All-or-nothing on line errors (P1.3)** — a malformed line UUID
///    can't leave a partially-hydrated transaction. The all-validation
///    pass happens before any `context.insert`.
@MainActor
struct TransactionsHydratorTests {
    // MARK: - mainContext semantics

    /// Real discriminator for "hydrator uses mainContext, not a fresh
    /// context". Pre-dirty mainContext with a sentinel change BEFORE
    /// running the SUT. If the SUT calls `mainContext.save()` (the fix),
    /// the sentinel is flushed and `hasChanges` ends as false. If the SUT
    /// builds a `ModelContext(container)` and saves THAT instead (the bug
    /// shape), our sentinel is untouched and `mainContext.hasChanges`
    /// stays true.
    ///
    /// This test would PASS today's mainContext code and FAIL the
    /// pre-D1 `let context = ModelContext(container)` shape — exactly the
    /// regression coverage P0.1 demanded.
    @Test func commitFlushesPreExistingMainContextDirtyState() async throws {
        let container = AppModelContainer.inMemory()
        let main = container.mainContext

        // Sentinel: a Store row we insert directly into mainContext, leaving
        // it dirty. The SUT's `mainContext.save()` is the only path that
        // can flush this — a fresh-context-based hydrator can't see it.
        let sentinel = Store(
            id: UUID(),
            name: "Sentinel",
            ownerUserId: UUID(),
            createdAt: Date()
        )
        main.insert(sentinel)
        #expect(main.hasChanges, "precondition: sentinel must leave mainContext dirty")

        let response = makeCommitResponse(
            txnId: UUID(), storeId: UUID(), lotId: UUID(), paidByUserId: UUID()
        )
        try await TransactionsHydrator.upsert(commitResponse: response, container: container)

        // If the SUT committed via mainContext (the fix), the sentinel got
        // flushed alongside the hydrator's own writes — hasChanges is now
        // false. If the SUT used a fresh ModelContext, hasChanges is still
        // true because nothing touched mainContext's pending changes.
        #expect(!main.hasChanges, "SUT must commit via mainContext.save() — sentinel should be flushed")
    }

    /// P0.2: closes the autosave race. After the SUT returns, mainContext
    /// must NOT have any pending changes — otherwise a process kill in
    /// the runloop-tick gap silently discards the hydration while the
    /// outbox row is already deleted (server says committed).
    @Test func commitSavesExplicitlyNoPendingChanges() async throws {
        let container = AppModelContainer.inMemory()
        let response = makeCommitResponse(
            txnId: UUID(), storeId: UUID(), lotId: UUID(), paidByUserId: UUID()
        )
        try await TransactionsHydrator.upsert(commitResponse: response, container: container)
        #expect(!container.mainContext.hasChanges, "mainContext must be saved before the hydrator returns")
    }

    /// Symmetric P0.2 assertion for the void path.
    @Test func voidSavesExplicitlyNoPendingChanges() async throws {
        let container = AppModelContainer.inMemory()
        let response = TransactionVoidResponse(
            void_transaction: .init(
                id: UUID().uuidString,
                store_id: UUID().uuidString,
                lot_id: UUID().uuidString,
                vendor_id: nil,
                vendor_name_snapshot: "v",
                total_buy_cents: 100,
                payment_method: "cash",
                payment_reference: nil,
                paid_at: ISO8601DateFormatter().string(from: Date()),
                paid_by_user_id: UUID().uuidString,
                voided_at: ISO8601DateFormatter().string(from: Date()),
                voided_by_user_id: UUID().uuidString,
                void_reason: "test",
                void_of_transaction_id: UUID().uuidString
            ),
            original_id: UUID().uuidString
        )
        try await TransactionsHydrator.upsert(voidResponse: response, container: container)
        #expect(!container.mainContext.hasChanges, "void path must save before returning")
    }

    // MARK: - UUID validation

    /// The bug shape: server returns a malformed `store_id`. Before D1,
    /// the hydrator silently substituted `UUID()` and inserted a
    /// StoreTransaction pointing at a fake store — invisible to the user.
    /// After D1, the hydrator throws and inserts NOTHING.
    @Test func malformedStoreIdThrowsAndInsertsNothing() async throws {
        let container = AppModelContainer.inMemory()
        var response = makeCommitResponse(
            txnId: UUID(), storeId: UUID(), lotId: UUID(), paidByUserId: UUID()
        )
        response = TransactionCommitResponse(
            transaction: .init(
                id: response.transaction.id,
                store_id: "not-a-uuid",
                lot_id: response.transaction.lot_id,
                vendor_id: nil,
                vendor_name_snapshot: response.transaction.vendor_name_snapshot,
                total_buy_cents: response.transaction.total_buy_cents,
                payment_method: response.transaction.payment_method,
                payment_reference: nil,
                paid_at: response.transaction.paid_at,
                paid_by_user_id: response.transaction.paid_by_user_id,
                voided_at: nil, voided_by_user_id: nil,
                void_reason: nil, void_of_transaction_id: nil
            ),
            lines: [], deduped: nil
        )

        do {
            try await TransactionsHydrator.upsert(commitResponse: response, container: container)
            Issue.record("hydrator must throw on a malformed UUID")
        } catch let error as OutboxBridgeError {
            switch error {
            case .malformedPayload(let reason):
                #expect(reason.contains("store_id"))
            }
        }

        let main = container.mainContext
        let all = try main.fetch(FetchDescriptor<StoreTransaction>())
        #expect(all.isEmpty)
    }

    /// Same shape but for `paid_by_user_id`.
    @Test func malformedPaidByUserIdThrowsAndInsertsNothing() async throws {
        let container = AppModelContainer.inMemory()
        let base = makeCommitResponse(
            txnId: UUID(), storeId: UUID(), lotId: UUID(), paidByUserId: UUID()
        )
        let response = TransactionCommitResponse(
            transaction: .init(
                id: base.transaction.id,
                store_id: base.transaction.store_id,
                lot_id: base.transaction.lot_id,
                vendor_id: nil,
                vendor_name_snapshot: base.transaction.vendor_name_snapshot,
                total_buy_cents: base.transaction.total_buy_cents,
                payment_method: base.transaction.payment_method,
                payment_reference: nil,
                paid_at: base.transaction.paid_at,
                paid_by_user_id: "garbage",
                voided_at: nil, voided_by_user_id: nil,
                void_reason: nil, void_of_transaction_id: nil
            ),
            lines: [], deduped: nil
        )

        do {
            try await TransactionsHydrator.upsert(commitResponse: response, container: container)
            Issue.record("hydrator must throw on a malformed paid_by_user_id")
        } catch let error as OutboxBridgeError {
            switch error {
            case .malformedPayload(let reason):
                #expect(reason.contains("paid_by_user_id"))
            }
        }

        let main = container.mainContext
        let all = try main.fetch(FetchDescriptor<StoreTransaction>())
        #expect(all.isEmpty)
    }

    /// Void path: malformed `original_id`. After P1.3 this is validated
    /// up front so nothing in the void path mutates the context.
    @Test func voidMalformedOriginalIdThrowsAndInsertsNothing() async throws {
        let container = AppModelContainer.inMemory()
        let response = TransactionVoidResponse(
            void_transaction: .init(
                id: UUID().uuidString,
                store_id: UUID().uuidString,
                lot_id: UUID().uuidString,
                vendor_id: nil,
                vendor_name_snapshot: "v",
                total_buy_cents: 100,
                payment_method: "cash",
                payment_reference: nil,
                paid_at: ISO8601DateFormatter().string(from: Date()),
                paid_by_user_id: UUID().uuidString,
                voided_at: ISO8601DateFormatter().string(from: Date()),
                voided_by_user_id: UUID().uuidString,
                void_reason: "test",
                void_of_transaction_id: UUID().uuidString
            ),
            original_id: "definitely-not-a-uuid"
        )

        do {
            try await TransactionsHydrator.upsert(voidResponse: response, container: container)
            Issue.record("hydrator must throw on a malformed original_id")
        } catch let error as OutboxBridgeError {
            switch error {
            case .malformedPayload(let reason):
                #expect(reason.contains("original_id"))
            }
        }

        // P1.3: void path is all-or-nothing too. A bad original_id must
        // not leave a half-inserted void row.
        let main = container.mainContext
        let all = try main.fetch(FetchDescriptor<StoreTransaction>())
        #expect(all.isEmpty, "void path must validate ALL UUIDs before inserting anything")
    }

    // MARK: - P1.3 all-or-nothing on line errors

    /// A malformed line UUID partway through a commit response must NOT
    /// leave the transaction row inserted with only some of its lines.
    /// After P1.3 we validate every line UUID up front before any
    /// `context.insert`, so a bad line aborts the whole hydration.
    /// Without this guard the user would see a lot stuck with a phantom
    /// transaction row and no line rows, and retry would hit the server
    /// 409 path (drained as success) — silently un-recoverable.
    @Test func malformedLineUUIDLeavesNoPartialHydration() async throws {
        let container = AppModelContainer.inMemory()
        let txnId = UUID()
        let scanId = UUID()
        let validLineTxnId = txnId.uuidString
        // First line is well-formed, second has a bad scan_id — the bug
        // shape is "we already inserted the txn + line[0] when line[1]
        // throws". P1.3 makes this all-or-nothing.
        let response = TransactionCommitResponse(
            transaction: .init(
                id: txnId.uuidString,
                store_id: UUID().uuidString,
                lot_id: UUID().uuidString,
                vendor_id: nil,
                vendor_name_snapshot: "v",
                total_buy_cents: 200,
                payment_method: "cash",
                payment_reference: nil,
                paid_at: ISO8601DateFormatter().string(from: Date()),
                paid_by_user_id: UUID().uuidString,
                voided_at: nil, voided_by_user_id: nil,
                void_reason: nil, void_of_transaction_id: nil
            ),
            lines: [
                .init(transaction_id: validLineTxnId, scan_id: scanId.uuidString,
                      line_index: 0, buy_price_cents: 100, identity_snapshot: nil),
                .init(transaction_id: validLineTxnId, scan_id: "bad-scan-id",
                      line_index: 1, buy_price_cents: 100, identity_snapshot: nil)
            ],
            deduped: nil
        )

        do {
            try await TransactionsHydrator.upsert(commitResponse: response, container: container)
            Issue.record("hydrator must throw on a malformed line UUID")
        } catch let error as OutboxBridgeError {
            switch error {
            case .malformedPayload(let reason):
                #expect(reason.contains("scan_id"))
            }
        }

        // The load-bearing assertion: zero rows of either model survived.
        // Without P1.3, the StoreTransaction + first TransactionLine would
        // be inserted into mainContext and (under autosave) leak to disk.
        let main = container.mainContext
        let txns = try main.fetch(FetchDescriptor<StoreTransaction>())
        let lines = try main.fetch(FetchDescriptor<TransactionLine>())
        #expect(txns.isEmpty, "no transaction row may survive a partial hydration failure")
        #expect(lines.isEmpty, "no line row may survive a partial hydration failure")
    }

    // MARK: - Helpers

    private func makeCommitResponse(
        txnId: UUID, storeId: UUID, lotId: UUID, paidByUserId: UUID
    ) -> TransactionCommitResponse {
        TransactionCommitResponse(
            transaction: .init(
                id: txnId.uuidString,
                store_id: storeId.uuidString,
                lot_id: lotId.uuidString,
                vendor_id: nil,
                vendor_name_snapshot: "Test Vendor",
                total_buy_cents: 12_345,
                payment_method: "cash",
                payment_reference: nil,
                paid_at: ISO8601DateFormatter().string(from: Date()),
                paid_by_user_id: paidByUserId.uuidString,
                voided_at: nil, voided_by_user_id: nil,
                void_reason: nil, void_of_transaction_id: nil
            ),
            lines: [], deduped: nil
        )
    }
}
