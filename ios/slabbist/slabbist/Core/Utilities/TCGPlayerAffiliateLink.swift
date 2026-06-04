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
}
