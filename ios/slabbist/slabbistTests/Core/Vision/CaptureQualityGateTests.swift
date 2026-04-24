import Foundation
import Testing
import CoreGraphics
import UIKit
@testable import slabbist

@Suite("CaptureQualityGate")
struct CaptureQualityGateTests {
    @Test("rejects below minimum resolution")
    func rejectsLowRes() {
        let image = solidImage(size: CGSize(width: 800, height: 1100), color: .white)
        let result = CaptureQualityGate().evaluate(
            image: image,
            cardDetection: CardRectangleDetector.Result(
                boundingBox: CGRect(x: 50, y: 50, width: 700, height: 1000),
                confidence: 0.95
            ),
            blurScore: 200,
            glareRatio: 0.001
        )
        if case .rejected(let reason) = result {
            #expect(reason.lowercased().contains("resolution"))
        } else {
            Issue.record("expected rejection")
        }
    }

    @Test("rejects when card detection is missing")
    func rejectsNoCard() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100), color: .white)
        let result = CaptureQualityGate().evaluate(
            image: image,
            cardDetection: nil,
            blurScore: 200,
            glareRatio: 0.001
        )
        if case .rejected(let reason) = result {
            #expect(reason.lowercased().contains("card"))
        } else {
            Issue.record("expected rejection")
        }
    }

    @Test("rejects when blur score below threshold")
    func rejectsBlurry() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100), color: .white)
        let result = CaptureQualityGate().evaluate(
            image: image,
            cardDetection: CardRectangleDetector.Result(
                boundingBox: CGRect(x: 100, y: 200, width: 1300, height: 1700),
                confidence: 0.95
            ),
            blurScore: 50,
            glareRatio: 0.001
        )
        if case .rejected(let reason) = result {
            #expect(reason.lowercased().contains("blur"))
        } else {
            Issue.record("expected rejection")
        }
    }

    @Test("rejects when glare ratio above threshold")
    func rejectsGlare() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100), color: .white)
        let result = CaptureQualityGate().evaluate(
            image: image,
            cardDetection: CardRectangleDetector.Result(
                boundingBox: CGRect(x: 100, y: 200, width: 1300, height: 1700),
                confidence: 0.95
            ),
            blurScore: 200,
            glareRatio: 0.05
        )
        if case .rejected(let reason) = result {
            #expect(reason.lowercased().contains("glare"))
        } else {
            Issue.record("expected rejection")
        }
    }

    @Test("accepts when all four checks pass")
    func acceptsClean() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100), color: .white)
        let det = CardRectangleDetector.Result(
            boundingBox: CGRect(x: 100, y: 200, width: 1300, height: 1700),
            confidence: 0.95
        )
        let result = CaptureQualityGate().evaluate(
            image: image,
            cardDetection: det,
            blurScore: 200,
            glareRatio: 0.001
        )
        if case .ok = result {} else { Issue.record("expected ok") }
    }

    private func solidImage(size: CGSize, color: UIColor) -> UIImage {
        // Force scale=1 so size.width/height == pixel width/height, matching
        // what the implementation computes via image.size * image.scale.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
