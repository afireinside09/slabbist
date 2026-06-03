import Foundation
import Testing
import CoreGraphics
import UIKit
@testable import slabbist

@Suite("CardRectangleDetector")
struct CardRectangleDetectorTests {
    @Test("detects a card on a contrasting background")
    func detectsCard() async throws {
        // PBXFileSystemSynchronizedRootGroup flattens resources to the bundle root,
        // so the fixture lives at the top level of the test bundle — no subdirectory.
        let url = Bundle(for: BundleAnchor.self).url(
            forResource: "centered_card",
            withExtension: "png"
        )
        guard let url else {
            Issue.record("missing fixture: GradingFixtures/centered_card.png")
            return
        }
        guard let image = UIImage(contentsOfFile: url.path) else {
            Issue.record("could not load fixture image")
            return
        }
        let result = try await CardRectangleDetector().detect(in: image)
        #expect(result != nil)
        if let result {
            // Capture scalars before #expect to avoid main-actor isolation warnings
            // that can surface with Swift Testing macro expansions on iOS 26 SDK.
            let conf = result.confidence
            let bb = result.boundingBox
            #expect(conf >= 0.85)
            let ar = bb.width / bb.height
            #expect(ar > 0.6 && ar < 0.85)
        }
    }

    @Test("sync detect returns nil for an image with no card-like rectangle")
    func syncDetectNoCard() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600), format: format)
            .image { ctx in UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 600)) }
        let cg = try #require(image.cgImage)
        #expect(CardRectangleDetector.detect(in: cg) == nil)
    }
}

private final class BundleAnchor {}
