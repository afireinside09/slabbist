import Foundation

/// Wire shape for the `stores` Postgres table.
///
/// Property names are camelCase (Swift style); `CodingKeys` map them to
/// the snake_case column names the Postgrest endpoint expects. Date
/// fields are decoded by the Supabase SDK's configured JSON decoder.
nonisolated struct StoreDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var ownerUserId: UUID
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerUserId = "owner_user_id"
        case createdAt = "created_at"
    }
}
