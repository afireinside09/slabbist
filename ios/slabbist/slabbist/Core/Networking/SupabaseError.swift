import Foundation
import Supabase

/// Error surface exposed by our Supabase data layer. Wraps the concrete
/// errors thrown by `supabase-swift` so call sites (view models,
/// services, outbox worker) can `catch SupabaseError` instead of
/// spelunking through Postgrest / GoTrue internals.
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
        case let .transport(error):
            return "Transport error: \(error.localizedDescription)"
        }
    }

    /// Map an arbitrary error (typically a Postgrest / AuthError) to a
    /// `SupabaseError`. Unknown shapes fall through to `.transport`.
    static func map(_ error: Error) -> SupabaseError {
        if let already = error as? SupabaseError { return already }

        // Postgrest surfaces HTTP status codes in its error type.
        if let pg = error as? PostgrestError {
            switch pg.code {
            case "PGRST116":
                return .notFound(table: "", id: nil)
            case "23505":
                return .constraintViolation(message: pg.message, underlying: pg)
            case "42501":
                return .forbidden(underlying: pg)
            default:
                return .transport(underlying: pg)
            }
        }

        if let auth = error as? AuthError {
            // Any auth-shaped error where the session is missing / expired.
            let message = auth.localizedDescription.lowercased()
            if message.contains("not authenticated") || message.contains("missing session") {
                return .unauthorized
            }
            return .transport(underlying: auth)
        }

        return .transport(underlying: error)
    }
}
