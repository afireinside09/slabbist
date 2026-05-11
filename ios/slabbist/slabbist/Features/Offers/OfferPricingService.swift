import Foundation

/// Pure helpers for client-side buy-price derivation.
///
/// `defaultBuyPrice` is the auto-pricing rule (comp × margin, half-up rounding)
/// that the iOS app applies when a scan's comp lands. The server-side
/// `/lot-offer-recompute` Edge Function does NOT re-derive — it sums the
/// `buy_price_cents` values the client wrote. So this is the single source of
/// truth for the auto-pricing formula; the server is the source of truth for
/// per-lot totals.
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
