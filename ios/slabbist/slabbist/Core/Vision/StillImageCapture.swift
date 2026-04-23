import AVFoundation
import UIKit

/// Captures a single high-resolution still photo from a `CameraSession`.
/// Adds an `AVCapturePhotoOutput` to the session lazily and orchestrates
/// the delegate callback as an `async` value.
@MainActor
final class StillImageCapture: NSObject {
    private let session: CameraSession
    private let photoOutput = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var attached = false

    init(session: CameraSession) {
        self.session = session
        super.init()
    }

    func attachIfNeeded() {
        guard !attached else { return }
        let cs = session.captureSession
        cs.beginConfiguration()
        defer { cs.commitConfiguration() }
        if cs.canAddOutput(photoOutput) {
            cs.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            attached = true
        }
    }

    func capture() async throws -> UIImage {
        attachIfNeeded()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UIImage, Error>) in
            self.continuation = cont
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            settings.flashMode = .off
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension StillImageCapture: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            defer { self.continuation = nil }
            if let error {
                self.continuation?.resume(throwing: error)
                return
            }
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                self.continuation?.resume(throwing: NSError(
                    domain: "StillImageCapture",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "no image data"]
                ))
                return
            }
            self.continuation?.resume(returning: image)
        }
    }
}
