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
}

private final class BundleAnchor {}
