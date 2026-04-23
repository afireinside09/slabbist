import Foundation
import Supabase

/// Reads/writes the `scans` table. List paths use `ScanListItemDTO`
/// to skip `ocr_raw_text` / `captured_photo_url`; detail uses `ScanDTO`.
nonisolated struct SupabaseScanRepository: ScanRepository, Sendable {
    static let tableName = "scans"

    private let base: SupabaseRepository<ScanDTO>
    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
        self.base = SupabaseRepository(tableName: Self.tableName, client: client)
    }

    // MARK: - List (slim projection)

    /// All scans in a lot, oldest first so UI reconstructs capture order.
    func listItems(
        lotId: UUID,
        page: Page = .default,
        includeTotalCount: Bool = false
    ) async throws -> PagedResult<ScanListItemDTO> {
        do {
            let count: CountOption? = includeTotalCount ? .exact : nil
            let response = try await client.from(Self.tableName)
                .select(ScanListItemDTO.columns, count: count)
                .eq("lot_id", value: lotId.uuidString)
                .order("created_at", ascending: true)
                .range(from: page.range.from, to: page.range.to)
                .execute()
            let rows = try JSONCoders.decoder.decode([ScanListItemDTO].self, from: response.data)
            return PagedResult(rows: rows, totalCount: response.count, page: page)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    /// All scans in a store with a given status — supports the
    /// validation-queue UI. Backed by the partial index on
    /// `scans(lot_id) WHERE status = 'pending_validation'` when that
    /// status is requested.
    func listItems(
        storeId: UUID,
        status: ScanStatus,
        page: Page = .default,
        includeTotalCount: Bool = false
    ) async throws -> PagedResult<ScanListItemDTO> {
        do {
            let count: CountOption? = includeTotalCount ? .exact : nil
            let response = try await client.from(Self.tableName)
                .select(ScanListItemDTO.columns, count: count)
                .eq("store_id", value: storeId.uuidString)
                .eq("status", value: status.rawValue)
                .order("created_at", ascending: true)
                .range(from: page.range.from, to: page.range.to)
                .execute()
            let rows = try JSONCoders.decoder.decode([ScanListItemDTO].self, from: response.data)
            return PagedResult(rows: rows, totalCount: response.count, page: page)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    // MARK: - Count

    func countPending(storeId: UUID) async throws -> Int {
        do {
            let response = try await client.from(Self.tableName)
                .select("id", head: true, count: .exact)
                .eq("store_id", value: storeId.uuidString)
                .eq("status", value: ScanStatus.pendingValidation.rawValue)
                .execute()
            return response.count ?? 0
        } catch {
            throw SupabaseError.map(error)
        }
    }

    // MARK: - Detail (full row)

    func find(id: UUID) async throws -> ScanDTO? {
        try await base.find(id: id)
    }

    // MARK: - Writes

    func insert(_ scan: ScanDTO) async throws {
        try await base.insert(scan)
    }

    @discardableResult
    func insertAndReturn(_ scan: ScanDTO) async throws -> ScanDTO {
        try await base.insertAndReturn(scan)
    }

    func upsert(_ scan: ScanDTO) async throws {
        try await base.upsert(scan)
    }

    func upsertMany(_ scans: [ScanDTO]) async throws {
        try await base.upsertMany(scans)
    }

    func delete(id: UUID) async throws {
        try await base.delete(id: id)
    }
}
