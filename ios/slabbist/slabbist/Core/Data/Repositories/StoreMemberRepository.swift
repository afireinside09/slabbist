import Foundation
import Supabase

/// Reads/writes the `store_members` table. Composite primary key
/// `(store_id, user_id)` means we bypass the generic `find(id:)` /
/// `delete(id:)` helpers and use `query()` to build exact filters.
nonisolated struct StoreMemberRepository: Sendable {
    static let tableName = "store_members"

    private let base: SupabaseRepository<StoreMemberDTO>

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.base = SupabaseRepository(tableName: Self.tableName, client: client)
    }

    func listMembers(storeId: UUID) async throws -> [StoreMemberDTO] {
        try await base.findWhere(column: "store_id", equals: storeId)
    }

    func listMemberships(userId: UUID) async throws -> [StoreMemberDTO] {
        try await base.findWhere(column: "user_id", equals: userId)
    }

    func membership(storeId: UUID, userId: UUID) async throws -> StoreMemberDTO? {
        do {
            let rows: [StoreMemberDTO] = try await base.query()
                .select()
                .eq("store_id", value: storeId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            throw SupabaseError.map(error)
        }
    }

    @discardableResult
    func upsert(_ member: StoreMemberDTO) async throws -> StoreMemberDTO {
        try await base.upsert(member, onConflict: "store_id,user_id")
    }

    func remove(storeId: UUID, userId: UUID) async throws {
        do {
            _ = try await base.query()
                .delete()
                .eq("store_id", value: storeId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
        } catch {
            throw SupabaseError.map(error)
        }
    }
}
