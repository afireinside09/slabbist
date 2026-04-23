import Foundation
import Supabase

/// A single process-wide Supabase client. Holds the auth session and
/// exposes the Postgrest + Auth surfaces we need app-wide.
///
/// Marked `nonisolated` so the singleton can be resolved from any
/// actor (repositories, services, background tasks) without having
/// to hop to MainActor. The underlying `SupabaseClient` is `Sendable`.
///
/// The client uses the tuned `URLSession` from `SupabaseHTTP.shared`
/// (waitsForConnectivity, bounded timeouts, protocol-cache ETag
/// handshake). Tests that need to intercept requests build their own
/// `SupabaseClient` via `AppSupabase.make(session:)`.
nonisolated final class AppSupabase: Sendable {
    static let shared = AppSupabase()

    let client: SupabaseClient

    private init() {
        self.client = Self.make(session: SupabaseHTTP.shared)
    }

    /// Build a `SupabaseClient` against the app's resolved environment
    /// but with a caller-supplied `URLSession`. Used by tests to inject
    /// `URLProtocol` interceptors.
    static func make(session: URLSession) -> SupabaseClient {
        let options = SupabaseClientOptions(
            global: SupabaseClientOptions.GlobalOptions(session: session)
        )
        return SupabaseClient(
            supabaseURL: AppEnvironment.supabaseURL,
            supabaseKey: AppEnvironment.supabaseKey,
            options: options
        )
    }
}
