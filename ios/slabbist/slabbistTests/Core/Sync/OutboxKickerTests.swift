import Foundation
import Testing
@testable import slabbist

@Suite("OutboxKicker")
@MainActor
struct OutboxKickerTests {
    @Test("kick() invokes the underlying closure")
    func kickInvokes() async {
        let counter = Counter()
        let kicker = OutboxKicker { await counter.increment() }
        kicker.kick()
        // Allow the detached task to schedule + run.
        try? await Task.sleep(nanoseconds: 50_000_000)
        await #expect(counter.value == 1)
    }

    @Test("multiple kicks each invoke the closure")
    func multipleKicks() async {
        let counter = Counter()
        let kicker = OutboxKicker { await counter.increment() }
        kicker.kick(); kicker.kick(); kicker.kick()
        try? await Task.sleep(nanoseconds: 100_000_000)
        await #expect(counter.value == 3)
    }
}

private actor Counter {
    var value: Int = 0
    func increment() { value += 1 }
}
