import Foundation

/// Test-only `URLProtocol` that captures the outgoing request and
/// returns a canned response. Registered on a `URLSessionConfiguration`
/// via `protocolClasses` and then fed into a `SupabaseClient` through
/// `SupabaseClientOptions.GlobalOptions.session`, it lets tests assert
/// on the exact URL / headers / body the Supabase SDK emits without
/// touching the network.
///
/// Not thread-safe across concurrent tests — serialize callers via
/// `reset()` at the start of each test case.
final class CapturingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var cannedBody: Data = Data("[]".utf8)
    nonisolated(unsafe) static var cannedStatus: Int = 200
    nonisolated(unsafe) static var cannedHeaders: [String: String] = [
        "Content-Type": "application/json",
        "Content-Range": "0-0/0"
    ]

    static func reset() {
        lastRequest = nil
        cannedBody = Data("[]".utf8)
        cannedStatus = 200
        cannedHeaders = [
            "Content-Type": "application/json",
            "Content-Range": "0-0/0"
        ]
    }

    /// Build a `URLSession` that routes every request through this
    /// protocol. Ephemeral config — no caching, no cookies.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.cannedStatus,
            httpVersion: "HTTP/1.1",
            headerFields: Self.cannedHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.cannedBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
