import UIKit
import CoreGraphics

/// Computes real blur + glare metrics for a captured still. Glare is measured
/// inside the detected card rect (pixel space) when available, so a bright
/// background doesn't trip the gate. Blur is measured over the whole frame.
enum CaptureMetrics {
    struct Result: Equatable {
        var blurScore: Double
        var glareRatio: Double
    }

    static func measure(image: UIImage, cardRect: CGRect?) -> Result {
        guard let cg = image.cgImage,
              let buffer = GrayscaleBuffer(cgImage: cg, maxDimension: 512) else {
            // No decodable image — worst case so the gate rejects.
            return Result(blurScore: 0, glareRatio: 1)
        }
        let blur = BlurMetric.laplacianVariance(buffer)
        let normRect = cardRect.map { rect -> CGRect in
            let w = CGFloat(cg.width), h = CGFloat(cg.height)
            guard w > 0, h > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
            return CGRect(x: rect.minX / w, y: rect.minY / h,
                          width: rect.width / w, height: rect.height / h)
        }
        let glare = GlareMetric.overexposedRatio(buffer, in: normRect)
        return Result(blurScore: blur, glareRatio: glare)
    }
}
