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

    /// Merge update — pass only the fields that changed. `lastError` is
    /// owned by `setPaused` and only gets set/cleared via the auth-pause
    /// path; the drainer body uses `update` for routine pending/draining
    /// transitions.
    func update(
        pendingCount: Int? = nil,
        isDraining: Bool? = nil
    ) {
        if let pendingCount { self.pendingCount = pendingCount }
        if let isDraining { self.isDraining = isDraining }
    }

    /// Auth pause flag. When `paused`, the pill switches to "Sign in to
    /// sync" copy and the drainer no-ops on `kick()`.
    func setPaused(_ paused: Bool, reason: String?) {
        self.isPaused = paused
        self.lastError = reason
    }
}
