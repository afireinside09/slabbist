import Foundation
import SwiftData

@MainActor
final class CompRepository {
    enum Error: Swift.Error, Equatable {
        case noMarketData
        case productNotResolved
        case identityNotFound
        case authInvalid
        case upstreamUnavailable
        case httpStatus(Int)
        case decoding(String)
    }

    nonisolated struct Wire: Decodable {
        let headline_price_cents: Int64?
        let grading_service: String
        let grade: String
        let loose_price_cents: Int64?
        let psa_7_price_cents: Int64?
        let psa_8_price_cents: Int64?
        let psa_9_price_cents: Int64?
        let psa_9_5_price_cents: Int64?
        let psa_10_price_cents: Int64?
        let bgs_10_price_cents: Int64?
        let cgc_10_price_cents: Int64?
        let sgc_10_price_cents: Int64?
        let price_history: [PriceHistoryPoint]
        let ppt_tcgplayer_id: String
        let ppt_url: String
        let fetched_at: Date
        let cache_hit: Bool
        let is_stale_fallback: Bool
        // v2 additions; both optional so legacy responses still decode.
        let poketrace: PoketraceWire?
        let reconciled: ReconciledWire?

        struct PoketraceWire: Decodable {
            let card_id: String
            let tier: String
            let avg_cents: Int64?
            let low_cents: Int64?
            let high_cents: Int64?
            let avg_1d_cents: Int64?
            let avg_7d_cents: Int64?
            let avg_30d_cents: Int64?
            let median_3d_cents: Int64?
            let median_7d_cents: Int64?
            let median_30d_cents: Int64?
            let trend: String?
            let confidence: String?
            let sale_count: Int?
            /// Per-tier ladder for the iOS source toggle. Optional so
            /// pre-ladder responses still decode; absent keys are
            /// rendered as "no data" cells.
            let tier_prices_cents: [String: Int64]?
            let price_history: [PriceHistoryPoint]
            let fetched_at: Date
        }
        struct ReconciledWire: Decodable {
            let headline_price_cents: Int64?
            let source: String
        }
    }

    struct Decoded {
        let headlinePriceCents: Int64?
        let gradingService: String
        let grade: String
        let loosePriceCents: Int64?
        let psa7PriceCents: Int64?
        let psa8PriceCents: Int64?
        let psa9PriceCents: Int64?
        let psa9_5PriceCents: Int64?
        let psa10PriceCents: Int64?
        let bgs10PriceCents: Int64?
        let cgc10PriceCents: Int64?
        let sgc10PriceCents: Int64?
        let priceHistory: [PriceHistoryPoint]
        let pptTCGPlayerId: String
        let pptURL: URL?
        let fetchedAt: Date
        let cacheHit: Bool
        let isStaleFallback: Bool
        let poketrace: SourceComp?
        let reconciledHeadlineCents: Int64?
        let reconciledSource: String  // "avg" | "ppt-only" | "poketrace-only"

        struct SourceComp: Equatable {
            let cardId: String
            let tier: String
            let avgCents: Int64?
            let lowCents: Int64?
            let highCents: Int64?
            let avg1dCents: Int64?
            let avg7dCents: Int64?
            let avg30dCents: Int64?
            let median3dCents: Int64?
            let median7dCents: Int64?
            let median30dCents: Int64?
            let trend: String?
            let confidence: String?
            let saleCount: Int?
            /// Per-tier ladder for the source toggle, keyed by snake_case
            /// ladder ids ("loose"/"psa_7".."sgc_10"); values in cents.
            let tierPricesCents: [String: Int64]
            let priceHistory: [PriceHistoryPoint]
            let fetchedAt: Date
        }
    }

    private let urlSession: URLSession
    private let baseURL: URL
    private let authTokenProvider: () async -> String?

    init(urlSession: URLSession = .shared, baseURL: URL, authTokenProvider: @escaping () async -> String?) {
        self.urlSession = urlSession
        self.baseURL = baseURL
        self.authTokenProvider = authTokenProvider
    }

    nonisolated static func decode(data: Data) throws -> Decoded {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wire: Wire
        do { wire = try decoder.decode(Wire.self, from: data) }
        catch { throw Error.decoding("\(error)") }
        let poketrace = wire.poketrace.map { pt in
            Decoded.SourceComp(
                cardId: pt.card_id, tier: pt.tier,
                avgCents: pt.avg_cents, lowCents: pt.low_cents, highCents: pt.high_cents,
                avg1dCents: pt.avg_1d_cents, avg7dCents: pt.avg_7d_cents, avg30dCents: pt.avg_30d_cents,
                median3dCents: pt.median_3d_cents, median7dCents: pt.median_7d_cents, median30dCents: pt.median_30d_cents,
                trend: pt.trend, confidence: pt.confidence, saleCount: pt.sale_count,
                tierPricesCents: pt.tier_prices_cents ?? [:],
                priceHistory: pt.price_history, fetchedAt: pt.fetched_at
            )
        }
        let reconciledCents = wire.reconciled?.headline_price_cents ?? wire.headline_price_cents
        let reconciledSource = wire.reconciled?.source ?? "ppt-only"
        return Decoded(
            headlinePriceCents: wire.headline_price_cents,
            gradingService: wire.grading_service,
            grade: wire.grade,
            loosePriceCents: wire.loose_price_cents,
            psa7PriceCents: wire.psa_7_price_cents,
            psa8PriceCents: wire.psa_8_price_cents,
            psa9PriceCents: wire.psa_9_price_cents,
            psa9_5PriceCents: wire.psa_9_5_price_cents,
            psa10PriceCents: wire.psa_10_price_cents,
            bgs10PriceCents: wire.bgs_10_price_cents,
            cgc10PriceCents: wire.cgc_10_price_cents,
            sgc10PriceCents: wire.sgc_10_price_cents,
            priceHistory: wire.price_history,
            pptTCGPlayerId: wire.ppt_tcgplayer_id,
            pptURL: URL(string: wire.ppt_url),
            fetchedAt: wire.fetched_at,
            cacheHit: wire.cache_hit,
            isStaleFallback: wire.is_stale_fallback,
            poketrace: poketrace,
            reconciledHeadlineCents: reconciledCents,
            reconciledSource: reconciledSource
        )
    }

    nonisolated static func decodeErrorBody(_ data: Data, statusCode: Int) throws -> Never {
        struct Body: Decodable { let code: String? }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        switch (statusCode, body?.code) {
        case (404, "NO_MARKET_DATA"):       throw Error.noMarketData
        case (404, "PRODUCT_NOT_RESOLVED"): throw Error.productNotResolved
        case (404, "IDENTITY_NOT_FOUND"):   throw Error.identityNotFound
        case (502, "AUTH_INVALID"):         throw Error.authInvalid
        case (503, "UPSTREAM_UNAVAILABLE"): throw Error.upstreamUnavailable
        default: throw Error.httpStatus(statusCode)
        }
    }

    func fetchComp(
        identityId: UUID,
        gradingService: String,
        grade: String
    ) async throws -> Decoded {
        var request = URLRequest(url: baseURL.appendingPathComponent("/price-comp"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let token = await authTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "graded_card_identity_id": identityId.uuidString.lowercased(),
            "grading_service": gradingService,
            "grade": grade,
        ])
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Error.httpStatus(0) }
        if http.statusCode == 200 { return try Self.decode(data: data) }
        try Self.decodeErrorBody(data, statusCode: http.statusCode)
    }
}
