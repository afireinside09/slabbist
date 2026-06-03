import Foundation
import Testing
import CoreGraphics
@testable import slabbist

@Suite("SteadinessTracker")
struct SteadinessTrackerTests {
    @Test("not steady before reaching capacity")
    func needsFullWindow() {
        var t = SteadinessTracker(capacity: 5, maxVariance: 0.0004)
        for _ in 0..<3 { t.push(CGPoint(x: 0.5, y: 0.5)) }
        #expect(t.isSteady == false)
    }

    @Test("steady when the framing barely moves")
    func steadyWhenStill() {
        var t = SteadinessTracker(capacity: 5, maxVariance: 0.0004)
        for _ in 0..<5 { t.push(CGPoint(x: 0.5, y: 0.5)) }
        #expect(t.isSteady == true)
    }

    @Test("not steady when the framing jumps around")
    func unsteadyWhenJittery() {
        var t = SteadinessTracker(capacity: 5, maxVariance: 0.0004)
        let pts = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9),
                   CGPoint(x: 0.1, y: 0.9), CGPoint(x: 0.9, y: 0.1),
                   CGPoint(x: 0.5, y: 0.5)]
        pts.forEach { t.push($0) }
        #expect(t.isSteady == false)
    }

    @Test("reset clears the window")
    func resetClears() {
        var t = SteadinessTracker(capacity: 5, maxVariance: 0.0004)
        for _ in 0..<5 { t.push(CGPoint(x: 0.5, y: 0.5)) }
        t.reset()
        #expect(t.isSteady == false)
    }
}
