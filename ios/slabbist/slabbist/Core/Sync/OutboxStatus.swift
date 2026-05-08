import Foundation
import Observation

/// MainActor-isolated, SwiftUI-bindable surface for the outbox drainer.
/// The drainer publishes updates here; views (the sync status pill) read.
@MainActor
@Observable
final class OutboxStatus {
    private(set) var pendingCount: Int = 0
    private(set) var isDraining: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var lastError: String?

    init() {}

    /// Merge update — pass only the fields that changed.
    /// `lastError` is double-optional: pass `nil` to leave it untouched,
    /// pass `.some(nil)` to clear, pass `.some("...")` to set.
    func update(
        pendingCount: Int? = nil,
        isDraining: Bool? = nil,
        lastError: String?? = nil
    ) {
        if let pendingCount { self.pendingCount = pendingCount }
        if let isDraining { self.isDraining = isDraining }
        if case let .some(newValue) = lastError { self.lastError = newValue }
    }

    /// Auth pause flag. When `paused`, the pill switches to "Sign in to
    /// sync" copy and the drainer no-ops on `kick()`.
    func setPaused(_ paused: Bool, reason: String?) {
        self.isPaused = paused
        self.lastError = reason
    }
}
