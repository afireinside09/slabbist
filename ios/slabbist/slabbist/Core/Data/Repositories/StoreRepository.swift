import Foundation
import Supabase

/// Reads/writes the `stores` table. RLS restricts the result set to
/// rows where the caller is a member; an unauthenticated session
/// simply returns an empty list.
nonisolated struct StoreRepository: Sendable {
    static let tableName = "stores"

    private let base: SupabaseRepository<StoreDTO>

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.base = SupabaseRepository(tableName: Self.tableName, client: client)
    }

    /// All stores the caller can see (by RLS: stores they are a member
    /// of), newest first.
    func listForCurrentUser() async throws -> [StoreDTO] {
        try await base.findAll(orderBy: "created_at", ascending: false)
    }

    func find(id: UUID) async throws -> StoreDTO? {
        try await base.find(id: id)
    }

    /// Stores the given user owns (independent of membership RLS —
    /// primarily for admin / debugging flows).
    func listOwnedBy(userId: UUID) async throws -> [StoreDTO] {
        try await base.findWhere(column: "owner_user_id", equals: userId)
    }

    @discardableResult
    func upsert(_ store: StoreDTO) async throws -> StoreDTO {
        try await base.upsert(store)
    }
}
