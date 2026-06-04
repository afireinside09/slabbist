import Foundation
import SwiftData
import Supabase
import Auth

@MainActor
final class CompRepository {
    enum Error: Swift.Error, Equatable {
        case noMarketData
        case productNotResolved
        case identityNotFound
        case upstreamUnavailable
        case httpStatus(Int)
        case decoding(String)
    }

    nonisolated struct Wire: Decodable {
        let grading_service: String
        let grade: String
        let headline_price_cents: Int64?
        let poketrace: PoketraceWire?
        let sold_listings: [SoldListingWire]
        let marketplace_url: String?
        let fetched_at: Date
        let cache_hit: Bool

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
            /// Per-tier ladder for the iOS comp-card, keyed by snake_case
            /// tier ids ("loose"/"psa_7".."sgc_10"); values in cents.
            /// Optional so pre-ladder responses still decode.
            let tier_prices_cents: [String: Int64]?
            let price_history: [PriceHistoryPoint]
            let fetched_at: Date
        }

        struct SoldListingWire: Decodable {
            let source_listing_id: String
            let title: String?
            let price_cents: Int64?
            let sold_at: Date
            let grader: String?
            let grade: String?
            let condition: String?
            let url: String?
            let anomaly_flag: String?
        }
    }

    struct Decoded {
        let gradingService: String
        let grade: String
        let headlinePriceCents: Int64?
        let poketrace: SourceComp?
        let soldListings: [SoldListing]
        let marketplaceURL: URL?
        let fetchedAt: Date
        let cacheHit: Bool

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
            /// Per-tier ladder for the comp-card, keyed by snake_case ladder ids
            /// ("loose"/"psa_7".."sgc_10"); values in cents.
            let tierPricesCents: [String: Int64]
            let priceHistory: [PriceHistoryPoint]
            let fetchedAt: Date
        }
    }

    private let urlSession: URLSession
    private let baseURL: URL
    private let authTokenProvider: () async -> String?

    /// Uses the fail-fast `URLSession.shared` ON PURPOSE — NOT
    /// `SupabaseHTTP.shared`. That tuned session sets
    /// `waitsForConnectivity = true`, which is right for the background
    /// outbox (queue through a wifi blip, retry invisibly) but wrong for
    /// this foreground read: offline it would spin up to 60s behind a
    /// "Pulling listings…" spinner instead of failing in ~1s so the UI can
    /// show its offline/retry affordance. Tests inject their own session.
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

        let soldListings: [SoldListing] = wire.sold_listings.compactMap { sl in
            SoldListing(
                sourceListingId: sl.source_listing_id,
                title: sl.title,
                priceCents: sl.price_cents,
                soldAt: sl.sold_at,
                grader: sl.grader,
                grade: sl.grade,
                condition: sl.condition,
                url: sl.url.flatMap(URL.init(string:)),
                anomalyFlag: sl.anomaly_flag
            )
        }

        return Decoded(
            gradingService: wire.grading_service,
            grade: wire.grade,
            headlinePriceCents: wire.headline_price_cents,
            poketrace: poketrace,
            soldListings: soldListings,
            marketplaceURL: wire.marketplace_url.flatMap(URL.init(string:)),
            fetchedAt: wire.fetched_at,
            cacheHit: wire.cache_hit
        )
    }

    nonisolated static func decodeErrorBody(_ data: Data, statusCode: Int) throws -> Never {
        struct Body: Decodable { let code: String? }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        switch (statusCode, body?.code) {
        case (404, "NO_MARKET_DATA"):       throw Error.noMarketData
        case (404, "PRODUCT_NOT_RESOLVED"): throw Error.productNotResolved
        case (404, "IDENTITY_NOT_FOUND"):   throw Error.identityNotFound
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

    /// Production constructor used by every UI surface that needs to
    /// re-fire a comp fetch (the scan detail Retry button, the
    /// lot-detail row retry, the queue-row retry). Single source of the
    /// base URL + auth token closure — duplicated inline construction
    /// risks URL drift across surfaces (P1.4 / CLAUDE.md Rule 3).
    static func live() -> CompRepository {
        let baseURL = AppEnvironment.supabaseURL.appendingPathComponent("/functions/v1")
        return CompRepository(
            baseURL: baseURL,
            authTokenProvider: { try? await AppSupabase.shared.client.auth.session.accessToken }
        )
    }
}
