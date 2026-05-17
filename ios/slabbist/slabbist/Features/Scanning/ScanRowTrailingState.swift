import Foundation

/// Picks the trailing-edge UI a scan row should show based on
/// `(compFetchState, reconciledHeadlinePriceCents, snapshot.headlinePriceCents,
/// vendorAskCents)`. Shared between `ScanQueueView`, `LotDetailView.slabRow`,
/// and `LotDetailView`'s aggregate strip so all three surfaces resolve the
/// same value for the same scan — there must not be two parallel resolvers
/// that can drift (P0.1: the prior `trailingValue(for:)` helper would
/// fall back to the raw PPT snapshot while the row would fall through to
/// `.fetching`, producing a header total that didn't match the row body).
///
/// Priority (top wins):
///   1. cert-lookup transient retry — handled separately by the row's own
///      retry pill plumbing and **not** modeled here (the caller checks
///      `isTransientFailed` before calling into this helper).
///   2. `hasManualWithReconciled` — user typed a manual price AND a comp
///      later landed. The pill keeps showing the manual amount (the user's
///      input deserves visible acknowledgement — P1.3) but the aggregate
///      total uses the reconciled value (lot math reflects the market).
///   3. `hasReconciled` — a server-reconciled comp number is on the scan
///      and no manual price is set; show the dollar value.
///   4. `hasSnapshot` — legacy scans validated before reconciliation was
///      plumbed have a `GradedMarketSnapshot.headlinePriceCents` but no
///      `reconciledHeadlinePriceCents`. Render identically to
///      `.hasReconciled` (the user can't tell them apart); the separate
///      case exists so the data path is grep-able and testable.
///   5. `hasManual` — no comp, user typed in a manual price; show the
///      "$25 ✎" edit pill.
///   6. `needsPrice` — comp came back `.noData` with no manual price;
///      show the "Set price" pill.
///   7. `staleFetching` — `.fetching` state older than ~90s; UI shows a
///      Retry CTA (C2 recovery hatch).
///   8. `fetching` — actively fetching; show the existing status copy.
///   9. `failed` — comp lookup failed; show the negative status copy.
///  10. `idle` — nothing has happened yet (cert lookup still pending, or
///      a legacy row with `compFetchState == nil` and no manual price).
enum ScanRowTrailingState: Equatable {
    case hasReconciled(cents: Int64)
    case hasSnapshot(cents: Int64)
    case hasManual(cents: Int64)
    /// Both a manual ask and a reconciled comp exist. The row displays
    /// the manual pill (visible acknowledgement of user input — P1.3);
    /// `aggregateCents` returns the reconciled value (the lot total
    /// reflects the market price, not the operator's draft).
    case hasManualWithReconciled(manualCents: Int64, reconciledCents: Int64)
    case needsPrice
    case staleFetching
    case fetching
    case failed
    case idle

    /// The value this state contributes to a lot's aggregate total, or
    /// `nil` when the state has no dollar amount yet (pills, spinners,
    /// failures). The aggregate strip in `LotDetailView` sums these.
    var aggregateCents: Int64? {
        switch self {
        case .hasReconciled(let c), .hasSnapshot(let c), .hasManual(let c):
            return c
        case .hasManualWithReconciled(_, let reconciled):
            // Reconciled wins for the *total* even though the row shows
            // the manual. That's the contract: the lot math reflects
            // market reality; the row reflects user input.
            return reconciled
        case .needsPrice, .staleFetching, .fetching, .failed, .idle:
            return nil
        }
    }

    /// `true` when the contributing value to the aggregate came from a
    /// user-typed manual price rather than a comp. Drives the "N manual"
    /// suffix on the aggregate caption. Only `.hasManual` qualifies —
    /// `.hasManualWithReconciled` contributes its reconciled cents, so
    /// from the *math's* perspective it isn't a manual contribution.
    var isManualContribution: Bool {
        if case .hasManual = self { return true }
        return false
    }

    /// Resolve the trailing state from a scan's persisted fields. Reads
    /// `Scan` + an optional latest snapshot so test fixtures can build
    /// a `Scan` and round-trip the same way the view does. Callers that
    /// don't have a snapshot to join (the queue row, which renders before
    /// the snapshot @Query lands) pass `nil` and the legacy-snapshot
    /// fallback is skipped — the row falls through to `.fetching`/`.idle`
    /// as before.
    static func resolve(
        for scan: Scan,
        snapshot: GradedMarketSnapshot? = nil,
        now: Date = Date()
    ) -> ScanRowTrailingState {
        let manual = scan.vendorAskCents
        if let cents = scan.reconciledHeadlinePriceCents {
            if let manual {
                return .hasManualWithReconciled(manualCents: manual, reconciledCents: cents)
            }
            return .hasReconciled(cents: cents)
        }
        if let cents = snapshot?.headlinePriceCents {
            // Legacy snapshot-only path. Same shadow-prevention rule as
            // the reconciled branch: if the user typed a manual price,
            // surface it on the row even though the aggregate uses the
            // snapshot dollar value.
            if let manual {
                return .hasManualWithReconciled(manualCents: manual, reconciledCents: cents)
            }
            return .hasSnapshot(cents: cents)
        }
        if let manual {
            return .hasManual(cents: manual)
        }
        let state = scan.compFetchState.flatMap(CompFetchState.init(rawValue:))
        switch state {
        case .noData:
            return .needsPrice
        case .fetching:
            return CompFetchService.isStaleFetching(scan, now: now) ? .staleFetching : .fetching
        case .failed:
            return .failed
        case .resolved, .none:
            return .idle
        }
    }
}
