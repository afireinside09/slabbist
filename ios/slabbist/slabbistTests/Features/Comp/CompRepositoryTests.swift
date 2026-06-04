import Testing
import Foundation
import SwiftData
@testable import slabbist

@Suite("CompRepository")
@MainActor
struct CompRepositoryTests {

    // MARK: - v3 happy path: poketrace block + sold listings + marketplace_url

    @Test("decodes a v3 response with poketrace block, sold listings, and marketplace_url")
    func decodesV3Full() async throws {
        let json = #"""
        {
          "grading_service": "PSA",
          "grade": "10",
          "headline_price_cents": 19500,
          "poketrace": {
            "card_id": "22222222-2222-2222-2222-222222222222",
            "tier": "PSA_10",
            "avg_cents": 19500,
            "low_cents": 18000,
            "high_cents": 21000,
            "avg_1d_cents": null,
            "avg_7d_cents": 19400,
            "avg_30d_cents": 19200,
            "median_3d_cents": 19500,
            "median_7d_cents": 19350,
            "median_30d_cents": 19000,
            "trend": "stable",
            "confidence": "high",
            "sale_count": 24,
            "tier_prices_cents": { "psa_10": 19500, "psa_9": 6800 },
            "price_history": [
              { "ts": "2026-04-30T00:00:00Z", "price_cents": 19200 }
            ],
            "fetched_at": "2026-05-07T22:14:03Z"
          },
          "sold_listings": [
            {
              "source_listing_id": "ebay-001",
              "title": "Charizard PSA 10",
              "price_cents": 19500,
              "sold_at": "2026-04-28T10:00:00Z",
              "grader": "PSA",
              "grade": "10",
              "condition": "Graded",
              "url": "https://www.ebay.com/itm/001",
              "anomaly_flag": null
            },
            {
              "source_listing_id": "ebay-002",
              "title": "Charizard PSA 10 Base Set",
              "price_cents": 20000,
              "sold_at": "2026-04-25T14:00:00Z",
              "grader": "PSA",
              "grade": "10",
              "condition": "Graded",
              "url": "https://www.ebay.com/itm/002",
              "anomaly_flag": null
            }
          ],
          "marketplace_url": "https://www.ebay.com/sch/i.html?_nkw=charizard+psa+10",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": false
        }
        """#.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.headlinePriceCents == 19500)
        #expect(decoded.gradingService == "PSA")
        #expect(decoded.grade == "10")
        #expect(decoded.cacheHit == false)
        // Poketrace block
        #expect(decoded.poketrace?.avgCents == 19500)
        #expect(decoded.poketrace?.trend == "stable")
        #expect(decoded.poketrace?.confidence == "high")
        #expect(decoded.poketrace?.saleCount == 24)
        #expect(decoded.poketrace?.tier == "PSA_10")
        #expect(decoded.poketrace?.cardId == "22222222-2222-2222-2222-222222222222")
        #expect(decoded.poketrace?.tierPricesCents["psa_10"] == 19500)
        // Sold listings
        #expect(decoded.soldListings.count == 2)
        #expect(decoded.soldListings[0].sourceListingId == "ebay-001")
        #expect(decoded.soldListings[0].priceCents == 19500)
        #expect(decoded.soldListings[0].url != nil)
        // Marketplace URL
        #expect(decoded.marketplaceURL != nil)
        #expect(decoded.marketplaceURL?.host == "www.ebay.com")
    }

    // MARK: - v3: poketrace null, empty sold listings

    @Test("decodes a v3 response with poketrace null and empty sold_listings")
    func decodesV3NullPoketraceNoSoldListings() async throws {
        let json = #"""
        {
          "grading_service": "PSA",
          "grade": "10",
          "headline_price_cents": null,
          "poketrace": null,
          "sold_listings": [],
          "marketplace_url": null,
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": false
        }
        """#.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.poketrace == nil)
        #expect(decoded.soldListings.isEmpty)
        #expect(decoded.headlinePriceCents == nil)
        #expect(decoded.marketplaceURL == nil)
    }

    // MARK: - v3: cache hit

    @Test("decodes a v3 cache-hit response")
    func decodesV3CacheHit() async throws {
        let json = #"""
        {
          "grading_service": "CGC",
          "grade": "9.5",
          "headline_price_cents": 8500,
          "poketrace": {
            "card_id": "33333333-3333-3333-3333-333333333333",
            "tier": "CGC_9_5",
            "avg_cents": 8500,
            "low_cents": null,
            "high_cents": null,
            "avg_1d_cents": null,
            "avg_7d_cents": null,
            "avg_30d_cents": null,
            "median_3d_cents": null,
            "median_7d_cents": null,
            "median_30d_cents": null,
            "trend": null,
            "confidence": null,
            "sale_count": null,
            "price_history": [],
            "fetched_at": "2026-05-07T22:14:03Z"
          },
          "sold_listings": [],
          "marketplace_url": null,
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": true
        }
        """#.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.cacheHit == true)
        #expect(decoded.poketrace?.avgCents == 8500)
        #expect(decoded.soldListings.isEmpty)
    }

    // MARK: - Error body mapping

    @Test("404 NO_MARKET_DATA surfaces as a typed error")
    func mapsNoMarketData() async throws {
        let json = #"{ "code": "NO_MARKET_DATA" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.noMarketData) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 404)
        }
    }

    @Test("404 PRODUCT_NOT_RESOLVED surfaces as productNotResolved")
    func mapsProductNotResolved() async throws {
        let json = #"{ "code": "PRODUCT_NOT_RESOLVED" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.productNotResolved) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 404)
        }
    }

    @Test("404 IDENTITY_NOT_FOUND surfaces as identityNotFound")
    func mapsIdentityNotFound() async throws {
        let json = #"{ "code": "IDENTITY_NOT_FOUND" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.identityNotFound) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 404)
        }
    }

    @Test("503 UPSTREAM_UNAVAILABLE surfaces as upstreamUnavailable")
    func mapsUpstreamUnavailable() async throws {
        let json = #"{ "code": "UPSTREAM_UNAVAILABLE" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.upstreamUnavailable) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 503)
        }
    }

    @Test("unrecognised 404 code falls through to httpStatus(404)")
    func mapsUnknown404() async throws {
        let json = #"{ "code": "SOMETHING_ELSE" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.httpStatus(404)) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 404)
        }
    }

    @Test("502 with unknown code falls through to httpStatus(502)")
    func maps502Default() async throws {
        let json = #"{ "code": "AUTH_INVALID" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.httpStatus(502)) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 502)
        }
    }

    // MARK: - tcgplayer_product_id

    @Test("decodes tcgplayer_product_id string into Int; absent → nil")
    func decodesTcgplayerProductId() throws {
        let withId = #"""
        {
          "grading_service": "PSA", "grade": "10",
          "headline_price_cents": null, "poketrace": null,
          "sold_listings": [], "marketplace_url": null,
          "tcgplayer_product_id": "517812",
          "fetched_at": "2026-06-04T00:00:00Z", "cache_hit": false
        }
        """#
        let a = try CompRepository.decode(data: Data(withId.utf8))
        #expect(a.tcgplayerProductId == 517812)

        let withoutId = #"""
        {
          "grading_service": "PSA", "grade": "10",
          "headline_price_cents": null, "poketrace": null,
          "sold_listings": [], "marketplace_url": null,
          "fetched_at": "2026-06-04T00:00:00Z", "cache_hit": false
        }
        """#
        let b = try CompRepository.decode(data: Data(withoutId.utf8))
        #expect(b.tcgplayerProductId == nil)
    }

    // MARK: - Decoding error on malformed input

    @Test("malformed JSON surfaces as .decoding error")
    func decodingError() async throws {
        let json = #"{ "this": "is broken" }"#.data(using: .utf8)!
        var captured: (any Error)?
        do { _ = try CompRepository.decode(data: json) } catch { captured = error }
        let err = try #require(captured as? CompRepository.Error)
        guard case .decoding = err else {
            Issue.record("expected .decoding, got \(err)")
            return
        }
    }
}
