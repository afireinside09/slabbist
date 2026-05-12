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
    var defaultMarginPct: Double = 0.7
    /// Per-store offer ladder, sorted descending by `minCompCents`. The
    /// server stores it as a JSONB array; the SDK's JSONDecoder maps it
    /// directly to `[MarginTier]`. Defaults to the canonical ladder so
    /// rows decoded from older clients (before the column existed) still
    /// produce a usable ladder.
    var marginLadder: [MarginTier] = .defaultMarginLadder

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerUserId = "owner_user_id"
        case createdAt = "created_at"
        case defaultMarginPct = "default_margin_pct"
        case marginLadder = "margin_ladder"
    }
}
