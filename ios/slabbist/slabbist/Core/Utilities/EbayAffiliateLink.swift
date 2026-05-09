import Foundation

/// Rewrites raw eBay item URLs into eBay Partner Network (EPN) affiliate
/// links so Slabbist earns commission on resulting sales.
///
/// Input is the URL eBay served us (stored verbatim in
/// `mover_ebay_listings.url`). Output is the same URL with EPN smart-link
/// query params merged in. Non-eBay hosts pass through untouched. If the
/// campaign ID is missing (e.g. a dev build with no `Secrets.xcconfig`),
/// the original URL is returned so the app stays usable.
enum EbayAffiliateLink {
    /// US site rotation ID — required by EPN smart links.
    private static let rotationID = "711-53200-19255-0"

    static func rewrite(_ raw: String) -> URL? {
        guard var components = URLComponents(string: raw) else { return nil }
        guard let host = components.host?.lowercased(), host.hasSuffix("ebay.com") else {
            return components.url
        }

        let campaignID = AppEnvironment.epnCampaignID
        guard !campaignID.isEmpty else { return components.url }

        let epnParams: [String: String] = [
            "mkcid": "1",
            "mkrid": rotationID,
            "siteid": "0",
            "campid": campaignID,
            "customid": AppEnvironment.epnCustomID,
            "toolid": "10001",
            "mkevt": "1",
        ]

        var items = components.queryItems ?? []
        let existingNames = Set(items.map(\.name))
        for (name, value) in epnParams where !existingNames.contains(name) {
            items.append(URLQueryItem(name: name, value: value))
        }
        components.queryItems = items
        return components.url
    }
}
