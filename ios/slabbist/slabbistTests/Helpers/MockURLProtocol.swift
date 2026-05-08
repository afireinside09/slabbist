import Foundation

/// `URLProtocol` subclass for stubbing `URLSession` requests in tests.
///
/// Usage:
/// ```swift
/// MockURLProtocol.reset()
/// MockURLProtocol.requestHandler = { request in
///     let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
///     return (response, jsonData)
/// }
/// let session = MockURLProtocol.session()
/// ```
///
/// Captured requests live in `capturedRequests`. The intercept is global to
/// the `URLSession` returned by `session()` because `protocolClasses` is a
/// process-wide singleton — call `reset()` between tests to keep state clean.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    /// Closure invoked for every request. The default throws `URLError(.badURL)`
    /// so a forgotten test setup fails loud rather than silently returning empty.
    nonisolated(unsafe) static var requestHandler: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data?) = { _ in
        throw URLError(.badURL)
    }

    /// Every request that flows through the mock, in order. Useful for
    /// asserting de-dup behaviour ("exactly one network call").
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    private static let lock = NSLock()

    /// Resets `capturedRequests` and reinstalls the default-throwing handler.
    /// Call this in each test's setup to avoid cross-test contamination.
    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        capturedRequests = []
        requestHandler = { _ in throw URLError(.badURL) }
    }

    /// Returns a `URLSession` configured to route all requests through this
    /// mock. Each test should grab a fresh session; the underlying
    /// `URLProtocol` registry is process-wide.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(request)
        let handler = Self.requestHandler
        Self.lock.unlock()

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
