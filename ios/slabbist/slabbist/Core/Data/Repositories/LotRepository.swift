import Foundation
import Supabase

/// Reads/writes the `lots` table.
nonisolated struct LotRepository: Sendable {
    static let tableName = "lots"

    private let base: SupabaseRepository<LotDTO>

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.base = SupabaseRepository(tableName: Self.tableName, client: client)
    }

    /// All lots in a store, newest first.
    func list(storeId: UUID) async throws -> [LotDTO] {
        do {
            return try await base.query()
                .select()
                .eq("store_id", value: storeId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            throw SupabaseError.map(error)
        }
    }

    /// Lots in a store filtered by status, newest first.
    func list(storeId: UUID, status: LotStatus) async throws -> [LotDTO] {
        do {
            return try await base.query()
                .select()
                .eq("store_id", value: storeId.uuidString)
                .eq("status", value: status.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            throw SupabaseError.map(error)
        }
    }

    func find(id: UUID) async throws -> LotDTO? {
        try await base.find(id: id)
    }

    @discardableResult
    func insert(_ lot: LotDTO) async throws -> LotDTO {
        try await base.insert(lot)
    }

    @discardableResult
    func upsert(_ lot: LotDTO) async throws -> LotDTO {
        try await base.upsert(lot)
    }

    @discardableResult
    func upsertMany(_ lots: [LotDTO]) async throws -> [LotDTO] {
        try await base.upsertMany(lots)
    }

    func delete(id: UUID) async throws {
        try await base.delete(id: id)
    }
}
