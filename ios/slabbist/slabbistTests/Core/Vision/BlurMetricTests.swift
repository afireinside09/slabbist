import Foundation
import Testing
@testable import slabbist

@Suite("BlurMetric")
struct BlurMetricTests {
    @Test("flat buffer scores ~0 (below sharp threshold)")
    func flatIsBlurry() {
        let buf = GrayscaleBuffer(width: 8, height: 8, pixels: [UInt8](repeating: 128, count: 64))
        #expect(BlurMetric.laplacianVariance(buf) < 100)
    }

    @Test("checkerboard scores high (above sharp threshold)")
    func checkerboardIsSharp() {
        var pixels = [UInt8](); pixels.reserveCapacity(64)
        for y in 0..<8 { for x in 0..<8 { pixels.append((x + y) % 2 == 0 ? 0 : 255) } }
        let buf = GrayscaleBuffer(width: 8, height: 8, pixels: pixels)
        #expect(BlurMetric.laplacianVariance(buf) > 100)
    }

    @Test("buffers smaller than the kernel score 0")
    func tooSmall() {
        let buf = GrayscaleBuffer(width: 2, height: 2, pixels: [0, 255, 255, 0])
        #expect(BlurMetric.laplacianVariance(buf) == 0)
    }
}
