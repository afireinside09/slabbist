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

    @Test("decodes a v2 envelope with both PPT and Poketrace blocks present")
    func decodesV2BothSources() async throws {
        let json = #"""
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
          "price_history": [{ "ts": "2025-11-08T00:00:00Z", "price_cents": 16200 }],
          "ppt_tcgplayer_id": "243172",
          "ppt_url": "https://www.pokemonpricetracker.com/card/charizard",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": false,
          "is_stale_fallback": false,
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
            "price_history": [{ "ts": "2026-04-30T00:00:00Z", "price_cents": 19200 }],
            "fetched_at": "2026-05-07T22:14:03Z"
          },
          "reconciled": { "headline_price_cents": 19000, "source": "avg" }
        }
        """#.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.headlinePriceCents == 18500)
        #expect(decoded.poketrace != nil)
        #expect(decoded.poketrace?.avgCents == 19500)
        #expect(decoded.poketrace?.trend == "stable")
        #expect(decoded.poketrace?.confidence == "high")
        #expect(decoded.poketrace?.saleCount == 24)
        #expect(decoded.reconciledHeadlineCents == 19000)
        #expect(decoded.reconciledSource == "avg")
    }

    @Test("decodes a v2 envelope with poketrace null (PPT-only)")
    func decodesV2PptOnly() async throws {
        let json = #"""
        {
          "headline_price_cents": 18500,
          "grading_service": "PSA", "grade": "10",
          "loose_price_cents": 400,
          "psa_7_price_cents": null, "psa_8_price_cents": null,
          "psa_9_price_cents": null, "psa_9_5_price_cents": null,
          "psa_10_price_cents": 18500, "bgs_10_price_cents": null,
          "cgc_10_price_cents": null, "sgc_10_price_cents": null,
          "price_history": [],
          "ppt_tcgplayer_id": "243172",
          "ppt_url": "https://www.pokemonpricetracker.com/card/charizard",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": false, "is_stale_fallback": false,
          "poketrace": null,
          "reconciled": { "headline_price_cents": 18500, "source": "ppt-only" }
        }
        """#.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.poketrace == nil)
        #expect(decoded.reconciledSource == "ppt-only")
    }

    @Test("decodes a legacy (pre-v2) response with no poketrace/reconciled blocks")
    func decodesLegacyResponse() async throws {
        let json = #"""
        {
          "headline_price_cents": 18500,
          "grading_service": "PSA", "grade": "10",
          "loose_price_cents": 400,
          "psa_7_price_cents": null, "psa_8_price_cents": null,
          "psa_9_price_cents": null, "psa_9_5_price_cents": null,
          "psa_10_price_cents": 18500, "bgs_10_price_cents": null,
          "cgc_10_price_cents": null, "sgc_10_price_cents": null,
          "price_history": [],
          "ppt_tcgplayer_id": "243172",
          "ppt_url": "https://www.pokemonpricetracker.com/card/charizard",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": false, "is_stale_fallback": false
        }
        """#.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.poketrace == nil)
        #expect(decoded.reconciledHeadlineCents == 18500)   // falls back to PPT headline
        #expect(decoded.reconciledSource == "ppt-only")     // synthesized
    }
}
