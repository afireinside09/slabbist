import Foundation
import SwiftData

/// View-model-facing facade for the lot-offer workflow. Owns three jobs:
///
///   1. Snapshot the store's default margin onto a lot the first time it's
///      priced, so re-opening the lot reproduces the same numbers even if the
///      store's default has drifted since.
///   2. Auto-derive (and revert / override) per-scan buy prices via
///      `OfferPricingService`, keeping local SwiftData and the outbox patch
///      in lock-step.
///   3. Drive the `LotOfferState` state machine — `drafting → priced →
///      presented → accepted → paid` with `declined`/`voided` branches —
///      rejecting illegal transitions at the boundary instead of pushing a
///      bad payload to the outbox.
///
/// Mirrors `VendorsRepository` in shape: every mutation writes SwiftData,
/// enqueues an `OutboxItem`, calls `context.save()`, then `kicker.kick()`s
/// the drainer.
@MainActor
final class OfferRepository {
    private let context: ModelContext
    private let kicker: OutboxKicker
    let currentStoreId: UUID
    let currentUserId: UUID

    init(context: ModelContext, kicker: OutboxKicker, currentStoreId: UUID, currentUserId: UUID) {
        self.context = context
        self.kicker = kicker
        self.currentStoreId = currentStoreId
        self.currentUserId = currentUserId
    }

    // MARK: - State machine

    /// Surfaced so callers can show a meaningful error when they try to
    /// e.g. accept an offer that was never presented. Carrying both ends
    /// of the bad transition makes the message specific without forcing
    /// the call site to read `lot.lotOfferState` again itself.
    enum InvalidTransition: Error { case notAllowed(from: LotOfferState, to: LotOfferState) }

    /// Whitelist of legal `LotOfferState` transitions. Idempotent
    /// self-transitions (`from == to`) are also allowed so callers can
    /// blindly re-affirm a state without special-casing it. Anything
    /// outside the table throws on apply.
    static func canTransition(from: LotOfferState, to: LotOfferState) -> Bool {
        if from == to { return true }
        switch (from, to) {
        case (.drafting, .priced),
             (.priced, .presented),
             (.presented, .priced),
             (.presented, .declined),
             (.presented, .accepted),
             (.accepted, .presented),
             (.accepted, .declined),
             (.accepted, .paid),
             (.paid, .voided),
             (.declined, .priced):
            return true
        default:
            return false
        }
    }

    private func transition(_ lot: Lot, to next: LotOfferState) throws {
        let current = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
        guard Self.canTransition(from: current, to: next) else {
            throw InvalidTransition.notAllowed(from: current, to: next)
        }
        lot.lotOfferState = next.rawValue
        lot.lotOfferStateUpdatedAt = Date()
        lot.updatedAt = Date()
        enqueueLotPatch(lot)
    }

    // MARK: - Public API

    /// Snapshot the store's default margin onto a freshly-created lot. No-op
    /// if a snapshot already exists — once a lot has been priced, its margin
    /// is fixed (the user can still change it via `setLotMargin`, but the
    /// store-default never silently re-overrides their choice).
    func snapshotDefaultMargin(into lot: Lot, store: Store) throws {
        guard lot.marginPctSnapshot == nil else { return }
        lot.marginPctSnapshot = store.defaultMarginPct
        lot.updatedAt = Date()
        enqueueLotPatch(lot)
        try context.save()
        kicker.kick()
    }

    /// Set a per-scan buy price, marking it overridden. Pass `nil` for
    /// `cents` (with `overridden = false`) to revert to the auto-derived
    /// value next time the comp lands or the lot margin changes.
    func setBuyPrice(_ cents: Int64?, scan: Scan, overridden: Bool) throws {
        scan.buyPriceCents = cents
        scan.buyPriceOverridden = overridden
        scan.updatedAt = Date()
        enqueueScanBuyPricePatch(scan)
        try recompute(lot: scan.lotId)
        try context.save()
        kicker.kick()
    }

    /// Compute and apply the auto-derived buy price for a scan whose comp
    /// just landed. Skips overridden scans (their value sticks until the
    /// user explicitly clears the override). Returns the computed value
    /// (or `nil` if either input is missing).
    @discardableResult
    func applyAutoBuyPrice(scan: Scan, lot: Lot) throws -> Int64? {
        guard !scan.buyPriceOverridden else { return scan.buyPriceCents }
        let auto = OfferPricingService.defaultBuyPrice(
            reconciledCents: scan.reconciledHeadlinePriceCents,
            marginPct: lot.marginPctSnapshot
        )
        scan.buyPriceCents = auto
        scan.updatedAt = Date()
        enqueueScanBuyPricePatch(scan)
        try recompute(lot: lot.id)
        return auto
    }

    /// Update the lot's margin (e.g. from a slider in OfferReviewView) and
    /// re-derive buy prices for every non-overridden scan in the lot. One
    /// `context.save()` + `kicker.kick()` at the end so the outbox sees the
    /// whole batch as a unit.
    func setLotMargin(_ pct: Double, on lot: Lot) throws {
        lot.marginPctSnapshot = pct
        lot.updatedAt = Date()
        enqueueLotPatch(lot)

        let lotId = lot.id
        let descriptor = FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        let scans = try context.fetch(descriptor)
        for scan in scans where !scan.buyPriceOverridden {
            let auto = OfferPricingService.defaultBuyPrice(
                reconciledCents: scan.reconciledHeadlinePriceCents,
                marginPct: pct
            )
            scan.buyPriceCents = auto
            scan.updatedAt = Date()
            enqueueScanBuyPricePatch(scan)
        }
        try recompute(lot: lot.id)
        try context.save()
        kicker.kick()
    }

    /// Attach a vendor (or detach when `vendor == nil`). Snapshots the
    /// display name onto the lot so a later rename of the vendor doesn't
    /// retroactively change this lot's offer header.
    func attachVendor(_ vendor: Vendor?, to lot: Lot) throws {
        lot.vendorId = vendor?.id
        lot.vendorNameSnapshot = vendor?.displayName
        lot.updatedAt = Date()
        enqueueLotPatch(lot)
        try context.save()
        kicker.kick()
    }

    /// Move a priced lot into the `presented` state — the moment the
    /// vendor sees the number.
    func sendToOffer(_ lot: Lot) throws {
        try transition(lot, to: .presented)
        try context.save()
        kicker.kick()
    }

    /// Roll a presented lot back to `priced` so the store can edit numbers
    /// before re-presenting.
    func bounceBack(_ lot: Lot) throws {
        try transition(lot, to: .priced)
        try context.save()
        kicker.kick()
    }

    /// Vendor walks away — the lot stays in the system for history but
    /// won't accrue further actions until reopened.
    func decline(_ lot: Lot) throws {
        try transition(lot, to: .declined)
        try context.save()
        kicker.kick()
    }

    /// Vendor agrees to the presented offer. Doesn't pay them yet — that's
    /// a separate `.accepted → .paid` step driven by the cash-out flow.
    func recordAcceptance(_ lot: Lot) throws {
        try transition(lot, to: .accepted)
        try context.save()
        kicker.kick()
    }

    /// Allow a declined lot back into the pricing flow. Lands on `.priced`
    /// rather than `.drafting` because the math is still on the lot — the
    /// vendor just changed their mind.
    func reopenDeclined(_ lot: Lot) throws {
        try transition(lot, to: .priced)
        try context.save()
        kicker.kick()
    }

    // MARK: - Outbox plumbing

    private func enqueueLotPatch(_ lot: Lot) {
        let payload = OutboxPayloads.UpdateLotOffer(
            id: lot.id.uuidString,
            vendor_id: lot.vendorId?.uuidString,
            vendor_name_snapshot: lot.vendorNameSnapshot,
            margin_pct_snapshot: lot.marginPctSnapshot,
            lot_offer_state: lot.lotOfferState,
            lot_offer_state_updated_at: lot.lotOfferStateUpdatedAt.map { ISO8601DateFormatter.shared.string(from: $0) },
            updated_at: ISO8601DateFormatter.shared.string(from: lot.updatedAt)
        )
        let now = Date()
        let item = OutboxItem(
            id: UUID(),
            kind: .updateLotOffer,
            payload: (try? JSONEncoder().encode(payload)) ?? Data(),
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        )
        context.insert(item)
    }

    private func enqueueScanBuyPricePatch(_ scan: Scan) {
        let payload = OutboxPayloads.UpdateScanBuyPrice(
            id: scan.id.uuidString,
            buy_price_cents: scan.buyPriceCents,
            buy_price_overridden: scan.buyPriceOverridden,
            updated_at: ISO8601DateFormatter.shared.string(from: scan.updatedAt)
        )
        let now = Date()
        let item = OutboxItem(
            id: UUID(),
            kind: .updateScanBuyPrice,
            payload: (try? JSONEncoder().encode(payload)) ?? Data(),
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        )
        context.insert(item)
    }

    private func recompute(lot lotId: UUID) throws {
        let payload = OutboxPayloads.RecomputeLotOffer(lot_id: lotId.uuidString)
        let now = Date()
        let item = OutboxItem(
            id: UUID(),
            kind: .recomputeLotOffer,
            payload: try JSONEncoder().encode(payload),
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        )
        context.insert(item)
    }
}
