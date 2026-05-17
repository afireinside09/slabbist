import Foundation
import OSLog
import SwiftData

/// Applies a `/lot-offer-recompute` response back onto the local `Lot` row.
///
/// Mirrors `TransactionsHydrator` in shape: runs on the MainActor against
/// `container.mainContext` so `@Query`-subscribed views (LotDetailView's
/// hero / action bar) observe the write without a follow-up render.
///
/// D2: the drainer used to discard this response — the server-derived
/// `offered_total_cents` and `lot_offer_state` never landed on the iOS
/// cache, so any server-only state change (admin override, future
/// auto-expiry) was invisible to the operator. Apply them here so the
/// local row converges with the server.
@MainActor
enum LotOfferRecomputeHydrator {
    /// Apply `response` to the local `Lot` row. Silently no-ops when the
    /// lot was deleted locally mid-dispatch (the outbox row is still
    /// drained as success — the server's recompute itself succeeded).
    /// Throws `OutboxBridgeError.malformedPayload` on a bad `lot_id`
    /// UUID so the drainer's classifier routes the outbox row to
    /// `.failed` with the field name in `lastError`.
    static func apply(
        response: LotOfferRecomputeResponse,
        container: ModelContainer
    ) throws {
        guard let lotId = UUID(uuidString: response.lot_id) else {
            throw OutboxBridgeError.malformedPayload(
                reason: "LotOfferRecomputeHydrator: lot_id is not a valid UUID (\(response.lot_id))"
            )
        }

        let context = container.mainContext
        guard let lot = try context.fetch(
            FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
        ).first else {
            // Lot was deleted locally between enqueue and dispatch. The
            // server's recompute still landed; nothing to mirror back.
            AppLog.outbox.notice("recomputeLotOffer response skipped — lot \(lotId.uuidString, privacy: .public) not found locally")
            return
        }

        // P2.4: short-circuit on a no-op response. After offline→online,
        // the recompute kick frequently returns the same numbers the local
        // cache already has. Bumping `lot.updatedAt` unconditionally fans
        // out spurious invalidations to every `@Query` sorting by
        // `updatedAt`. Diff first; save only when something changed.
        let oldTotal = lot.offeredTotalCents
        let oldState = lot.lotOfferState
        let newTotal = response.offered_total_cents
        let knownNextState = LotOfferState(rawValue: response.lot_offer_state)

        let totalChanged = oldTotal != newTotal
        let stateChanged = knownNextState.map { $0.rawValue != oldState } ?? false

        guard totalChanged || stateChanged else {
            AppLog.outbox.notice("recomputeLotOffer response matched local cache for lot \(lotId.uuidString, privacy: .public); no write")
            return
        }

        // `offered_total_cents` is always persisted — it's a pure number,
        // no enum decoding to fail. The state update is gated on knowing
        // the case so a server-side enum extension can't silently corrupt
        // the iOS state machine.
        if totalChanged {
            lot.offeredTotalCents = newTotal
        }

        if let nextState = knownNextState {
            if stateChanged {
                lot.lotOfferState = nextState.rawValue
                lot.lotOfferStateUpdatedAt = Date()
            }
        } else {
            // Server returned a state the iOS enum doesn't know — log and
            // leave the local state alone so we don't write garbage that
            // `LotOfferState(rawValue:)` falls back to `.drafting` on.
            AppLog.outbox.notice("recomputeLotOffer returned unknown lot_offer_state=\(response.lot_offer_state, privacy: .public) for lot \(lotId.uuidString, privacy: .public); offered_total_cents updated, state untouched")
        }

        lot.updatedAt = Date()

        // Explicit save — same rationale as TransactionsHydrator: a lost
        // autosave between SUT-return and runloop-tick would silently
        // discard the hydration while the outbox row is already deleted
        // (server says recompute succeeded). No replay path.
        try context.save()
    }
}
