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

/// Current-price tier slice. The server pre-computes top-10 per
/// (group, sub_type, tier, direction). Raw values match the
/// `price_tier` column on `public.movers` and the `p_price_tier`
/// RPC parameter exactly, so the enum is the wire format.
///
/// There is no "all" case: the product always wants the user on a
/// concrete price band, and `public.movers` no longer stores
/// `'all'` rows. The set rail spans every tier server-side via
/// `get_movers_sets`, so we don't need an "all" sentinel client-side
/// either.
enum MoversPriceTier: String, CaseIterable, Identifiable, Sendable, Hashable {
    case under5      = "under_5"
    case tier5_25    = "tier_5_25"
    case tier25_50   = "tier_25_50"
    case tier50_100  = "tier_50_100"
    case tier100_200 = "tier_100_200"
    case tier200Plus = "tier_200_plus"

    var id: String { rawValue }

    /// Short label for chips in the tier rail.
    var displayName: String {
        switch self {
        case .under5:      return "< $5"
        case .tier5_25:    return "$5–$25"
        case .tier25_50:   return "$25–$50"
        case .tier50_100:  return "$50–$100"
        case .tier100_200: return "$100–$200"
        case .tier200Plus: return "$200+"
        }
    }

    /// Tiers shown in the picker. Same as `allCases` today, kept as
    /// a separate symbol so callers express intent ("the picker
    /// rail") rather than relying on `allCases` order.
    static let pickerOptions: [MoversPriceTier] = allCases
}
