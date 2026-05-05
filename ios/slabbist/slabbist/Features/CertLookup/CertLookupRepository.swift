import Foundation

/// Resolves a `(grader, certNumber)` pair to a `GradedCardIdentity` + grade by
/// calling the `cert-lookup` Supabase Edge Function. The edge function is the
/// only thing that knows the PSA token; iOS never holds it.
@MainActor
final class CertLookupRepository {
    enum Error: Swift.Error, Equatable {
        case certNotFound
        case unsupportedGrader
        case notPokemon
        case rateLimited
        case upstreamUnavailable
        case httpStatus(Int)
        case decoding(String)
    }

    nonisolated struct Wire: Decodable {
        let identity_id: String
        let graded_card_id: String
        let grading_service: String
        let grade: String
        let card: WireCard
        let cache_hit: Bool
    }

    struct WireCard: Decodable {
        let set_name: String
        let card_number: String?
        let card_name: String
        let variant: String?
        let year: Int?
        let language: String
    }

    struct Decoded: Equatable {
        let identityId: UUID
        let gradedCardId: UUID
        let gradingService: String
        let grade: String
        let setName: String
        let cardNumber: String?
        let cardName: String
        let variant: String?
        let year: Int?
        let language: String
        let cacheHit: Bool
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
        let wire: Wire
        do { wire = try decoder.decode(Wire.self, from: data) }
        catch { throw Error.decoding("\(error)") }
        guard let identityId = UUID(uuidString: wire.identity_id) else {
            throw Error.decoding("invalid identity_id")
        }
        guard let cardId = UUID(uuidString: wire.graded_card_id) else {
            throw Error.decoding("invalid graded_card_id")
        }
        return Decoded(
            identityId: identityId,
            gradedCardId: cardId,
            gradingService: wire.grading_service,
            grade: wire.grade,
            setName: wire.card.set_name,
            cardNumber: wire.card.card_number,
            cardName: wire.card.card_name,
            variant: wire.card.variant,
            year: wire.card.year,
            language: wire.card.language,
            cacheHit: wire.cache_hit
        )
    }

    nonisolated static func decodeErrorBody(_ data: Data, statusCode: Int) throws -> Never {
        struct Body: Decodable { let code: String? }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        switch (statusCode, body?.code) {
        case (404, "CERT_NOT_FOUND"): throw Error.certNotFound
        case (415, "UNSUPPORTED_GRADER"): throw Error.unsupportedGrader
        case (415, "NOT_POKEMON"): throw Error.notPokemon
        case (429, _): throw Error.rateLimited
        case (502, _), (503, _): throw Error.upstreamUnavailable
        default: throw Error.httpStatus(statusCode)
        }
    }

    func lookup(grader: Grader, certNumber: String) async throws -> Decoded {
        var request = URLRequest(url: baseURL.appendingPathComponent("/cert-lookup"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let token = await authTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grader": grader.rawValue,
            "cert_number": certNumber,
        ])
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Error.httpStatus(0) }
        if http.statusCode == 200 { return try Self.decode(data: data) }
        try Self.decodeErrorBody(data, statusCode: http.statusCode)
    }
}
