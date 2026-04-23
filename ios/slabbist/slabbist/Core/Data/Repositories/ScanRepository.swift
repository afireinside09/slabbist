import Foundation
import Supabase

/// Reads/writes the `scans` table.
nonisolated struct ScanRepository: Sendable {
    static let tableName = "scans"

    private let base: SupabaseRepository<ScanDTO>

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.base = SupabaseRepository(tableName: Self.tableName, client: client)
    }

    /// All scans in a lot, oldest first so UI reconstructs capture order.
    func list(lotId: UUID) async throws -> [ScanDTO] {
        do {
            return try await base.query()
                .select()
                .eq("lot_id", value: lotId.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            throw SupabaseError.map(error)
        }
    }

    /// All scans in a store with a given status (useful for validation
    /// queues).
    func list(storeId: UUID, status: ScanStatus) async throws -> [ScanDTO] {
        do {
            return try await base.query()
                .select()
                .eq("store_id", value: storeId.uuidString)
                .eq("status", value: status.rawValue)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            throw SupabaseError.map(error)
        }
    }

    func find(id: UUID) async throws -> ScanDTO? {
        try await base.find(id: id)
    }

    @discardableResult
    func insert(_ scan: ScanDTO) async throws -> ScanDTO {
        try await base.insert(scan)
    }

    @discardableResult
    func upsert(_ scan: ScanDTO) async throws -> ScanDTO {
        try await base.upsert(scan)
    }

    @discardableResult
    func upsertMany(_ scans: [ScanDTO]) async throws -> [ScanDTO] {
        try await base.upsertMany(scans)
    }

    func delete(id: UUID) async throws {
        try await base.delete(id: id)
    }
}
