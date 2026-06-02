import AVFoundation
import Observation
import UIKit

/// One-shot still-capture session for the photo-scan flow. Parallel to
/// `CameraSession` (which owns the live video-data OCR loop) but configured
/// with `AVCapturePhotoOutput` for a full-resolution still — live video
/// frames are downscaled and too soft to read many small labels at once.
///
/// Isolated from `CameraSession` on purpose. The two never run concurrently:
/// `BulkScanView` stops its live session while the photo cover is up.
@MainActor
@Observable
final class StillPhotoCamera: NSObject {
    enum Authorization: Equatable {
        case notDetermined, authorized, denied, restricted
    }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var isConfigured: Bool = false

    nonisolated(unsafe) let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()

    /// Held across the async `capture()` round-trip; resumed by the
    /// AVFoundation delegate callback. Only one capture is in flight at a
    /// time (the shutter is disabled while capturing).
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    func requestAuthorization() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:  authorization = .authorized
        case .denied:      authorization = .denied
        case .restricted:  authorization = .restricted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorization = granted ? .authorized : .denied
        @unknown default:
            authorization = .denied
        }
    }

    func configure() throws {
        guard !isConfigured else { return }
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "StillPhotoCamera", code: 1, userInfo: [NSLocalizedDescriptionKey: "No rear camera"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw NSError(domain: "StillPhotoCamera", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"])
        }
        captureSession.addInput(input)

        guard captureSession.canAddOutput(photoOutput) else {
            throw NSError(domain: "StillPhotoCamera", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot add photo output"])
        }
        captureSession.addOutput(photoOutput)
        isConfigured = true
    }

    func start() {
        guard !captureSession.isRunning else { return }
        Task.detached(priority: .userInitiated) {
            self.captureSession.startRunning()
        }
    }

    func stop() {
        guard captureSession.isRunning else { return }
        Task.detached(priority: .userInitiated) {
            self.captureSession.stopRunning()
        }
    }

    /// Capture one full-res still. Returns `nil` if not configured or capture
    /// fails. Resolves on the AVFoundation delegate callback.
    func capture() async -> UIImage? {
        guard isConfigured else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            captureContinuation = cont
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension StillPhotoCamera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            let cont = self.captureContinuation
            self.captureContinuation = nil
            cont?.resume(returning: image)
        }
    }
}
