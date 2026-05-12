import Foundation
import Supabase

/// Reads/writes the `stores` table. RLS restricts the result set to
/// rows where the caller is a member; an unauthenticated session
/// simply returns an empty list.
nonisolated struct SupabaseStoreRepository: StoreRepository, Sendable {
    static let tableName = "stores"

    private let base: SupabaseRepository<StoreDTO>

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.base = SupabaseRepository(tableName: Self.tableName, client: client)
    }

    /// All stores the caller can see (by RLS: stores they are a member
    /// of), newest first. Bounded by `page` — `Page.default` is 50.
    func listForCurrentUser(page: Page) async throws -> [StoreDTO] {
        try await base.findAll(page: page, orderBy: "created_at", ascending: false)
    }

    func find(id: UUID) async throws -> StoreDTO? {
        try await base.find(id: id)
    }

    /// Stores the given user owns (independent of membership RLS —
    /// primarily for admin / debugging flows).
    func listOwnedBy(userId: UUID, page: Page) async throws -> [StoreDTO] {
        try await base.findWhere(column: "owner_user_id", equals: userId, page: page)
    }

    @discardableResult
    func upsertAndReturn(_ store: StoreDTO) async throws -> StoreDTO {
        try await base.upsertAndReturn(store)
    }

    func upsert(_ store: StoreDTO) async throws {
        try await base.upsert(store)
    }

    func patch(id: UUID, fields: [String: AnyJSON]) async throws {
        try await base.patch(id: id, fields: fields)
    }

    func createMyStore(name: String) async throws -> UUID {
        do {
            let response = try await base.client.rpc(
                "create_my_store",
                params: CreateMyStoreParams(p_name: name)
            ).execute()
            let raw = try JSONCoders.decoder.decode(UUID.self, from: response.data)
            return raw
        } catch {
            throw SupabaseError.map(error)
        }
    }

    private struct CreateMyStoreParams: Encodable, Sendable {
        let p_name: String
    }
}
