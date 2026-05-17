import Foundation
import Observation

/// MainActor-isolated entry point producers and lifecycle hooks call to
/// nudge the drainer. Owns no state — just hops onto a Task and invokes
/// the supplied closure (typically `await drainer.kick()`).
///
/// Producers stay decoupled from the actor: they don't `await`, don't
/// import the actor type, and don't care that the drainer is doing work
/// on a background thread.
///
/// `@Observable` is required so `SlabbistApp` can inject it via
/// `.environment(kicker)` and views can read it without a wrapper.
@MainActor
@Observable
final class OutboxKicker {
    private let action: @Sendable () async -> Void

    init(action: @escaping @Sendable () async -> Void) {
        self.action = action
    }

    /// Fire-and-forget. Safe to call from any MainActor context.
    ///
    /// A4: kicks come from user-driven producers (save in OfferReview,
    /// scenePhase change, reachability transition), so the spawned task
    /// runs at `.userInitiated` priority. The previous `.utility` form
    /// pinned drains to background, which made the SyncStatusPill lag
    /// behind active user actions. We keep the task detached so the
    /// producer's MainActor isn't blocked while the drain runs — the
    /// drainer is an actor and already manages its own isolation, and
    /// the post-drain `kickPending` re-pass coalesces concurrent kicks
    /// safely (see `OutboxDrainer.drainOnce`).
    func kick() {
        let action = self.action
        Task.detached(priority: .userInitiated) {
            await action()
        }
    }
}
