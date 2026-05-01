import Foundation
import SwiftData

@MainActor
final class CompRepository {
    enum Error: Swift.Error, Equatable {
        case noMarketData
        case upstreamUnavailable
        /// Server returned 404 with `code: "IDENTITY_NOT_FOUND"` — the
        /// graded-card identity the client persisted no longer exists
        /// on the server (stale local cache, project switch, manual
        /// row delete). Distinct from `notDeployed` so we can suggest
        /// re-running the cert lookup vs. fixing infrastructure.
        case identityNotFound
        /// 404 with no `code` field (or an unrecognized one) — almost
        /// always means the edge function isn't deployed at the
        /// expected URL. Surfacing this as its own case lets the UI
        /// show actionable copy instead of a bare HTTP code.
        case notDeployed
        case httpStatus(Int)
        case decoding(String)
    }

    struct Wire: Decodable {
        let blended_price_cents: Int64
        let mean_price_cents: Int64
        let trimmed_mean_price_cents: Int64
        let median_price_cents: Int64
        let low_price_cents: Int64
        let high_price_cents: Int64
        let confidence: Double
        let sample_count: Int
        let sample_window_days: Int
        let velocity_7d: Int
        let velocity_30d: Int
        let velocity_90d: Int
        let sold_listings: [WireListing]
        let fetched_at: Date
        let cache_hit: Bool
        let is_stale_fallback: Bool
    }

    struct WireListing: Decodable {
        let sold_price_cents: Int64
        let sold_at: Date
        let title: String
        let url: URL
        let source: String
        let is_outlier: Bool
        let outlier_reason: String?
    }

    struct Decoded {
        let blendedPriceCents: Int64
        let meanPriceCents: Int64
        let trimmedMeanPriceCents: Int64
        let medianPriceCents: Int64
        let lowPriceCents: Int64
        let highPriceCents: Int64
        let confidence: Double
        let sampleCount: Int
        let sampleWindowDays: Int
        let velocity7d: Int
        let velocity30d: Int
        let velocity90d: Int
        let soldListings: [SoldListingMirror]
        let fetchedAt: Date
        let cacheHit: Bool
        let isStaleFallback: Bool
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
        let listings = wire.sold_listings.map { w in
            SoldListingMirror(
                soldPriceCents: w.sold_price_cents,
                soldAt: w.sold_at,
                title: w.title,
                url: w.url,
                source: w.source,
                isOutlier: w.is_outlier,
                outlierReason: w.outlier_reason.flatMap(OutlierReason.init(rawValue:))
            )
        }
        return Decoded(
            blendedPriceCents: wire.blended_price_cents,
            meanPriceCents: wire.mean_price_cents,
            trimmedMeanPriceCents: wire.trimmed_mean_price_cents,
            medianPriceCents: wire.median_price_cents,
            lowPriceCents: wire.low_price_cents,
            highPriceCents: wire.high_price_cents,
            confidence: wire.confidence,
            sampleCount: wire.sample_count,
            sampleWindowDays: wire.sample_window_days,
            velocity7d: wire.velocity_7d,
            velocity30d: wire.velocity_30d,
            velocity90d: wire.velocity_90d,
            soldListings: listings,
            fetchedAt: wire.fetched_at,
            cacheHit: wire.cache_hit,
            isStaleFallback: wire.is_stale_fallback
        )
    }

    nonisolated static func decodeErrorBody(_ data: Data, statusCode: Int) throws -> Never {
        struct Body: Decodable { let code: String? }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        switch (statusCode, body?.code) {
        case (404, "NO_MARKET_DATA"):       throw Error.noMarketData
        case (404, "IDENTITY_NOT_FOUND"):   throw Error.identityNotFound
        case (404, .none):                  throw Error.notDeployed
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
        // Cap a single attempt at 30s. The edge function fetches eBay
        // OAuth + Marketplace Insights (a 4-bucket cascade) and writes
        // back a cache row; warm path is sub-second, cold path < 10s.
        // 30s leaves headroom without leaving the spinner stuck for a
        // full minute when something upstream (eBay API, Supabase
        // cold start) misbehaves.
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
