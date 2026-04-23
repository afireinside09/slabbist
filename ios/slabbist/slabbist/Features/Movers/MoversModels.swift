import Foundation

/// TCG language surface exposed in the Movers tab. The raw value is
/// the `tcg_categories.category_id` the RPC filters on.
enum MoversLanguage: Int, CaseIterable, Identifiable, Sendable, Hashable {
    case english = 3
    case japanese = 85

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .english:  return "English"
        case .japanese: return "Japanese"
        }
    }
}

/// Direction of the move — top gainers (largest positive %) or top
/// losers (largest negative %). Raw value maps to the RPC parameter.
enum MoversDirection: String, CaseIterable, Identifiable, Sendable, Hashable {
    case gainers
    case losers

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gainers: return "Gainers"
        case .losers:  return "Losers"
        }
    }
}
