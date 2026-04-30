import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class CameraSession: NSObject {
    enum Authorization: Equatable {
        case notDetermined, authorized, denied, restricted
    }

    enum SessionFault: Equatable {
        /// `AVCaptureSessionRuntimeError` — usually device unplug, hardware
        /// failure, or another foreground app stealing the camera.
        case runtimeError(message: String)
        /// `AVCaptureSessionWasInterrupted` — Control Center / FaceTime /
        /// thermal shutdown. Caller should pause UI; the session will resume
        /// automatically and `fault` will reset to `nil` when the
        /// `interruptionEnded` notification fires.
        case interrupted(reason: AVCaptureSession.InterruptionReason)
    }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var isRunning: Bool = false
    private(set) var isConfigured: Bool = false
    /// Latest hardware/system fault, or `nil` if the session is healthy.
    /// Observe to surface a banner / error state in the camera UI.
    private(set) var fault: SessionFault?

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

    /// Idempotent — repeat calls (e.g. after a pop/push that re-fires
    /// `onAppear`) short-circuit so the AVCaptureSession keeps its
    /// existing input and output rather than throwing "cannot add
    /// input" on re-entry.
    func configure() throws {
        guard !isConfigured else { return }
        registerSessionObservers()
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
        isConfigured = true
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

    private func registerSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: captureSession,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            let message = err?.localizedDescription ?? "Camera runtime error"
            MainActor.assumeIsolated {
                self.fault = .runtimeError(message: message)
                self.isRunning = self.captureSession.isRunning
            }
        }
        center.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: captureSession,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
            let reason = raw.flatMap { AVCaptureSession.InterruptionReason(rawValue: $0) }
                ?? .videoDeviceNotAvailableInBackground
            MainActor.assumeIsolated {
                self.fault = .interrupted(reason: reason)
            }
        }
        center.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: captureSession,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.fault = nil
            }
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
