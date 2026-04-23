import Foundation

/// Factory for the `URLSession` backing the Supabase client. Centralizes
/// network-layer policy so every Postgrest / Auth request gets the same
/// timeouts, caching, and connectivity behavior.
///
/// Tuning rationale:
/// - `waitsForConnectivity = true` — the scanner-on-the-shop-floor case:
///   wifi drops and comes back. With this set, requests queue instead of
///   failing instantly, so the outbox worker doesn't burn retries on a
///   transient blip.
/// - `timeoutIntervalForRequest = 20s` — interactive operations should
///   fail fast enough that UI can fall back; anything longer feels
///   broken. The outbox still retries, so individual write failures
///   aren't user-visible.
/// - `timeoutIntervalForResource = 60s` — allows large list responses
///   / slow tethered connections to finish.
/// - `requestCachePolicy = .useProtocolCachePolicy` + small in-memory
///   `URLCache` — lets Postgrest's `ETag` / `If-None-Match` handshake
///   return 304s for unchanged list queries. Disk cache is off because
///   Supabase responses usually carry row-level state we don't want
///   long-lived on disk.
/// - `httpMaximumConnectionsPerHost = 6` — default, documented here so
///   we know it's intentional. HTTP/2 multiplexes over a single
///   connection anyway; this caps parallel HTTP/1.1 fallbacks.
/// - HTTP/3 — iOS 15+ negotiates automatically when the peer advertises
///   it; no flag to flip.
nonisolated enum SupabaseHTTP {
    /// Four-megabyte in-memory response cache. Memory-only (capacity
    /// arg) — per the rationale above.
    private static let sharedCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0)

    /// Build a configured session. `protocolClasses` lets tests inject
    /// `URLProtocol` subclasses to intercept requests without touching
    /// the network.
    static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = sharedCache
        if let protocolClasses {
            config.protocolClasses = protocolClasses + (config.protocolClasses ?? [])
        }
        return URLSession(configuration: config)
    }

    /// The session shared by the app-wide `AppSupabase` singleton.
    static let shared: URLSession = makeSession()
}
