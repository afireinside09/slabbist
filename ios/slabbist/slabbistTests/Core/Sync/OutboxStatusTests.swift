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

    @Test("update sets pendingCount and isDraining")
    func updateSetsCountAndDraining() {
        let s = OutboxStatus()
        s.update(pendingCount: 3, isDraining: true)
        #expect(s.pendingCount == 3)
        #expect(s.isDraining == true)
        #expect(s.isPaused == false)
        #expect(s.lastError == nil)
    }

    @Test("update merges without clobbering unchanged fields")
    func updateMergesWithoutClobbering() {
        let s = OutboxStatus()
        s.update(pendingCount: 3, isDraining: true)

        // Subsequent update touches only isDraining; pendingCount must persist,
        // and lastError (set via setPaused) must not be touched.
        s.setPaused(true, reason: "Sign in to sync")
        s.update(isDraining: false)

        #expect(s.pendingCount == 3)        // preserved
        #expect(s.isDraining == false)      // updated
        #expect(s.isPaused == true)         // not touched
        #expect(s.lastError == "Sign in to sync") // not touched
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
