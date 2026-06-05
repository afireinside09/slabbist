import Foundation

/// Builds an impact.com affiliate deep link to a TCGplayer product page so
/// Slabbist earns commission on resulting sales. Mirrors `EbayAffiliateLink`.
///
/// The destination is always `https://www.tcgplayer.com/product/{id}`. When an
/// impact base tracking URL is configured (the `AppEnvironment` default, or a
/// `TCGPLAYER_IMPACT_BASE_URL` override) the destination is percent-encoded
/// into that link's `u=` parameter, with the originating surface in `subId1`
/// for impact-side click reporting. When no base URL is configured the raw
/// tcgplayer.com URL is returned so the button still works (un-attributed) —
/// the same graceful fallback as the eBay integration's missing-campaign path.
///
/// `baseURL` is injectable so tests are deterministic regardless of the build's
/// resolved config; production call sites omit it.
///
/// `subId` must be URL-safe; the known surfaces ("graded", "mover", "gradegain")
/// satisfy this.
enum TCGPlayerAffiliateLink {
    static func link(
        productId: Int,
        subId: String,
        baseURL: String = AppEnvironment.tcgplayerImpactBaseURL
    ) -> URL? {
        guard productId > 0 else { return nil }
        let destination = "https://www.tcgplayer.com/product/\(productId)"
        guard !baseURL.isEmpty else { return URL(string: destination) }

        // RFC 3986 unreserved set — encodes ":" and "/" so the destination is a
        // valid single query value (URLComponents would leave them bare).
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: unreserved) ?? destination
        return URL(string: "\(baseURL)?subId1=\(subId)&u=\(encoded)")
    }

    /// Builds an affiliate deep link to a TCGplayer **search** for `query`
    /// (used when we have no resolved product id — e.g. cameo cards). The
    /// destination is `tcgplayer.com/search/pokemon/product?...q=<query>`,
    /// percent-encoded into the impact base's `u=` param with `subId1`.
    /// Returns nil for a blank query so callers can hide the button.
    static func searchLink(
        query: String,
        subId: String,
        baseURL: String = AppEnvironment.tcgplayerImpactBaseURL
    ) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Encode the query as a query-component value (space -> %20).
        let queryAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? trimmed
        let destination = "https://www.tcgplayer.com/search/pokemon/product?productLineName=pokemon&q=\(q)"
        guard !baseURL.isEmpty else { return URL(string: destination) }

        // Encode the whole destination as a single u= value (same rule as link()).
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: unreserved) ?? destination
        return URL(string: "\(baseURL)?subId1=\(subId)&u=\(encoded)")
    }
}
