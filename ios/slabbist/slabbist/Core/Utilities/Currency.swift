import Foundation

enum Currency {
    /// Shared so feature views can format USD without re-instantiating.
    static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    static func displayUSD(cents: Int64?) -> String {
        guard let cents else { return "—" }
        let divided = Decimal(cents) / Decimal(100)
        return usdFormatter.string(from: divided as NSDecimalNumber) ?? "—"
    }

    /// Whole-dollar currency formatter — no fraction digits. Paired with
    /// `usdFormatter` by `displayUSDCompact`.
    static let usdWholeFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f
    }()

    /// Drops the cents when the amount is a whole number of dollars
    /// ("$1,200" rather than "$1,200.00"), otherwise shows two digits. Used
    /// by the lot/scan buy-price heros where round numbers read cleaner.
    /// Picks between two cached formatters so nothing is allocated or
    /// mutated per render.
    static func displayUSDCompact(cents: Int64?) -> String {
        guard let cents else { return "—" }
        let formatter = cents % 100 == 0 ? usdWholeFormatter : usdFormatter
        let divided = Decimal(cents) / Decimal(100)
        return formatter.string(from: divided as NSDecimalNumber) ?? "—"
    }

    /// Parses a US-locale dollar amount into cents. Comma is treated as the
    /// thousands separator (not the decimal mark) so "1,500" → 150000, not
    /// 150 — the bug `Manual/BuyPriceSheet.parseCents` used to ship.
    /// Returns nil for empty / non-numeric / negative input.
    static func parseUSDToCents(_ raw: String) -> Int64? {
        let cleaned = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard let dollars = Decimal(string: cleaned, locale: Locale(identifier: "en_US")),
              dollars >= 0 else {
            return nil
        }
        var scaled = dollars * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let value = rounded as NSDecimalNumber
        guard value.compare(NSDecimalNumber(value: Int64.max)) != .orderedDescending else {
            return nil
        }
        return value.int64Value
    }
}

extension ISO8601DateFormatter {
    static let shared = ISO8601DateFormatter()
}
