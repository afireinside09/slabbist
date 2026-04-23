import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class CameraSession: NSObject {
    enum Authorization: Equatable {
        case notDetermined, authorized, denied, restricted
    }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var isRunning: Bool = false

    let captureSession = AVCaptureSession()

    private let sampleQueue = DispatchQueue(label: "com.slabbist.camera.samples")
    private let videoOutput = AVCaptureVideoDataOutput()

    // Callback storage lives off the MainActor because the AVFoundation
    // delegate calls us back on `sampleQueue`. Guarded by a lock so writes
    // from MainActor and reads from `sampleQueue` are well-ordered.
    private let callbackLock = NSLock()
    nonisolated(unsafe) private var _onSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?

    /// Set the per-frame callback. The callback fires on the internal sample
    /// queue (a serial background queue) — callers that need MainActor work
    /// must hop themselves. Pass `nil` to clear.
    func setOnSampleBuffer(_ callback: (@Sendable (CMSampleBuffer) -> Void)?) {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        _onSampleBuffer = callback
    }

    func requestAuthorization() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:     authorization = .authorized
        case .denied:         authorization = .denied
        case .restricted:     authorization = .restricted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorization = granted ? .authorized : .denied
        @unknown default:
            authorization = .denied
        }
    }

    func configure() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "CameraSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "No rear camera"])
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw NSError(domain: "CameraSession", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"])
        }
        captureSession.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        guard captureSession.canAddOutput(videoOutput) else {
            throw NSError(domain: "CameraSession", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot add video output"])
        }
        captureSession.addOutput(videoOutput)
    }

    func start() {
        guard !captureSession.isRunning else { return }
        Task.detached(priority: .userInitiated) {
            self.captureSession.startRunning()
            await MainActor.run { self.isRunning = true }
        }
    }

    func stop() {
        guard captureSession.isRunning else { return }
        Task.detached(priority: .userInitiated) {
            self.captureSession.stopRunning()
            await MainActor.run { self.isRunning = false }
        }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        // Invoked on `sampleQueue`. Read the callback under lock and fire it
        // synchronously on this queue — no MainActor hop. Callers that need
        // MainActor work must hop inside their own closure.
        callbackLock.lock()
        let callback = _onSampleBuffer
        callbackLock.unlock()
        callback?(sampleBuffer)
    }
}
