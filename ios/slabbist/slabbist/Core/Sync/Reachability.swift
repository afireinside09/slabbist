import Foundation
import Network
import Observation

enum ReachabilityStatus: Equatable {
    case unknown
    case online
    case offline
}

@MainActor
@Observable
final class Reachability {
    private(set) var status: ReachabilityStatus = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.slabbist.reachability")
    /// Debounce window for path updates. Cell↔WiFi handoffs and captive
    /// portal probes can flap online/offline within milliseconds; downstream
    /// consumers (eventually the outbox drainer) shouldn't thrash on the
    /// transient.
    private static let debounceMillis: Int = 500
    private var pendingApply: Task<Void, Never>?

    init(start: Bool = false) {
        if start { self.start() }
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let next: ReachabilityStatus = (path.status == .satisfied) ? .online : .offline
            Task { @MainActor [weak self] in
                self?.scheduleApply(next)
            }
        }
        monitor.start(queue: queue)
    }

    /// Test seam — feeds a status directly without spinning up NWPathMonitor.
    /// MainActor-isolated to match production; race between background monitor
    /// writes and this helper is no longer possible because both paths hop to
    /// MainActor.
    func applyForTesting(status: ReachabilityStatus) {
        pendingApply?.cancel()
        pendingApply = nil
        self.status = status
    }

    private func scheduleApply(_ next: ReachabilityStatus) {
        // Skip the debounce on the first transition out of `.unknown` — the
        // initial path read should propagate immediately so consumers don't
        // sit in `.unknown` for half a second after launch.
        if status == .unknown {
            self.status = next
            return
        }
        if status == next {
            // Already there — no need to flap.
            pendingApply?.cancel()
            pendingApply = nil
            return
        }
        pendingApply?.cancel()
        pendingApply = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.debounceMillis) * 1_000_000)
            guard let self, !Task.isCancelled else { return }
            self.status = next
            self.pendingApply = nil
        }
    }
}
