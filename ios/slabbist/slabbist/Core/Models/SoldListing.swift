import Foundation

/// One individual sold eBay comp surfaced from Poketrace's listings endpoint.
struct SoldListing: Codable, Identifiable, Equatable {
    var id: String { sourceListingId }
    let sourceListingId: String
    let title: String?
    let priceCents: Int64?
    let soldAt: Date
    let grader: String?
    let grade: String?
    let condition: String?
    let url: URL?
    let anomalyFlag: String?
}
