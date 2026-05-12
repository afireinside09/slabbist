import Foundation

/// One rung on the buyer's per-slab margin ladder. The ladder is a per-store
/// configurable rule: for each scan whose lot has no manual margin override,
/// the buy-price math picks the highest tier whose `minCompCents` the scan's
/// reconciled comp meets, and applies that tier's `marginPct`.
///
/// Stored on `stores.margin_ladder` as a JSON array. Encoded/decoded with
/// snake_case keys so the column round-trips through Postgrest without a
/// remapping layer.
nonisolated struct MarginTier: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// Inclusive lower bound, in cents. A tier with `minCompCents = 0`
    /// is the floor — every scan whose comp is non-negative qualifies.
    var minCompCents: Int64
    /// Margin to apply when this tier matches, expressed as a fraction
    /// in [0, 1]. Out-of-range values are rejected at the call site
    /// (see `OfferPricingService.defaultBuyPrice`).
    var marginPct: Double

    /// Synthetic identity for `ForEach` / list editing. The (cents, pct)
    /// pair is unique within a single ladder by construction (we keep
    /// thresholds sorted + de-duped on save).
    var id: String { "\(minCompCents)-\(marginPct)" }

    enum CodingKeys: String, CodingKey {
        case minCompCents = "min_comp_cents"
        case marginPct = "margin_pct"
    }
}

extension Array where Element == MarginTier {
    /// Canonical default ladder. Floor at 70% so the iOS picker's range
    /// (70%-100%) covers every tier the user can choose. Steps grow at
    /// $100 / $250 / $500 / $1000 — coarse enough to be readable in the
    /// edit screen but granular enough to cover the typical hobby-store
    /// "low ticket vs. premium card" spread. `nonisolated` so DTOs (also
    /// nonisolated) can use it as a property default under the
    /// `-default-isolation=MainActor` build setting.
    nonisolated static var defaultMarginLadder: [MarginTier] {
        [
            MarginTier(minCompCents: 100_000, marginPct: 0.90),
            MarginTier(minCompCents:  50_000, marginPct: 0.85),
            MarginTier(minCompCents:  25_000, marginPct: 0.80),
            MarginTier(minCompCents:  10_000, marginPct: 0.75),
            MarginTier(minCompCents:       0, marginPct: 0.70),
        ]
    }

    /// Sort highest threshold first + drop tiers with a non-positive
    /// or out-of-range margin. Call before persisting so the wire shape
    /// stays predictable and the lookup can short-circuit on the first
    /// matching tier.
    nonisolated func canonicalized() -> [MarginTier] {
        self
            .filter { $0.marginPct >= 0 && $0.marginPct <= 1 && $0.minCompCents >= 0 }
            .sorted { $0.minCompCents > $1.minCompCents }
    }

    /// Pick the matching margin for a scan whose reconciled comp is
    /// `compCents`. Returns `nil` when the ladder is empty or when no
    /// tier covers the value (e.g. ladder has no zero-floor row and the
    /// scan's comp is below every threshold). Callers fall back to
    /// `store.defaultMarginPct` so the math still produces a number.
    nonisolated func margin(forCompCents compCents: Int64) -> Double? {
        for tier in canonicalized() where compCents >= tier.minCompCents {
            return tier.marginPct
        }
        return nil
    }
}
