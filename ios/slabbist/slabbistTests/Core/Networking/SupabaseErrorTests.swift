import Foundation
import Testing
import Supabase
@testable import slabbist

@Suite("SupabaseError.map")
struct SupabaseErrorTests {
    // MARK: - Postgrest

    @Test("maps PGRST116 to .notFound")
    func pgrst116() {
        let pg = PostgrestError(code: "PGRST116", message: "Results contain 0 rows")
        let mapped = SupabaseError.map(pg)
        if case .notFound = mapped { return }
        Issue.record("expected .notFound, got \(mapped)")
    }

    @Test("maps PGRST301 / PGRST302 to .unauthorized (JWT invalid / not authenticated)")
    func pgrstAuthCodes() {
        for code in ["PGRST301", "PGRST302"] {
            let pg = PostgrestError(code: code, message: "auth failure")
            let mapped = SupabaseError.map(pg)
            if case .unauthorized = mapped { continue }
            Issue.record("expected .unauthorized for \(code), got \(mapped)")
        }
    }

    @Test("maps PGRST303 and Postgres 42501 to .forbidden (RLS)")
    func forbiddenCodes() {
        for code in ["PGRST303", "42501"] {
            let pg = PostgrestError(code: code, message: "forbidden")
            let mapped = SupabaseError.map(pg)
            if case .forbidden = mapped { continue }
            Issue.record("expected .forbidden for \(code), got \(mapped)")
        }
    }

    @Test("23505 (unique violation) maps to .uniqueViolation, not generic .constraintViolation")
    func uniqueViolationMapping() {
        let pg = PostgrestError(
            code: "23505",
            message: "duplicate key value violates unique constraint \"lots_pkey\""
        )
        let mapped = SupabaseError.map(pg)
        if case .uniqueViolation = mapped { return }
        Issue.record("expected .uniqueViolation, got \(mapped)")
    }

    @Test("23503 (FK violation) still maps to .constraintViolation")
    func fkViolationMapping() {
        let pg = PostgrestError(code: "23503", message: "foreign key violation")
        let mapped = SupabaseError.map(pg)
        if case .constraintViolation = mapped { return }
        Issue.record("expected .constraintViolation, got \(mapped)")
    }

    @Test("maps remaining 23xxx Postgres codes to .constraintViolation")
    func constraintCodes() {
        for code in ["23502", "23503", "23514"] {
            let pg = PostgrestError(code: code, message: "boom")
            let mapped = SupabaseError.map(pg)
            guard case let .constraintViolation(message, _) = mapped else {
                Issue.record("expected .constraintViolation for \(code), got \(mapped)")
                continue
            }
            #expect(message == "boom")
        }
    }

    @Test("maps unknown PostgrestError code to .transport")
    func unknownPostgrest() {
        let pg = PostgrestError(code: "99999", message: "unknown")
        let mapped = SupabaseError.map(pg)
        if case .transport = mapped { return }
        Issue.record("expected .transport, got \(mapped)")
    }

    // MARK: - Auth

    @Test("maps AuthError.sessionMissing to .unauthorized")
    func authSessionMissing() {
        let mapped = SupabaseError.map(AuthError.sessionMissing)
        if case .unauthorized = mapped { return }
        Issue.record("expected .unauthorized, got \(mapped)")
    }

    @Test("maps auth api errors with auth-invalid codes to .unauthorized")
    func authAPIUnauthorized() throws {
        let unauthorizedCodes: [ErrorCode] = [
            .noAuthorization, .badJWT, .invalidJWT,
            .sessionNotFound, .sessionExpired,
            .refreshTokenNotFound, .refreshTokenAlreadyUsed
        ]
        let dummyResponse = try #require(HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        ))

        for code in unauthorizedCodes {
            let auth = AuthError.api(
                message: "not allowed",
                errorCode: code,
                underlyingData: Data(),
                underlyingResponse: dummyResponse
            )
            let mapped = SupabaseError.map(auth)
            if case .unauthorized = mapped { continue }
            Issue.record("expected .unauthorized for \(code.rawValue), got \(mapped)")
        }
    }

    @Test("maps auth userNotFound/identityNotFound to .notFound")
    func authUserNotFound() throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        ))
        for code in [ErrorCode.userNotFound, .identityNotFound] {
            let auth = AuthError.api(
                message: "no user",
                errorCode: code,
                underlyingData: Data(),
                underlyingResponse: response
            )
            let mapped = SupabaseError.map(auth)
            if case .notFound = mapped { continue }
            Issue.record("expected .notFound for \(code.rawValue), got \(mapped)")
        }
    }

    @Test("maps non-auth AuthError cases to .transport")
    func authOtherToTransport() {
        let cases: [AuthError] = [
            .weakPassword(message: "too short", reasons: []),
            .implicitGrantRedirect(message: "bad url"),
            .pkceGrantCodeExchange(message: "bad code")
        ]
        for auth in cases {
            let mapped = SupabaseError.map(auth)
            if case .transport = mapped { continue }
            Issue.record("expected .transport for \(auth), got \(mapped)")
        }
    }

    // MARK: - Fallback & idempotence

    @Test("unknown errors become .transport")
    func unknownFallback() {
        struct BogusError: Error {}
        let mapped = SupabaseError.map(BogusError())
        if case .transport = mapped { return }
        Issue.record("expected .transport, got \(mapped)")
    }

    @Test("mapping a SupabaseError is idempotent")
    func idempotent() {
        let already: SupabaseError = .notFound(table: "lots", id: "abc")
        let mapped = SupabaseError.map(already)
        guard case let .notFound(table, id) = mapped else {
            Issue.record("expected passthrough .notFound, got \(mapped)")
            return
        }
        #expect(table == "lots")
        #expect(id == "abc")
    }
}
