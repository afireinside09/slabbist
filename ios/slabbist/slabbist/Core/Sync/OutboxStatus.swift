import Foundation
import Observation

/// Disambiguates the auth-pause copy. `.reconnecting` is the in-flight
/// token-refresh state (no user action needed); `.signedOut` means the
/// session genuinely expired and the user has to sign in.
nonisolated enum AuthPauseState: Sendable, Equatable {
    case reconnecting
    case signedOut
}

/// A2: thin bridge the `SyncStatusPill` uses to drive the failures sheet
/// without importing `OutboxDrainer` directly. The host builds it once
/// in `SlabbistApp.init` and injects via environment.
///
/// Captures `@Sendable` async closures so the implementation can hop
/// onto the drainer actor without leaking `OutboxDrainer` into the
/// SwiftUI surface or making the view ` MainActor`-coupled to the actor.
///
/// `@Observable` is required so SwiftUI's `@Environment` injection
/// accepts it. The closures themselves don't change after construction,
/// so the synthesized observation is harmless.
@MainActor
@Observable
final class OutboxFailureBridge {
    let load: @Sendable () async -> [OutboxDrainer.FailedRowSnapshot]
    let retry: @Sendable (UUID) async -> Void
    let discard: @Sendable (UUID) async -> Void

    init(
        load: @escaping @Sendable () async -> [OutboxDrainer.FailedRowSnapshot],
        retry: @escaping @Sendable (UUID) async -> Void,
        discard: @escaping @Sendable (UUID) async -> Void
    ) {
        self.load = load
        self.retry = retry
        self.discard = discard
    }
}

/// MainActor-isolated, SwiftUI-bindable surface for the outbox drainer.
/// The drainer publishes updates here; views (the sync status pill) read.
@MainActor
@Observable
final class OutboxStatus {
    private(set) var pendingCount: Int = 0
    /// Number of outbox rows in `.failed` state. The pill surfaces this
    /// distinctly from `pendingCount` so failures can never silently
    /// accumulate behind a "0 pending → hidden" pill.
    private(set) var failedCount: Int = 0
    private(set) var isDraining: Bool = false
    private(set) var isPaused: Bool = false
    /// Refines `isPaused` into UI-grade copy. Nil when not paused.
    private(set) var authState: AuthPauseState?
    private(set) var lastError: String?

    init() {}

    /// Merge update — pass only the fields that changed. `lastError` is
    /// owned by `setPaused` and only gets set/cleared via the auth-pause
    /// path; the drainer body uses `update` for routine pending/draining
    /// transitions.
    func update(
        pendingCount: Int? = nil,
        failedCount: Int? = nil,
        isDraining: Bool? = nil
    ) {
        if let pendingCount { self.pendingCount = pendingCount }
        if let failedCount { self.failedCount = failedCount }
        if let isDraining { self.isDraining = isDraining }
    }

    /// Auth pause flag. When `paused`, the pill switches to "Sign in to
    /// sync" copy and the drainer no-ops on `kick()`.
    func setPaused(_ paused: Bool, reason: String?, authState: AuthPauseState? = nil) {
        self.isPaused = paused
        self.lastError = reason
        // Clear the auth sub-state on unpause so the pill doesn't render
        // stale "Reconnecting…" copy after the session recovers.
        self.authState = paused ? authState : nil
    }
}
