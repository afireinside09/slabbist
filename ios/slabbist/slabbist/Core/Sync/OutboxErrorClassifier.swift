import Foundation

/// Maps a `SupabaseError` (and the `OutboxKind` of the in-flight item)
/// to a `Disposition` the drainer can act on. Pure function — no side
/// effects, fully unit-tested.
enum OutboxErrorClassifier {
    enum Disposition: Equatable {
        /// Transient — retry with exponential backoff, no max attempts.
        case transient
        /// Idempotent success — treat as if the operation landed.
        /// Drainer deletes the item from the local outbox.
        case success
        /// Auth expired — drainer pauses the queue and waits for session
        /// to recover (supabase-swift auto-refreshes; we re-kick on the
        /// next signed-in observation).
        case auth
        /// Permanent — drainer marks `.failed` and stops retrying.
        case permanent
    }

    static func classify(_ error: SupabaseError, for kind: OutboxKind) -> Disposition {
        switch error {
        case .unauthorized:
            return .auth
        case .uniqueViolation:
            // 23505 on insert means "row already exists" — previous attempt
            // landed and we lost the response. Idempotent success.
            // On any other kind, an unexpected uniqueness collision is
            // permanent.
            switch kind {
            case .insertLot, .insertScan: return .success
            default: return .permanent
            }
        case .notFound:
            // Deleting something that's already gone is fine. For update
            // kinds it means the row was deleted server-side; nothing we
            // can do — give up.
            switch kind {
            case .deleteLot, .deleteScan: return .success
            default: return .permanent
            }
        case .forbidden, .constraintViolation:
            return .permanent
        case .transport:
            // URLError network categories all retry. Anything else falls
            // through as transient too — the drainer caps backoff at 5
            // min, so a permanent transport-level bug just slow-spins
            // instead of corrupting state.
            return .transient
        }
    }
}
