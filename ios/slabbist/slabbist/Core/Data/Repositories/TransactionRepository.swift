import Foundation
import Supabase

/// Invokes the `/transaction-commit` + `/transaction-void` Edge Functions.
/// There is no plain CRUD surface on `transactions` — the table is
/// append-only and only the Edge Functions hold the snapshot + lot-state
/// invariants. Reads happen through `TransactionsRepository` (Plan 3 /
/// Task 10) once it lands.
///
/// Errors flow through `SupabaseError.map` so the outbox classifier can
/// route transport failures to the transient-retry path while the
/// permission / RLS failures land on `.failed`.
nonisolated struct SupabaseTransactionRepository: TransactionRepository, Sendable {
    static let commitFunctionName = "transaction-commit"
    static let voidFunctionName = "transaction-void"

    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
    }

    func commit(payload: TransactionCommitPayload) async throws -> TransactionCommitResponse {
        do {
            let response: TransactionCommitResponse = try await client.functions
                .invoke(Self.commitFunctionName, options: FunctionInvokeOptions(body: payload))
            return response
        } catch {
            throw SupabaseError.map(error)
        }
    }

    func void(transactionId: UUID, reason: String) async throws -> TransactionVoidResponse {
        struct Body: Encodable {
            let transaction_id: String
            let reason: String
        }
        let body = Body(transaction_id: transactionId.uuidString, reason: reason)
        do {
            let response: TransactionVoidResponse = try await client.functions
                .invoke(Self.voidFunctionName, options: FunctionInvokeOptions(body: body))
            return response
        } catch {
            throw SupabaseError.map(error)
        }
    }
}
