import Foundation
import Testing
import CoreGraphics
@testable import slabbist

@Suite("GlareMetric")
struct GlareMetricTests {
    @Test("fully blown buffer is ratio 1.0")
    func allBlown() {
        let buf = GrayscaleBuffer(width: 4, height: 4, pixels: [UInt8](repeating: 255, count: 16))
        #expect(GlareMetric.overexposedRatio(buf, in: nil) == 1.0)
    }

    @Test("pixels at 250 are not counted (threshold is > 250)")
    func boundaryNotBlown() {
        let buf = GrayscaleBuffer(width: 4, height: 4, pixels: [UInt8](repeating: 250, count: 16))
        #expect(GlareMetric.overexposedRatio(buf, in: nil) == 0.0)
    }

    @Test("only counts pixels inside the normalized rect")
    func respectsRect() {
        // Left half blown (255), right half dark (10).
        var pixels = [UInt8]()
        for _ in 0..<4 { pixels += [255, 255, 10, 10] } // 4x4
        let buf = GrayscaleBuffer(width: 4, height: 4, pixels: pixels)
        let leftHalf = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        let rightHalf = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        #expect(GlareMetric.overexposedRatio(buf, in: leftHalf) == 1.0)
        #expect(GlareMetric.overexposedRatio(buf, in: rightHalf) == 0.0)
    }
}
