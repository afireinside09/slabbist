import Foundation

/// Pure pricing math used by the lot-offer flow. Lives in its own type so the
/// rules — how the per-scan buy price is derived from a reconciled comp + the
/// store's margin — are testable in isolation and never duplicated across the
/// repository, the view models, or the recompute Edge Function's local mirror.
///
/// Mirrors the server-side derivation in `/lot-offer-recompute`: clients
/// auto-populate `scans.buy_price_cents` locally so the UI is responsive, the
/// outbox pushes the override flag + value, and the Edge Function reconciles
/// the lot total. Keeping the formula here (and not inside `OfferRepository`)
/// guarantees both producers stay in lock-step.
enum OfferPricingService {
    /// Auto-derived per-line buy price, in cents.
    ///
    /// Returns `nil` when either input is `nil` (e.g. the comp hasn't landed
    /// yet, or the store hasn't snapshotted a margin onto the lot) or when
    /// the margin sits outside `[0, 1]` — the latter guard keeps stray
    /// percent-vs-fraction bugs from silently producing nonsense buy prices.
    ///
    /// Rounding is "half-up to the nearest cent": `floor(raw + 0.5)` so a
    /// fractional `0.5` always rounds up to the next full cent. Plain
    /// `Double.rounded()` defaults to banker's rounding, which would round
    /// `0.5` to the nearest even value and quietly disagree with the
    /// server-side recompute.
    static func defaultBuyPrice(reconciledCents: Int64?, marginPct: Double?) -> Int64? {
        guard let reconciledCents, let marginPct else { return nil }
        guard marginPct >= 0 && marginPct <= 1 else { return nil }
        let raw = Double(reconciledCents) * marginPct
        return Int64((raw + 0.5).rounded(.down))
    }
}
