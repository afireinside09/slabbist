import Foundation
import Supabase

/// Repository protocols — the contract view models and services depend
/// on. Concrete `Supabase*Repository` types conform; tests can swap in
/// in-memory fakes without spinning up a network stack.
///
/// Keep protocol surfaces lean: only the methods call sites actually
/// use. Implementation-specific helpers (e.g. the `query()` escape
/// hatch, `tableName` constants) stay on the concrete types so the
/// protocol isn't bound to Postgrest semantics.

nonisolated protocol StoreRepository: Sendable {
    func listForCurrentUser(page: Page) async throws -> [StoreDTO]
    func find(id: UUID) async throws -> StoreDTO?
    func listOwnedBy(userId: UUID, page: Page) async throws -> [StoreDTO]
    func upsert(_ store: StoreDTO) async throws
    @discardableResult func upsertAndReturn(_ store: StoreDTO) async throws -> StoreDTO
}

nonisolated protocol StoreMemberRepository: Sendable {
    func listMembers(storeId: UUID, page: Page) async throws -> [StoreMemberDTO]
    func listMemberships(userId: UUID, page: Page) async throws -> [StoreMemberDTO]
    func membership(storeId: UUID, userId: UUID) async throws -> StoreMemberDTO?
    func upsert(_ member: StoreMemberDTO) async throws
    func remove(storeId: UUID, userId: UUID) async throws
}

nonisolated protocol LotRepository: Sendable {
    func listItems(
        storeId: UUID,
        status: LotStatus?,
        page: Page,
        includeTotalCount: Bool
    ) async throws -> PagedResult<LotListItemDTO>

    func listItemsAfter(
        storeId: UUID,
        createdAtBefore cursor: Date,
        limit: Int
    ) async throws -> [LotListItemDTO]

    func countOpen(storeId: UUID) async throws -> Int

    func find(id: UUID) async throws -> LotDTO?

    func insert(_ lot: LotDTO) async throws
    @discardableResult func insertAndReturn(_ lot: LotDTO) async throws -> LotDTO
    func upsert(_ lot: LotDTO) async throws
    func upsertMany(_ lots: [LotDTO]) async throws
    func patch(id: UUID, fields: [String: AnyJSON]) async throws
    func delete(id: UUID) async throws

    /// Invokes the `/lot-offer-recompute` Edge Function for a lot. Returns
    /// the server-computed `{ offered_total_cents, lot_offer_state }` so
    /// the iOS cache can refresh without a second round-trip.
    func recomputeOffer(lotId: UUID) async throws -> LotOfferRecomputeResponse
}

/// Response from `/lot-offer-recompute`. The Edge Function returns the
/// freshly-summed offer total plus the (possibly-flipped) state so the
/// drainer can avoid a follow-up SELECT.
nonisolated struct LotOfferRecomputeResponse: Codable, Sendable {
    let lot_id: String
    let offered_total_cents: Int64
    let lot_offer_state: String
}

nonisolated protocol ScanRepository: Sendable {
    func listItems(
        lotId: UUID,
        page: Page,
        includeTotalCount: Bool
    ) async throws -> PagedResult<ScanListItemDTO>

    func listItems(
        storeId: UUID,
        status: ScanStatus,
        page: Page,
        includeTotalCount: Bool
    ) async throws -> PagedResult<ScanListItemDTO>

    func countPending(storeId: UUID) async throws -> Int

    func find(id: UUID) async throws -> ScanDTO?

    func insert(_ scan: ScanDTO) async throws
    @discardableResult func insertAndReturn(_ scan: ScanDTO) async throws -> ScanDTO
    func upsert(_ scan: ScanDTO) async throws
    func upsertMany(_ scans: [ScanDTO]) async throws
    func patch(id: UUID, fields: [String: AnyJSON]) async throws
    func delete(id: UUID) async throws
}

nonisolated protocol VendorRepository: Sendable {
    func find(id: UUID) async throws -> VendorDTO?
    func listActive(storeId: UUID, page: Page) async throws -> [VendorDTO]
    func upsert(_ vendor: VendorDTO) async throws
    func patch(id: UUID, fields: [String: AnyJSON]) async throws
}

nonisolated protocol GradeEstimateRepository: Sendable {
    func listForCurrentUser(page: Page, includeTotalCount: Bool) async throws -> PagedResult<GradeEstimateDTO>
    func find(id: UUID) async throws -> GradeEstimateDTO?
    func setStarred(id: UUID, starred: Bool) async throws
    func delete(id: UUID) async throws

    /// Invokes the `/grade-estimate` Edge Function and returns the persisted row.
    func requestEstimate(
        frontPath: String,
        backPath: String,
        centeringFront: CenteringRatios,
        centeringBack: CenteringRatios,
        includeOtherGraders: Bool
    ) async throws -> GradeEstimateDTO
}

/// Convenience bundle — one repository per table, sharing a single
/// `SupabaseClient`. View models take `AppRepositories` (or the
/// individual protocols) via initializer injection; tests pass a
/// bundle populated with fakes.
nonisolated struct AppRepositories: Sendable {
    var stores: any StoreRepository
    var members: any StoreMemberRepository
    var lots: any LotRepository
    var scans: any ScanRepository
    var vendors: any VendorRepository
    var gradeEstimates: any GradeEstimateRepository

    static func live(client: SupabaseClient = AppSupabase.shared.client) -> AppRepositories {
        AppRepositories(
            stores: SupabaseStoreRepository(client: client),
            members: SupabaseStoreMemberRepository(client: client),
            lots: SupabaseLotRepository(client: client),
            scans: SupabaseScanRepository(client: client),
            vendors: SupabaseVendorRepository(client: client),
            gradeEstimates: SupabaseGradeEstimateRepository(client: client)
        )
    }
}
