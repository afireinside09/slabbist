import Foundation

/// Wire-shape payloads for outbox jobs. Keep these flat and snake_case to
/// match Postgres column names so the outbox worker (Plan 2) can POST them
/// directly without re-mapping. `nil` optional fields serialize to JSON
/// null; do not serialize them as empty strings or zeros.
nonisolated enum OutboxPayloads {}

nonisolated extension OutboxPayloads {
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

    /// Patch payload for the user-entered manual price on a scan. Used when
    /// Pokemon Price Tracker has no comp and the vendor records what they
    /// want to ask for the slab. `offer_cents == nil` clears the manual
    /// price (e.g. user reverts to PPT comp). The dedicated payload keeps
    /// the cert-lookup `UpdateScan` shape unambiguous for the future
    /// outbox worker — null on this struct unambiguously means "clear".
    struct UpdateScanOffer: Codable {
        let id: String
        let offer_cents: Int64?
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

    /// Patch payload for an existing lot. Only the fields that change are
    /// populated; everything else stays untouched on the server. No producer
    /// emits this in v1 — added so the outbox drainer's dispatch table is
    /// exhaustive without a `default:` branch hiding future bugs.
    struct UpdateLot: Codable {
        let id: String
        let name: String?
        let notes: String?
        let status: String?
        let updated_at: String
    }

    /// Full upsert payload for a vendor row. Used both on create and edit —
    /// the outbox worker UPSERTs against the `id` primary key. `archived_at`
    /// is `nil` for active vendors; the dedicated `ArchiveVendor` payload
    /// flips it without rewriting the rest of the row.
    struct UpsertVendor: Codable {
        let id: String
        let store_id: String
        let display_name: String
        let contact_method: String?
        let contact_value: String?
        let notes: String?
        let archived_at: String?
        let updated_at: String
    }

    /// Patch payload that flips a vendor's `archived_at` from NULL to the
    /// given timestamp. Pickers exclude archived vendors; existing scans /
    /// lots that already reference the row keep working.
    struct ArchiveVendor: Codable {
        let id: String
        let archived_at: String
    }
}
