import Foundation
import SwiftData

enum OutlierReason: String, Codable, CaseIterable {
    case priceHigh = "price_high"
    case priceLow  = "price_low"
}

@Model
final class SoldListingMirror {
    @Attribute(.unique) var id: UUID
    var soldPriceCents: Int64
    var soldAt: Date
    var title: String
    var url: URL
    var source: String
    var isOutlier: Bool
    var outlierReasonRaw: String?

    var outlierReason: OutlierReason? {
        get { outlierReasonRaw.flatMap(OutlierReason.init(rawValue:)) }
        set { outlierReasonRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        soldPriceCents: Int64,
        soldAt: Date,
        title: String,
        url: URL,
        source: String = "ebay",
        isOutlier: Bool = false,
        outlierReason: OutlierReason? = nil
    ) {
        self.id = id
        self.soldPriceCents = soldPriceCents
        self.soldAt = soldAt
        self.title = title
        self.url = url
        self.source = source
        self.isOutlier = isOutlier
        self.outlierReasonRaw = outlierReason?.rawValue
    }
}
