import Testing
import Foundation
import SwiftData
@testable import slabbist

@Suite("CompRepository")
@MainActor
struct CompRepositoryTests {
    @Test("decodes a full PPT cross-grader ladder response")
    func decodesFullLadder() async throws {
        let json = """
        {
          "headline_price_cents": 18500,
          "grading_service": "PSA",
          "grade": "10",
          "loose_price_cents": 400,
          "psa_7_price_cents": 2400,
          "psa_8_price_cents": 3400,
          "psa_9_price_cents": 6800,
          "psa_9_5_price_cents": 11200,
          "psa_10_price_cents": 18500,
          "bgs_10_price_cents": 21500,
          "cgc_10_price_cents": 16800,
          "sgc_10_price_cents": 16500,
          "price_history": [
            { "ts": "2025-11-08T00:00:00Z", "price_cents": 16200 },
            { "ts": "2025-11-15T00:00:00Z", "price_cents": 16850 }
          ],
          "ppt_tcgplayer_id": "243172",
          "ppt_url": "https://www.pokemonpricetracker.com/card/charizard-base-set",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": false,
          "is_stale_fallback": false
        }
        """.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.headlinePriceCents == 18500)
        #expect(decoded.psa10PriceCents == 18500)
        #expect(decoded.bgs10PriceCents == 21500)
        #expect(decoded.psa9_5PriceCents == 11200)
        #expect(decoded.loosePriceCents == 400)
        #expect(decoded.priceHistory.count == 2)
        #expect(decoded.priceHistory.first?.priceCents == 16200)
        #expect(decoded.pptTCGPlayerId == "243172")
        #expect(decoded.cacheHit == false)
    }

    @Test("decodes a partial ladder with null tiers")
    func decodesPartialLadder() async throws {
        let json = """
        {
          "headline_price_cents": null,
          "grading_service": "TAG",
          "grade": "10",
          "loose_price_cents": 500,
          "psa_7_price_cents": null,
          "psa_8_price_cents": null,
          "psa_9_price_cents": 4200,
          "psa_9_5_price_cents": null,
          "psa_10_price_cents": 18000,
          "bgs_10_price_cents": null,
          "cgc_10_price_cents": null,
          "sgc_10_price_cents": null,
          "price_history": [],
          "ppt_tcgplayer_id": "98765432",
          "ppt_url": "https://www.pokemonpricetracker.com/card/obscure",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": true,
          "is_stale_fallback": false
        }
        """.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.headlinePriceCents == nil)
        #expect(decoded.psa10PriceCents == 18000)
        #expect(decoded.bgs10PriceCents == nil)
        #expect(decoded.priceHistory.isEmpty)
    }

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

    @Test("502 AUTH_INVALID surfaces as authInvalid")
    func mapsAuthInvalid() async throws {
        let json = #"{ "code": "AUTH_INVALID" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.authInvalid) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 502)
        }
    }

    @Test("503 UPSTREAM_UNAVAILABLE surfaces as upstreamUnavailable")
    func mapsUpstreamUnavailable() async throws {
        let json = #"{ "code": "UPSTREAM_UNAVAILABLE" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.upstreamUnavailable) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 503)
        }
    }
}
