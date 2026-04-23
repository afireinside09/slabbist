import Foundation
import UIKit
import Vision

/// Wraps `VNDetectRectanglesRequest` with thresholds tuned for trading cards.
/// Returns the highest-confidence rectangle whose aspect ratio falls in the
/// trading-card range (0.6–0.85). Coordinates are in the image's pixel space,
/// origin top-left.
struct CardRectangleDetector {
    struct Result: Equatable {
        var boundingBox: CGRect    // pixel-space, origin top-left
        var confidence: Float
    }

    func detect(in image: UIImage) async throws -> Result? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.6
        request.maximumAspectRatio = 0.85
        request.minimumConfidence = 0.85
        request.minimumSize = 0.4   // at least 40% of the frame
        request.maximumObservations = 4

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])

        guard let best = (request.results ?? []).max(by: { $0.confidence < $1.confidence }) else {
            return nil
        }

        // Vision returns normalized coords with origin bottom-left; flip to top-left pixel space.
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let bb = best.boundingBox
        let pixelRect = CGRect(
            x: bb.minX * w,
            y: (1 - bb.maxY) * h,
            width: bb.width * w,
            height: bb.height * h
        )
        return Result(boundingBox: pixelRect, confidence: best.confidence)
    }
}
