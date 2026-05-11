import Foundation

/// Wire shape for the `scans` Postgres table.
nonisolated struct ScanDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var storeId: UUID
    var lotId: UUID
    var userId: UUID
    var grader: String
    var certNumber: String
    var grade: String?
    var status: String
    var ocrRawText: String?
    var ocrConfidence: Double?
    var capturedPhotoURL: String?
    var vendorAskCents: Int64?
    /// Per-scan buy price (cents) — the store-side counterpart to
    /// `vendorAskCents`. Set by `OfferRepository` (auto-derived or override).
    /// Nullable on the wire because a fresh scan has no buy price yet.
    var buyPriceCents: Int64?
    /// `true` when the user manually overrode the auto-derived `buyPriceCents`.
    /// Persisted so a refetch on a fresh device knows whether to recompute
    /// the value or keep the operator's manual entry.
    var buyPriceOverridden: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case lotId = "lot_id"
        case userId = "user_id"
        case grader
        case certNumber = "cert_number"
        case grade
        case status
        case ocrRawText = "ocr_raw_text"
        case ocrConfidence = "ocr_confidence"
        case capturedPhotoURL = "captured_photo_url"
        case vendorAskCents = "vendor_ask_cents"
        case buyPriceCents = "buy_price_cents"
        case buyPriceOverridden = "buy_price_overridden"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
