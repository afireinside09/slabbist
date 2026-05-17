import AVFoundation
import UIKit
import os

/// Captures a single high-resolution still photo from a `CameraSession`.
/// Owns an `AVCapturePhotoOutput` that must be attached to the session
/// before the session starts running — see `attachIfNeeded()`.
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

    deinit {
        // Resume any in-flight continuation so callers don't hang when the
        // view is dismissed mid-capture (e.g. user backs out before the
        // photo delegate fires).
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    /// E1: Attach the photo output. Callers MUST invoke this AFTER
    /// `CameraSession.configure()` and BEFORE `CameraSession.start()` so
    /// the begin/commitConfiguration block doesn't pause a running video
    /// feed. Calling this against a running session still works (it's
    /// idempotent after the first commit) but stalls the preview for
    /// ~200ms, and a capture tap during that window historically caused
    /// AVFoundation to drop the request without invoking the delegate —
    /// hanging the continuation forever. Eager-attach avoids both.
    ///
    /// Also throws `StillImageCaptureError.cannotAttach` if the session
    /// rejects the output (e.g. preset incompatibility) so the caller can
    /// surface the failure instead of silently being unable to capture.
    func attachIfNeeded() throws {
        guard !attached else { return }
        let cs = session.captureSession
        cs.beginConfiguration()
        defer { cs.commitConfiguration() }
        guard cs.canAddOutput(photoOutput) else {
            AppLog.camera.error("StillImageCapture: cannot add photo output to session")
            throw StillImageCaptureError.cannotAttach
        }
        cs.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        attached = true
    }

    func capture() async throws -> UIImage {
        // E1: defend against unattached calls (e.g. attach failed silently
        // in a refactor) — without an attached output, `capturePhoto` never
        // invokes the delegate and the continuation would hang forever.
        guard attached else {
            AppLog.camera.error("StillImageCapture.capture(): called before attach")
            throw StillImageCaptureError.notAttached
        }
        // E1: defend against re-entry. If a previous capture is still
        // in flight we'd lose its continuation by overwriting it here,
        // hanging the first caller. Reject the second call instead so the
        // user sees a clear error rather than a hung capture button.
        guard continuation == nil else {
            AppLog.camera.error("StillImageCapture.capture(): already in flight")
            throw StillImageCaptureError.alreadyInFlight
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UIImage, Error>) in
            self.continuation = cont
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            settings.flashMode = .off
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

#if DEBUG
extension StillImageCapture {
    /// E1 (P1.5) test seam: simulate an in-flight capture so the
    /// `.alreadyInFlight` re-entry guard can be exercised without
    /// spinning a real `AVCaptureSession` (the simulator has no camera,
    /// and calling `photoOutput.capturePhoto` against an unattached
    /// output aborts the process). DEBUG-only — release builds can't
    /// accidentally bypass the real attach path.
    ///
    /// Returns a Task whose continuation has been pinned into the slot.
    /// The test should not await the Task (it would hang); the deinit's
    /// resume-on-cleanup path lets it unwind safely when the SUT is
    /// torn down at end of test scope.
    func _testOnly_startPinnedInFlightCapture() -> Task<Void, Never> {
        attached = true
        return Task { @MainActor [weak self] in
            // This `withCheckedThrowingContinuation` installs a non-nil
            // continuation into `self.continuation` and then suspends
            // forever — the test never resumes it. The deinit cleanup
            // (resume-with-CancellationError) handles teardown.
            _ = try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<UIImage, Error>) in
                guard let self else {
                    cont.resume(throwing: CancellationError())
                    return
                }
                self.continuation = cont
                // Never call AVFoundation; never resume. The deinit picks
                // up the slack when the SUT is released.
            }
        }
    }
}
#endif

/// E1: surfaceable errors so a hung continuation can never be the failure
/// mode the caller sees.
enum StillImageCaptureError: Error, Equatable {
    /// The session rejected the photo output during configuration.
    case cannotAttach
    /// `capture()` was invoked before `attachIfNeeded()` succeeded.
    case notAttached
    /// A capture is already in flight on this instance.
    case alreadyInFlight
}

extension StillImageCapture: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            // E1: pull the continuation out atomically so a delegate
            // callback that fires twice (shouldn't, but AVFoundation has
            // a long history of corner cases) can't resume it twice.
            guard let cont = self.continuation else { return }
            self.continuation = nil
            if let error {
                cont.resume(throwing: error)
                return
            }
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                cont.resume(throwing: NSError(
                    domain: "StillImageCapture",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "no image data"]
                ))
                return
            }
            cont.resume(returning: image)
        }
    }
}
