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
}
