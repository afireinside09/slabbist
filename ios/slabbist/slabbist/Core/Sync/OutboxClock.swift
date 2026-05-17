import Foundation

/// Small clock seam so the drainer's time-based decisions (next-attempt
/// gate, backoff comparisons) can be deterministically driven by tests
/// without reaching for `Date()` directly. Production code injects
/// `SystemClock`; tests inject a `TestClock` that advances on demand.
public protocol OutboxClock: Sendable {
    nonisolated func current() -> Date
}

public nonisolated struct SystemClock: OutboxClock {
    public init() {}
    public func current() -> Date { Date() }
}
