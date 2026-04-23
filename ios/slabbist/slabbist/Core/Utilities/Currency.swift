import Foundation

enum Currency {
    private static let usdFormatter: NumberFormatter = {
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
}

extension ISO8601DateFormatter {
    static let shared = ISO8601DateFormatter()
}
