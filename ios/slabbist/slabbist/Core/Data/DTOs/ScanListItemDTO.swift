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
    var offerCents: Int64?
    var createdAt: Date
    var updatedAt: Date

    static let columns = "id,store_id,lot_id,grader,cert_number,grade,status,offer_cents,created_at,updated_at"

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case lotId = "lot_id"
        case grader
        case certNumber = "cert_number"
        case grade
        case status
        case offerCents = "offer_cents"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
