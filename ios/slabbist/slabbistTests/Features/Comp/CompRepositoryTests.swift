import Testing
import Foundation
import SwiftData
@testable import slabbist

@Suite("CompRepository")
@MainActor
struct CompRepositoryTests {
    @Test("decodes a live-fetch response into a GradedMarketSnapshot with listings")
    func decodesLiveFetchResponse() async throws {
        let json = """
        {
          "blended_price_cents": 12413,
          "mean_price_cents": 34940,
          "trimmed_mean_price_cents": 12413,
          "median_price_cents": 12350,
          "low_price_cents": 100,
          "high_price_cents": 250000,
          "confidence": 1.0,
          "sample_count": 10,
          "sample_window_days": 90,
          "velocity_7d": 3,
          "velocity_30d": 10,
          "velocity_90d": 10,
          "sold_listings": [
            { "sold_price_cents": 250000, "sold_at": "2026-04-20T10:00:00Z",
              "title": "SIGNED", "url": "https://www.ebay.com/itm/1",
              "source": "ebay", "is_outlier": true, "outlier_reason": "price_high" }
          ],
          "fetched_at": "2026-04-23T22:14:03Z",
          "cache_hit": false,
          "is_stale_fallback": false
        }
        """.data(using: .utf8)!

        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.blendedPriceCents == 12413)
        #expect(decoded.sampleCount == 10)
        #expect(decoded.soldListings.count == 1)
        #expect(decoded.soldListings[0].isOutlier == true)
        #expect(decoded.soldListings[0].outlierReason == .priceHigh)
    }

    @Test("404 NO_MARKET_DATA surfaces as a typed error")
    func mapsNoMarketData() async throws {
        let json = #"{ "code": "NO_MARKET_DATA" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.noMarketData) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 404)
        }
    }
}
