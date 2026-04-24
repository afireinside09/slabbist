import Foundation
import Testing
import CoreGraphics
@testable import slabbist

@Suite("CenteringMeasurement")
struct CenteringMeasurementTests {
    @Test("perfectly centered card → 50/50 ratios on both axes")
    func perfectlyCentered() {
        let image = CGRect(x: 0, y: 0, width: 1000, height: 1400)
        let card = CGRect(x: 100, y: 140, width: 800, height: 1120)
        let r = CenteringMeasurement.measure(cardRect: card, in: image)
        #expect(abs(r.left - 0.5) < 0.001)
        #expect(abs(r.right - 0.5) < 0.001)
        #expect(abs(r.top - 0.5) < 0.001)
        #expect(abs(r.bottom - 0.5) < 0.001)
    }

    @Test("60/40 horizontal off-center → left ratio 0.6")
    func horizontalSkew() {
        let image = CGRect(x: 0, y: 0, width: 1000, height: 1400)
        // Card shifted right: left whitespace = 120, right whitespace = 80
        let card = CGRect(x: 120, y: 140, width: 800, height: 1120)
        let r = CenteringMeasurement.measure(cardRect: card, in: image)
        #expect(abs(r.left - 0.6) < 0.001)
        #expect(abs(r.right - 0.4) < 0.001)
    }

    @Test("zero whitespace on one side returns 1.0/0.0")
    func cardTouchesEdge() {
        let image = CGRect(x: 0, y: 0, width: 1000, height: 1400)
        let card = CGRect(x: 0, y: 140, width: 900, height: 1120)
        let r = CenteringMeasurement.measure(cardRect: card, in: image)
        #expect(r.left == 0.0)
        #expect(r.right == 1.0)
    }
}
