import Foundation

/// Lightweight projection of `lots` for list views. Excludes the
/// `transaction_stamp` jsonb column and any other heavy fields that
/// don't render in a row. Typical payload is 3–5× smaller than
/// `LotDTO`, and since list scrolls are the hottest read path, this
/// is where bandwidth savings compound.
///
/// Use `LotDTO` when you need the full row (detail view, edit flow).
nonisolated struct LotListItemDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var storeId: UUID
    var name: String
    var status: String
    var vendorName: String?
    var offeredTotalCents: Int64?
    var createdAt: Date
    var updatedAt: Date

    /// Comma-separated Postgrest `SELECT` projection matching this
    /// DTO's fields. Keep in sync with `CodingKeys`.
    static let columns = "id,store_id,name,status,vendor_name,offered_total_cents,created_at,updated_at"

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case name
        case status
        case vendorName = "vendor_name"
        case offeredTotalCents = "offered_total_cents"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
