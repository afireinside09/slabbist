import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class GradingCaptureViewModel {
    enum Phase: Equatable {
        case front
        /// Front still captured; user is fine-tuning the centering guides
        /// before it's recorded. The image + seed guides live in
        /// `pendingAdjust*`.
        case adjustFront
        case back
        case adjustBack
        case uploading
        case analyzing
        case done(estimateId: UUID)
        case failed(message: String)
    }

    private(set) var phase: Phase = .front

    /// The estimate the analysis just produced. Held so the host can show
    /// the full grade report in-flow the moment capture completes — the
    /// result the user earned is presented immediately, not buried in the
    /// history list for them to hunt down. Set alongside `.done`.
    private(set) var result: GradeEstimateDTO?
    /// Last error thrown by `runAnalysis` — lives on the view-model
    /// (single source of truth alongside `phase`) rather than in the
    /// view, so a detached retry Task doesn't drop the write when the
    /// view recreates. `AnalysisOverlay` reads this to special-case
    /// offline-class `URLError`s.
    private(set) var lastError: Error?

    /// Latest live capture readiness published by `LiveReadinessAnalyzer`.
    /// Drives the shutter-enabled state and the QualityChip while framing.
    private(set) var liveReadiness: CaptureReadiness?

    /// Called from the camera sample queue (hopped to MainActor). Ignored once
    /// we leave the camera (uploading/analyzing/done/failed) so a late frame
    /// can't repaint the chip behind the analysis overlay.
    func updateLiveReadiness(_ readiness: CaptureReadiness) {
        guard phase == .front || phase == .back else { return }
        liveReadiness = readiness
    }

    private let repo: any GradeEstimateRepository
    private let uploader: any PhotoUploader
    private let userId: UUID

    private var frontImage: UIImage?
    private var frontCentering: CenteringRatios?
    private var backImage: UIImage?
    private var backCentering: CenteringRatios?

    /// The still + Vision-seeded guides handed to the centering editor while
    /// in an `.adjust*` phase. Cleared once the user confirms (or retakes).
    private(set) var pendingAdjustImage: UIImage?
    private(set) var pendingAdjustGuides: CenteringGuides?
    /// Captured on the first valid `runAnalysis` call so `retry()` can
    /// re-invoke with the same arg. Set ONLY after the photo guard
    /// passes — a guard-failing call (no images captured yet) must not
    /// poison the cached value for a later legitimate retry (P1.6).
    private var lastIncludeOtherGraders: Bool = false

    init(repo: any GradeEstimateRepository, uploader: any PhotoUploader, userId: UUID) {
        self.repo = repo
        self.uploader = uploader
        self.userId = userId
    }

    func recordFront(image: UIImage, centering: CenteringRatios) {
        frontImage = image
        frontCentering = centering
        phase = .back
    }

    func recordBack(image: UIImage, centering: CenteringRatios) {
        backImage = image
        backCentering = centering
    }

    /// Park a freshly-captured still and its Vision-seeded guides, and enter
    /// the centering-adjust step. The centering the user dials in there is
    /// what gets recorded — replacing the old auto-measured-only path.
    func beginAdjust(image: UIImage, guides: CenteringGuides) {
        pendingAdjustImage = image
        pendingAdjustGuides = guides
        switch phase {
        case .front: phase = .adjustFront
        case .back: phase = .adjustBack
        default: break
        }
    }

    /// Commit the user-corrected front centering and advance to back capture.
    func confirmFront(centering: CenteringRatios) {
        guard let image = pendingAdjustImage else { return }
        pendingAdjustImage = nil
        pendingAdjustGuides = nil
        recordFront(image: image, centering: centering)
    }

    /// Commit the user-corrected back centering. The caller kicks analysis
    /// (through the cancellable Task) once this returns.
    func confirmBack(centering: CenteringRatios) {
        guard let image = pendingAdjustImage else { return }
        pendingAdjustImage = nil
        pendingAdjustGuides = nil
        recordBack(image: image, centering: centering)
    }

    /// Discard the parked still and return to re-capturing the same side.
    func cancelAdjust() {
        pendingAdjustImage = nil
        pendingAdjustGuides = nil
        switch phase {
        case .adjustFront: phase = .front
        case .adjustBack: phase = .back
        default: break
        }
    }

    func runAnalysis(includeOtherGraders: Bool) async throws {
        guard let frontImage, let frontCentering, let backImage, let backCentering else {
            phase = .failed(message: "Missing capture data")
            return
        }
        lastIncludeOtherGraders = includeOtherGraders
        lastError = nil
        phase = .uploading
        let upload: GradePhotoUploader.UploadResult
        do {
            // The uploader re-uploads on each call. It's wasted bytes on
            // retry, but the alternative — caching the storage paths and
            // skipping the upload — risks the Edge Function reading paths
            // that the server has already GC'd. Keep retry simple: full
            // re-upload, full re-analysis. (Spec defers disk persistence.)
            upload = try await uploader.upload(front: frontImage, back: backImage, userId: userId)
        } catch {
            phase = .failed(message: "Upload failed — try again.")
            lastError = error
            throw error
        }

        // Cancellation checkpoint between phases: if the user tapped
        // Cancel while the uploader was in flight, abort BEFORE we kick
        // off the analyze call — so a late `.done(estimateId:)` can't
        // land on a dismissed view (P0.2).
        try Task.checkCancellation()

        phase = .analyzing
        do {
            let row = try await repo.requestEstimate(
                frontPath: upload.frontPath,
                backPath: upload.backPath,
                centeringFront: frontCentering,
                centeringBack: backCentering,
                includeOtherGraders: includeOtherGraders
            )
            try Task.checkCancellation()
            result = row
            phase = .done(estimateId: row.id)
        } catch is CancellationError {
            // Cancellation surfaced from `requestEstimate` or the
            // checkpoint above. Don't overwrite `phase` with `.failed`
            // — the view is being dismissed, the overlay would be
            // dismantled before it ever rendered. Re-throw so the
            // caller's Task.cancel() handler observes it.
            throw CancellationError()
        } catch {
            phase = .failed(message: "Analysis failed — try again.")
            lastError = error
            throw error
        }
    }

    /// Re-invoke `runAnalysis` with the cached photos + centering
    /// ratios from the failed attempt. Used by `AnalysisOverlay`'s
    /// "Try again". No-ops if the photos haven't been captured (the
    /// overlay only shows after a `.failed` phase, which means both
    /// photos exist).
    func retry() async throws {
        try await runAnalysis(includeOtherGraders: lastIncludeOtherGraders)
    }
}
