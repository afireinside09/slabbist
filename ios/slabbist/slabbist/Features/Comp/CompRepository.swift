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
            isStaleFallback: wire.is_stale_fallback
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
