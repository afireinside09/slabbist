import Foundation
import Testing
import CoreGraphics
import UIKit
@testable import slabbist

@Suite("CaptureMetrics")
struct CaptureMetricsTests {
    @Test("a solid white image reads as fully blown glare")
    func whiteIsGlare() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100), color: .white)
        let m = CaptureMetrics.measure(image: image, cardRect: nil)
        #expect(m.glareRatio > 0.9)
    }

    @Test("a mid-gray image reads as no glare")
    func grayNoGlare() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100),
                               color: UIColor(white: 0.5, alpha: 1))
        let m = CaptureMetrics.measure(image: image, cardRect: nil)
        #expect(m.glareRatio < 0.01)
    }

    @Test("a featureless image reads as blurry (low blur score)")
    func flatIsBlurry() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100),
                               color: UIColor(white: 0.5, alpha: 1))
        let m = CaptureMetrics.measure(image: image, cardRect: nil)
        #expect(m.blurScore < 100)
    }

    private func solidImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
