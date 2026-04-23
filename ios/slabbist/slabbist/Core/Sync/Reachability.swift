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

    init(start: Bool = false) {
        if start { self.start() }
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let next: ReachabilityStatus = (path.status == .satisfied) ? .online : .offline
            Task { @MainActor [weak self] in
                self?.status = next
            }
        }
        monitor.start(queue: queue)
    }

    /// Test seam — feeds a status directly without spinning up NWPathMonitor.
    /// MainActor-isolated to match production; race between background monitor
    /// writes and this helper is no longer possible because both paths hop to
    /// MainActor.
    func applyForTesting(status: ReachabilityStatus) {
        self.status = status
    }
}
