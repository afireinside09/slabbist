import Foundation
import Supabase

/// Reads/writes the `vendors` table. RLS scopes the result set to
/// stores the caller is a member of. `listActive` excludes archived
/// rows so pickers don't surface stale vendors; the archive write is
/// expressed as a `patch` over `archived_at` to match the outbox
/// `archiveVendor` kind's wire shape.
nonisolated struct SupabaseVendorRepository: VendorRepository, Sendable {
    static let tableName = "vendors"

    private let base: SupabaseRepository<VendorDTO>
    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
        self.base = SupabaseRepository(tableName: Self.tableName, client: client)
    }

    // MARK: - Reads

    func find(id: UUID) async throws -> VendorDTO? {
        try await base.find(id: id)
    }

    /// Active (non-archived) vendors in a store, alphabetised by display
    /// name so pickers feel deterministic. Backed by the
    /// `vendors(store_id) WHERE archived_at IS NULL` partial index.
    func listActive(storeId: UUID, page: Page = .default) async throws -> [VendorDTO] {
        do {
            let response = try await client.from(Self.tableName)
                .select("*")
                .eq("store_id", value: storeId.uuidString)
                .is("archived_at", value: nil)
                .order("display_name", ascending: true)
                .range(from: page.range.from, to: page.range.to)
                .execute()
            return try JSONCoders.decoder.decode([VendorDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    // MARK: - Writes

    func upsert(_ vendor: VendorDTO) async throws {
        try await base.upsert(vendor)
    }

    func patch(id: UUID, fields: [String: AnyJSON]) async throws {
        try await base.patch(id: id, fields: fields)
    }
}
