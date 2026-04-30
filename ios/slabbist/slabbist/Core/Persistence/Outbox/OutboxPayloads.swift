import Foundation

/// Wire-shape payloads for outbox jobs. Keep these flat and snake_case to
/// match Postgres column names so the outbox worker (Plan 2) can POST them
/// directly without re-mapping. `nil` optional fields serialize to JSON
/// null; do not serialize them as empty strings or zeros.
enum OutboxPayloads {}

extension OutboxPayloads {
    struct InsertLot: Codable {
        let id: String
        let store_id: String
        let created_by_user_id: String
        let name: String
        let notes: String?
        let status: String
        let created_at: String
        let updated_at: String
    }

    struct InsertScan: Codable {
        let id: String
        let store_id: String
        let lot_id: String
        let user_id: String
        let grader: String
        let cert_number: String
        let status: String
        let ocr_raw_text: String?
        let ocr_confidence: Double?
        let created_at: String
        let updated_at: String
    }

    struct PriceCompJob: Codable {
        let graded_card_identity_id: String
        let grading_service: String
        let grade: String
    }

    /// Patch payload for an existing scan. Sent after `/cert-lookup` resolves
    /// a `(grader, cert_number)` to a graded card identity + grade. Only the
    /// fields that change are populated; everything else stays untouched on
    /// the server.
    struct UpdateScan: Codable {
        let id: String
        let graded_card_identity_id: String?
        let grade: String?
        let status: String
        let updated_at: String
    }

    /// User-initiated delete of a single slab. The outbox worker DELETEs the
    /// row from `scans` (RLS scopes it to the user's store).
    struct DeleteScan: Codable {
        let id: String
        let deleted_at: String
    }

    /// User-initiated delete of an entire lot. Server-side the `scans` rows
    /// are removed by an accompanying batch of `DeleteScan` items enqueued
    /// alongside this; we do not rely on a server-side cascade because the
    /// `scans.lot_id` foreign key was set up with `on delete set null` to
    /// avoid silent batch-loss from accidental lot deletes.
    struct DeleteLot: Codable {
        let id: String
        let deleted_at: String
    }
}
