import Vision
import UIKit
import ImageIO

/// One-shot Vision text recognition over a still image. Mirrors the live
/// scan path's request config (`.accurate`, language correction off) so a
/// photo reads cert digits the same way the camera loop does. Synchronous
/// and `nonisolated` — call it off the MainActor (see `PhotoScanView`).
enum PhotoTextRecognizer {
    static func recognizeText(in image: UIImage) -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}

/// Bridge `UIImage.Orientation` → `CGImagePropertyOrientation` so Vision
/// uprights a photo captured in any device orientation before OCR.
extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:            self = .up
        case .upMirrored:    self = .upMirrored
        case .down:          self = .down
        case .downMirrored:  self = .downMirrored
        case .left:          self = .left
        case .leftMirrored:  self = .leftMirrored
        case .right:         self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}
