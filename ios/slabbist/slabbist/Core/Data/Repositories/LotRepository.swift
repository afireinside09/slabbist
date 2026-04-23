import Foundation
import Supabase

/// Reads/writes the `lots` table. The list paths use the slim
/// `LotListItemDTO` projection to skip heavy fields (`transaction_stamp`
/// jsonb); detail paths use the full `LotDTO`.
nonisolated struct SupabaseLotRepository: LotRepository, Sendable {
    static let tableName = "lots"

    private let base: SupabaseRepository<LotDTO>
    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
        self.base = SupabaseRepository(tableName: Self.tableName, client: client)
    }

    // MARK: - List (slim projection)

    /// Paged list of lots in a store, newest first. Slim projection.
    /// If `status` is provided, the partial index on
    /// `(store_id, created_at desc) WHERE status = 'open'` applies —
    /// check `db/migrations` for the current supporting indexes.
    func listItems(
        storeId: UUID,
        status: LotStatus? = nil,
        page: Page = .default,
        includeTotalCount: Bool = false
    ) async throws -> PagedResult<LotListItemDTO> {
        do {
            let count: CountOption? = includeTotalCount ? .exact : nil
            var filter = client.from(Self.tableName)
                .select(LotListItemDTO.columns, count: count)
                .eq("store_id", value: storeId.uuidString)
            if let status {
                filter = filter.eq("status", value: status.rawValue)
            }
            let response = try await filter
                .order("created_at", ascending: false)
                .range(from: page.range.from, to: page.range.to)
                .execute()
            let rows = try JSONCoders.decoder.decode([LotListItemDTO].self, from: response.data)
            return PagedResult(rows: rows, totalCount: response.count, page: page)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    /// Keyset pagination for very large stores — pass the `createdAt`
    /// of the last row from the previous page. O(log n) regardless of
    /// depth.
    func listItemsAfter(
        storeId: UUID,
        createdAtBefore cursor: Date,
        limit: Int = 50
    ) async throws -> [LotListItemDTO] {
        do {
            let iso = ISO8601DateFormatter().string(from: cursor)
            let response = try await client.from(Self.tableName)
                .select(LotListItemDTO.columns)
                .eq("store_id", value: storeId.uuidString)
                .lt("created_at", value: iso)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
            return try JSONCoders.decoder.decode([LotListItemDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    // MARK: - Count

    func countOpen(storeId: UUID) async throws -> Int {
        do {
            let response = try await client.from(Self.tableName)
                .select("id", head: true, count: .exact)
                .eq("store_id", value: storeId.uuidString)
                .eq("status", value: LotStatus.open.rawValue)
                .execute()
            return response.count ?? 0
        } catch {
            throw SupabaseError.map(error)
        }
    }

    // MARK: - Detail (full row)

    func find(id: UUID) async throws -> LotDTO? {
        try await base.find(id: id)
    }

    // MARK: - Writes

    func insert(_ lot: LotDTO) async throws {
        try await base.insert(lot)
    }

    @discardableResult
    func insertAndReturn(_ lot: LotDTO) async throws -> LotDTO {
        try await base.insertAndReturn(lot)
    }

    func upsert(_ lot: LotDTO) async throws {
        try await base.upsert(lot)
    }

    func upsertMany(_ lots: [LotDTO]) async throws {
        try await base.upsertMany(lots)
    }

    func delete(id: UUID) async throws {
        try await base.delete(id: id)
    }
}
