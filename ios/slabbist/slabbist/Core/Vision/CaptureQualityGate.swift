import Foundation
import UIKit

/// Pre-flight checks applied to a captured frame. The capture button stays
/// disabled until `evaluate(...)` returns `.ok`. A failed check returns a
/// human-readable reason that the UI surfaces to the user.
struct CaptureQualityGate {
    struct Thresholds {
        var minWidth: Int = 1500
        var minHeight: Int = 2100
        var minBlurScore: Double = 100
        var maxGlareRatio: Double = 0.02
    }

    enum Outcome: Equatable {
        case ok
        case rejected(reason: String)
    }

    let thresholds: Thresholds

    init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    func evaluate(
        image: UIImage,
        cardDetection: CardRectangleDetector.Result?,
        blurScore: Double,
        glareRatio: Double
    ) -> Outcome {
        let w = Int(image.size.width * image.scale)
        let h = Int(image.size.height * image.scale)
        if w < thresholds.minWidth || h < thresholds.minHeight {
            return .rejected(reason: "Photo resolution too low — move closer or use better light.")
        }
        if cardDetection == nil {
            return .rejected(reason: "Card not detected — frame the whole card with a contrasting background.")
        }
        if blurScore < thresholds.minBlurScore {
            return .rejected(reason: "Too blurry — hold steady and let the camera focus.")
        }
        if glareRatio > thresholds.maxGlareRatio {
            return .rejected(reason: "Too much glare — angle the card away from direct light.")
        }
        return .ok
    }
}
