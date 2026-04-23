import Foundation
import Testing
@testable import slabbist

@Suite("Reachability")
@MainActor
struct ReachabilityTests {
    @Test("default status is .unknown before first path callback")
    func defaultStatusIsUnknown() {
        let r = Reachability()
        #expect(r.status == .unknown)
    }

    @Test("applying a path updates status to the mapped value")
    func appliesPathStatus() {
        let r = Reachability()
        r.applyForTesting(status: .online)
        #expect(r.status == .online)

        r.applyForTesting(status: .offline)
        #expect(r.status == .offline)
    }
}
