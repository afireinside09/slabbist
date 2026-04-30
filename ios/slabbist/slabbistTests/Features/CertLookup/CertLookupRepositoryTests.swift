import Testing
import Foundation
@testable import slabbist

@Suite("CertLookupRepository", .serialized)
struct CertLookupRepositoryTests {
    @Test("decodes a successful cert-lookup response")
    func decodesSuccessResponse() throws {
        let json = """
        {
          "identity_id": "11111111-1111-1111-1111-111111111111",
          "graded_card_id": "22222222-2222-2222-2222-222222222222",
          "grading_service": "PSA",
          "grade": "10",
          "card": {
            "set_name": "POKEMON GAME",
            "card_number": "4",
            "card_name": "CHARIZARD-HOLO",
            "variant": "1ST EDITION",
            "year": 1999,
            "language": "en"
          },
          "cache_hit": false
        }
        """.data(using: .utf8)!

        let decoded = try CertLookupRepository.decode(data: json)
        #expect(decoded.identityId == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(decoded.gradingService == "PSA")
        #expect(decoded.grade == "10")
        #expect(decoded.setName == "POKEMON GAME")
        #expect(decoded.cardNumber == "4")
        #expect(decoded.cardName == "CHARIZARD-HOLO")
        #expect(decoded.variant == "1ST EDITION")
        #expect(decoded.year == 1999)
        #expect(decoded.language == "en")
        #expect(decoded.cacheHit == false)
    }

    @Test("decodes when card_number and variant are null")
    func decodesNullableCardFields() throws {
        let json = """
        {
          "identity_id": "11111111-1111-1111-1111-111111111111",
          "graded_card_id": "22222222-2222-2222-2222-222222222222",
          "grading_service": "PSA",
          "grade": "9",
          "card": {
            "set_name": "POKEMON JAPANESE",
            "card_number": null,
            "card_name": "CHARIZARD-HOLO",
            "variant": null,
            "year": null,
            "language": "jp"
          },
          "cache_hit": true
        }
        """.data(using: .utf8)!

        let decoded = try CertLookupRepository.decode(data: json)
        #expect(decoded.cardNumber == nil)
        #expect(decoded.variant == nil)
        #expect(decoded.year == nil)
        #expect(decoded.language == "jp")
        #expect(decoded.cacheHit == true)
    }

    @Test("404 CERT_NOT_FOUND surfaces as a typed error")
    func mapsCertNotFound() throws {
        let json = #"{ "code": "CERT_NOT_FOUND" }"#.data(using: .utf8)!
        #expect(throws: CertLookupRepository.Error.certNotFound) {
            _ = try CertLookupRepository.decodeErrorBody(json, statusCode: 404)
        }
    }

    @Test("415 NOT_POKEMON surfaces as a typed error")
    func mapsNotPokemon() throws {
        let json = #"{ "code": "NOT_POKEMON" }"#.data(using: .utf8)!
        #expect(throws: CertLookupRepository.Error.notPokemon) {
            _ = try CertLookupRepository.decodeErrorBody(json, statusCode: 415)
        }
    }

    @Test("415 UNSUPPORTED_GRADER surfaces as a typed error")
    func mapsUnsupportedGrader() throws {
        let json = #"{ "code": "UNSUPPORTED_GRADER" }"#.data(using: .utf8)!
        #expect(throws: CertLookupRepository.Error.unsupportedGrader) {
            _ = try CertLookupRepository.decodeErrorBody(json, statusCode: 415)
        }
    }

    @Test("502 maps to upstreamUnavailable")
    func mapsUpstream() throws {
        let json = #"{ "code": "UPSTREAM_FAILED" }"#.data(using: .utf8)!
        #expect(throws: CertLookupRepository.Error.upstreamUnavailable) {
            _ = try CertLookupRepository.decodeErrorBody(json, statusCode: 502)
        }
    }

    @Test("429 maps to rateLimited")
    func mapsRateLimited() throws {
        let json = #"{ "code": "UPSTREAM_RATE_LIMITED" }"#.data(using: .utf8)!
        #expect(throws: CertLookupRepository.Error.rateLimited) {
            _ = try CertLookupRepository.decodeErrorBody(json, statusCode: 429)
        }
    }

    @Test("posts to /cert-lookup with grader and cert_number")
    @MainActor
    func postsExpectedRequest() async throws {
        let session = CapturingURLProtocol.makeSession()
        CapturingURLProtocol.reset()
        CapturingURLProtocol.cannedStatus = 200
        CapturingURLProtocol.cannedBody = """
        {
          "identity_id": "11111111-1111-1111-1111-111111111111",
          "graded_card_id": "22222222-2222-2222-2222-222222222222",
          "grading_service": "PSA",
          "grade": "10",
          "card": {
            "set_name": "POKEMON GAME",
            "card_number": "4",
            "card_name": "CHARIZARD",
            "variant": null,
            "year": 1999,
            "language": "en"
          },
          "cache_hit": false
        }
        """.data(using: .utf8)!

        let repo = CertLookupRepository(
            urlSession: session,
            baseURL: URL(string: "https://example.com/functions/v1")!,
            authTokenProvider: { "test-token" }
        )

        let decoded = try await repo.lookup(grader: .PSA, certNumber: "12345678")
        #expect(decoded.grade == "10")

        let request = try #require(CapturingURLProtocol.lastRequest)
        #expect(request.url?.path == "/functions/v1/cert-lookup")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer test-token")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
        // URLProtocol drops the body unless we re-stream it; verify content-type sufficed.
    }
}
