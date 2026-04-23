import Foundation

/// Wire shape for the `store_members` Postgres table. The primary key
/// is the composite `(store_id, user_id)`; this DTO is `Identifiable`
/// via that composite so it can be de-duped in collection views, but
/// CRUD for composite-key rows skips the generic `find(id:)` helper in
/// `SupabaseRepository` and uses the `query()` escape hatch instead.
nonisolated struct StoreMemberDTO: Codable, Sendable, Hashable, Identifiable {
    let storeId: UUID
    let userId: UUID
    var role: String
    var createdAt: Date

    var id: String { "\(storeId.uuidString):\(userId.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case storeId = "store_id"
        case userId = "user_id"
        case role
        case createdAt = "created_at"
    }
}
