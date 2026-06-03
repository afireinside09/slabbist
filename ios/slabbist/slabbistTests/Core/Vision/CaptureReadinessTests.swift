import Foundation
import Testing
@testable import slabbist

@Suite("CaptureReadiness")
struct CaptureReadinessTests {
    @Test("ready only when all flags pass")
    func readyAllTrue() {
        let r = CaptureReadiness(cardDetected: true, sharp: true, glareOK: true, steady: true)
        #expect(r.isReady == true)
        #expect(r.message == nil)
    }

    @Test("message prioritizes card detection over everything else")
    func messagePriority() {
        let r = CaptureReadiness(cardDetected: false, sharp: false, glareOK: false, steady: false)
        #expect(r.isReady == false)
        #expect(r.message?.lowercased().contains("card") == true)
    }

    @Test("blur message wins once a card is detected")
    func blurMessage() {
        let r = CaptureReadiness(cardDetected: true, sharp: false, glareOK: true, steady: true)
        #expect(r.message?.lowercased().contains("blur") == true)
    }

    @Test("steady is the lowest-priority message")
    func steadyMessage() {
        let r = CaptureReadiness(cardDetected: true, sharp: true, glareOK: true, steady: false)
        #expect(r.message?.lowercased().contains("still") == true)
    }
}
