import SwiftUI
import Observation
import UIKit

/// Backs the standalone "Measure centering" tool. Holds the imported image,
/// the Vision-seeded guides, and the confirmed result — all in memory, gone
/// on dismiss (v1 keeps this ephemeral; nothing is persisted).
@MainActor
@Observable
final class StandaloneCenteringModel {
    var importedImage: UIImage?
    var seedGuides: CenteringGuides = .centeredDefault
    var result: CenteringRatios?

    @ObservationIgnored private let detector = CardRectangleDetector()

    /// Take a picked image, orient it upright, and seed the eight guides from
    /// Vision (outer) + the inner-frame heuristic, falling back to a centered
    /// default when no card is detected (manual-first).
    func loadImage(_ image: UIImage) async {
        let upright = image.uprightCGImage().map { UIImage(cgImage: $0) } ?? image
        result = nil

        if let det = try? await detector.detect(in: upright) {
            let w = upright.size.width * upright.scale
            let h = upright.size.height * upright.scale
            if w > 0, h > 0 {
                let outer = CenteringGuides(
                    outerLeft: det.boundingBox.minX / w, innerLeft: det.boundingBox.minX / w,
                    innerRight: det.boundingBox.maxX / w, outerRight: det.boundingBox.maxX / w,
                    outerTop: det.boundingBox.minY / h, innerTop: det.boundingBox.minY / h,
                    innerBottom: det.boundingBox.maxY / h, outerBottom: det.boundingBox.maxY / h
                )
                seedGuides = InnerFrameDetector.bestGuess(outer: outer)
            } else {
                seedGuides = .centeredDefault
            }
        } else {
            seedGuides = .centeredDefault
        }

        importedImage = upright
    }

    func clear() {
        importedImage = nil
        seedGuides = .centeredDefault
        result = nil
    }
}
