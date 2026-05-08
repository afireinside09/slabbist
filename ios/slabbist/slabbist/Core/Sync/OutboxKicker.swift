import Foundation

/// MainActor-isolated entry point producers and lifecycle hooks call to
/// nudge the drainer. Owns no state — just hops onto a detached Task and
/// invokes the supplied closure (typically `await drainer.kick()`).
///
/// Producers stay decoupled from the actor: they don't `await`, don't
/// import the actor type, and don't care that the drainer is doing work
/// on a background thread.
@MainActor
final class OutboxKicker {
    private let action: @Sendable () async -> Void

    init(action: @escaping @Sendable () async -> Void) {
        self.action = action
    }

    /// Fire-and-forget. Safe to call from any MainActor context.
    func kick() {
        let action = self.action
        Task.detached(priority: .utility) {
            await action()
        }
    }
}
