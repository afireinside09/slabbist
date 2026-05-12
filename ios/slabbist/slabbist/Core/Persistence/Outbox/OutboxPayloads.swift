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

    /// Patch payload for the vendor's manual asking price on a scan. Used when
    /// Pokemon Price Tracker has no comp and the vendor records what they
    /// want to be paid for the slab. `vendor_ask_cents == nil` clears the
    /// manual price (e.g. user reverts to PPT comp). The struct name keeps
    /// its historical `UpdateScanOffer` form because the outbox kind /
    /// dispatch table refer to it; the wire field name follows the Postgres
    /// column rename to `scans.vendor_ask_cents` so the worker can patch the
    /// column directly without remapping.
    struct UpdateScanOffer: Codable {
        let id: String
        let vendor_ask_cents: Int64?
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
    ///
    /// `created_at` is carried on the wire so the on-conflict UPSERT path
    /// preserves the original insert timestamp instead of clobbering it
    /// with whatever the producer happens to stamp at retry time.
    struct UpsertVendor: Codable {
        let id: String
        let store_id: String
        let display_name: String
        let contact_method: String?
        let contact_value: String?
        let notes: String?
        let archived_at: String?
        let created_at: String
        let updated_at: String
    }

    /// Patch payload that flips a vendor's `archived_at` from NULL to the
    /// given timestamp. Pickers exclude archived vendors; existing scans /
    /// lots that already reference the row keep working.
    ///
    /// Wire shape carries only `archived_at` because the drainer dispatch
    /// reuses the same timestamp as `updated_at` server-side — the archive
    /// moment IS the update moment. Do not add a separate `updated_at`
    /// field here without updating `OutboxDrainer.dispatch`.
    struct ArchiveVendor: Codable {
        let id: String
        let archived_at: String
    }

    /// Patch payload for the new offer columns on a lot. Any field that's nil
    /// is omitted from the wire patch (don't accidentally clear server values).
    /// `updated_at` is always sent so the row's `updated_at` advances.
    struct UpdateLotOffer: Codable {
        let id: String
        let vendor_id: String?
        let vendor_name_snapshot: String?
        let margin_pct_snapshot: Double?
        let lot_offer_state: String?
        let lot_offer_state_updated_at: String?
        let updated_at: String
    }

    /// Trigger payload for `/lot-offer-recompute`. Server-side sums per-scan
    /// `buy_price_cents` and flips `lot_offer_state` as the lot crosses
    /// thresholds. Carries only `lot_id`; the Edge Function looks up the
    /// rest from the row.
    struct RecomputeLotOffer: Codable {
        let lot_id: String
    }

    /// Patch payload for per-scan buy price. `buy_price_cents == nil` clears
    /// the override (server falls back to the comp-derived value);
    /// `buy_price_overridden` is always sent so the toggle reflects intent
    /// even when reverting to the auto-computed price.
    struct UpdateScanBuyPrice: Codable {
        let id: String
        let buy_price_cents: Int64?
        let buy_price_overridden: Bool
        let updated_at: String
    }

    /// Trigger payload for `/transaction-commit`. The Edge Function snapshots
    /// the lot's scans into a `transactions` row + N `transaction_lines`,
    /// flips the lot to `paid`, and returns the inserted rows so the iOS
    /// cache can hydrate immediately without a follow-up SELECT.
    /// `vendor_id` resolves to the lot's currently-selected vendor;
    /// `vendor_name_override` lets the caller record a walk-in name without
    /// a Vendor row.
    struct CommitTransaction: Codable {
        let lot_id: String
        let payment_method: String
        let payment_reference: String?
        let vendor_id: String?
        let vendor_name_override: String?
    }

    /// Trigger payload for `/transaction-void`. The Edge Function inserts a
    /// negative-mirroring transaction row, marks the original `voided_at`,
    /// and flips the lot back to `voided` so it can be re-opened. Carries
    /// the originating transaction's UUID + a human-readable reason that
    /// shows up in the audit trail.
    struct VoidTransaction: Codable {
        let transaction_id: String
        let reason: String
    }

    /// Patch payload for the per-store margin ladder. Carries a canonical
    /// JSON-encoded `[MarginTier]` array (snake-cased keys) so the drainer
    /// can splat it directly into the `margin_ladder` JSONB column without
    /// knowing the inner shape. `stores` has no `updated_at` column today,
    /// so we deliberately omit one — add it here if/when the table grows
    /// the column.
    struct UpdateStoreMargin: Codable {
        let id: String
        let margin_ladder_json: String
    }
}

