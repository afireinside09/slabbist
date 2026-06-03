import AVFoundation
import CoreImage
import CoreGraphics
import UIKit

/// Throttled per-frame capture-quality analysis on the camera sample stream.
/// Created and used on the camera sample queue; `@unchecked Sendable` because
/// all mutable state is touched only from that single serial queue. Publishes
/// a `CaptureReadiness` via `onReadiness` (the caller hops to MainActor).
final class LiveReadinessAnalyzer: @unchecked Sendable {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let gate = CaptureQualityGate()
    private var steadiness = SteadinessTracker()
    private var lastProcessed: Double = -1
    private let interval: Double = 0.25   // ~4 Hz
    private let onReadiness: @Sendable (CaptureReadiness) -> Void

    init(onReadiness: @escaping @Sendable (CaptureReadiness) -> Void) {
        self.onReadiness = onReadiness
    }

    func handle(_ sampleBuffer: CMSampleBuffer) {
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        if lastProcessed >= 0, t - lastProcessed < interval { return }
        lastProcessed = t

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent),
              let buffer = GrayscaleBuffer(cgImage: cg, maxDimension: 512) else { return }

        let detection = CardRectangleDetector.detect(in: cg)
        let cardDetected = detection != nil
        let sharp = BlurMetric.laplacianVariance(buffer) >= gate.thresholds.minBlurScore

        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let normRect: CGRect? = detection.flatMap { det in
            guard w > 0, h > 0 else { return nil }
            return CGRect(x: det.boundingBox.minX / w, y: det.boundingBox.minY / h,
                          width: det.boundingBox.width / w, height: det.boundingBox.height / h)
        }
        let glareOK = GlareMetric.overexposedRatio(buffer, in: normRect) <= gate.thresholds.maxGlareRatio

        if let det = detection, w > 0, h > 0 {
            steadiness.push(CGPoint(x: det.boundingBox.midX / w, y: det.boundingBox.midY / h))
        } else {
            steadiness.reset()
        }

        onReadiness(CaptureReadiness(
            cardDetected: cardDetected, sharp: sharp,
            glareOK: glareOK, steady: steadiness.isSteady
        ))
    }
}
