import Foundation
import Supabase

/// Error surface exposed by our Supabase data layer. Wraps the
/// concrete errors thrown by `supabase-swift` so call sites (view
/// models, services, outbox worker) can `catch SupabaseError` instead
/// of spelunking through Postgrest / GoTrue internals.
///
/// The underlying SDK error is retained via `underlying` for logging
/// and debugging.
nonisolated enum SupabaseError: Error, CustomStringConvertible {
    /// No row matched a `single()` / `find` query.
    case notFound(table: String, id: String?)
    /// The caller is not authenticated (or the session expired).
    case unauthorized
    /// Row-Level Security rejected the operation.
    case forbidden(underlying: Error)
    /// Uniqueness / FK / check constraint violated.
    case constraintViolation(message: String, underlying: Error)
    /// Specifically a unique-constraint violation (PostgreSQL SQLSTATE
    /// 23505). Broken out from the generic `.constraintViolation` because
    /// the outbox drainer treats it as idempotent success on inserts —
    /// the row already exists, so the previous attempt landed.
    case uniqueViolation(message: String, underlying: Error)
    /// Network / transport / decoding problem that isn't specifically
    /// classified above.
    case transport(underlying: Error)

    var description: String {
        switch self {
        case let .notFound(table, id):
            return "Not found in \(table)\(id.map { " (id=\($0))" } ?? "")"
        case .unauthorized:
            return "Unauthorized — no active Supabase session"
        case let .forbidden(error):
            return "Forbidden by RLS: \(error.localizedDescription)"
        case let .constraintViolation(message, _):
            return "Constraint violation: \(message)"
        case let .uniqueViolation(message, _):
            return "Unique constraint violation: \(message)"
        case let .transport(error):
            return "Transport error: \(error.localizedDescription)"
        }
    }

    /// Map an arbitrary error (typically a `PostgrestError` or
    /// `AuthError`) to a `SupabaseError`. Unknown shapes fall through
    /// to `.transport`. Idempotent — re-mapping a `SupabaseError`
    /// returns itself.
    static func map(_ error: Error) -> SupabaseError {
        if let already = error as? SupabaseError { return already }

        if let pg = error as? PostgrestError {
            return mapPostgrest(pg)
        }

        if let auth = error as? AuthError {
            return mapAuth(auth)
        }

        return .transport(underlying: error)
    }

    // MARK: - Postgrest

    private static func mapPostgrest(_ error: PostgrestError) -> SupabaseError {
        switch error.code {
        // PostgREST-level codes (PGRSTxxx).
        case "PGRST116":
            // "Results contain 0 rows" — thrown by `.single()` when
            // the filter matched no rows.
            return .notFound(table: "", id: nil)
        case "PGRST301", "PGRST302":
            // JWT expired / not authenticated.
            return .unauthorized
        case "PGRST303":
            return .forbidden(underlying: error)

        // Postgres SQLSTATE codes surfaced through PostgREST.
        case "23505":
            // unique_violation — idempotent-success candidate for the outbox drainer
            return .uniqueViolation(message: error.message, underlying: error)
        case "23502":
            // not_null_violation
            return .constraintViolation(message: error.message, underlying: error)
        case "23503":
            // foreign_key_violation
            return .constraintViolation(message: error.message, underlying: error)
        case "23514":
            // check_violation
            return .constraintViolation(message: error.message, underlying: error)
        case "42501":
            // insufficient_privilege — RLS rejection
            return .forbidden(underlying: error)

        default:
            return .transport(underlying: error)
        }
    }

    // MARK: - Auth

    private static func mapAuth(_ error: AuthError) -> SupabaseError {
        switch error {
        case .sessionMissing:
            return .unauthorized
        case let .api(_, errorCode, _, _):
            switch errorCode {
            case .noAuthorization, .badJWT, .invalidJWT,
                 .sessionNotFound, .sessionExpired,
                 .refreshTokenNotFound, .refreshTokenAlreadyUsed:
                return .unauthorized
            case .userNotFound, .identityNotFound:
                return .notFound(table: "auth.users", id: nil)
            default:
                return .transport(underlying: error)
            }
        default:
            return .transport(underlying: error)
        }
    }
}
