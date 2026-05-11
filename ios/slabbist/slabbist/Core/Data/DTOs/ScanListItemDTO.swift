import Foundation

/// Lightweight projection of `scans` for list views. Excludes
/// `ocr_raw_text`, `captured_photo_url`, and any other large fields
/// that don't render in a row. Use `ScanDTO` for the full row.
nonisolated struct ScanListItemDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var storeId: UUID
    var lotId: UUID
    var grader: String
    var certNumber: String
    var grade: String?
    var status: String
    var vendorAskCents: Int64?
    /// Per-scan buy price (cents). Included in the projection so the lot
    /// detail row can render the offer total without a separate full-row
    /// fetch per scan.
    var buyPriceCents: Int64?
    /// `true` when the user manually overrode the auto-derived buy price.
    /// Surfaced in the projection so list-level UI (e.g. the override badge)
    /// can render without hydrating the full scan.
    var buyPriceOverridden: Bool
    var createdAt: Date
    var updatedAt: Date

    static let columns = "id,store_id,lot_id,grader,cert_number,grade,status,vendor_ask_cents,buy_price_cents,buy_price_overridden,created_at,updated_at"

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case lotId = "lot_id"
        case grader
        case certNumber = "cert_number"
        case grade
        case status
        case vendorAskCents = "vendor_ask_cents"
        case buyPriceCents = "buy_price_cents"
        case buyPriceOverridden = "buy_price_overridden"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
