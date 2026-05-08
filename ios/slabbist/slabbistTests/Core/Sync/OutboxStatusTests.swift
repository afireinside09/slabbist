import Foundation
import Testing
@testable import slabbist

@Suite("OutboxStatus")
@MainActor
struct OutboxStatusTests {
    @Test("defaults to empty / not draining / not paused")
    func defaults() {
        let s = OutboxStatus()
        #expect(s.pendingCount == 0)
        #expect(s.isDraining == false)
        #expect(s.isPaused == false)
        #expect(s.lastError == nil)
    }

    @Test("update merges new values")
    func update() {
        let s = OutboxStatus()
        s.update(pendingCount: 3, isDraining: true)
        #expect(s.pendingCount == 3)
        #expect(s.isDraining == true)
        #expect(s.isPaused == false)
        s.update(isDraining: false, lastError: "boom")
        #expect(s.pendingCount == 3) // unchanged
        #expect(s.isDraining == false)
        #expect(s.lastError == "boom")
    }

    @Test("setPaused flips both flags atomically")
    func pause() {
        let s = OutboxStatus()
        s.setPaused(true, reason: "Sign in to sync")
        #expect(s.isPaused == true)
        #expect(s.lastError == "Sign in to sync")
        s.setPaused(false, reason: nil)
        #expect(s.isPaused == false)
        #expect(s.lastError == nil)
    }
}
