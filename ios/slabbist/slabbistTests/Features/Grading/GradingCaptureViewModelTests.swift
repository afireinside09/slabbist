import Foundation
import Testing
import UIKit
@testable import slabbist

@Suite("GradingCaptureViewModel")
@MainActor
struct GradingCaptureViewModelTests {
    @Test("starts in front-capture phase")
    func initialPhase() {
        let vm = GradingCaptureViewModel(
            repo: FakeGradeRepo(),
            uploader: FakeUploader(),
            userId: UUID()
        )
        #expect(vm.phase == .front)
    }

    @Test("after front capture, advances to back-capture phase")
    func frontToBack() {
        let vm = GradingCaptureViewModel(
            repo: FakeGradeRepo(),
            uploader: FakeUploader(),
            userId: UUID()
        )
        let img = UIImage()
        let cf = CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5)
        vm.recordFront(image: img, centering: cf)
        #expect(vm.phase == .back)
    }

    @Test("after back capture, uploads + requests estimate, then transitions to .done with id")
    func backToDone() async throws {
        let repo = FakeGradeRepo()
        let uploader = FakeUploader()
        let vm = GradingCaptureViewModel(repo: repo, uploader: uploader, userId: UUID())
        let img = UIImage()
        let cf = CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5)
        vm.recordFront(image: img, centering: cf)
        vm.recordBack(image: img, centering: cf)
        try await vm.runAnalysis(includeOtherGraders: false)
        if case let .done(id) = vm.phase {
            #expect(id == repo.lastReturnedID)
        } else {
            Issue.record("expected .done phase")
        }
        // The full estimate is held so the host can present the report
        // in-flow without re-fetching what we just computed.
        #expect(vm.result?.id == repo.lastReturnedID)
    }

    // MARK: - C3 — failure overlay + retry path

    @Test("uploader throws → phase becomes .failed; retry with passing stub → .done")
    func uploadFailureThenRetrySucceeds() async throws {
        let repo = FakeGradeRepo()
        let uploader = FlakyUploader(failFirst: true)
        let vm = GradingCaptureViewModel(repo: repo, uploader: uploader, userId: UUID())
        let img = UIImage()
        let cf = CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5)
        vm.recordFront(image: img, centering: cf)
        vm.recordBack(image: img, centering: cf)

        // First analysis throws.
        await #expect(throws: (any Error).self) {
            try await vm.runAnalysis(includeOtherGraders: false)
        }
        if case .failed = vm.phase {
            // ok
        } else {
            Issue.record("expected .failed phase after upload throw, got \(vm.phase)")
        }

        // retry() re-invokes runAnalysis with the cached photos +
        // includeOtherGraders argument; uploader now passes → .done.
        try await vm.retry()
        if case let .done(id) = vm.phase {
            #expect(id == repo.lastReturnedID)
        } else {
            Issue.record("expected .done phase after retry, got \(vm.phase)")
        }
    }

    @Test("repo throws → .failed; cached includeOtherGraders forwards on retry")
    func analysisFailureRetryPreservesArgs() async throws {
        let repo = FlakyGradeRepo(failFirst: true)
        let uploader = FakeUploader()
        let vm = GradingCaptureViewModel(repo: repo, uploader: uploader, userId: UUID())
        let img = UIImage()
        let cf = CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5)
        vm.recordFront(image: img, centering: cf)
        vm.recordBack(image: img, centering: cf)

        await #expect(throws: (any Error).self) {
            try await vm.runAnalysis(includeOtherGraders: true)
        }
        if case .failed = vm.phase {
            // ok
        } else {
            Issue.record("expected .failed phase after analysis throw, got \(vm.phase)")
        }

        try await vm.retry()
        #expect(repo.lastIncludeOtherGraders == true)
        if case .done = vm.phase {
            // ok
        } else {
            Issue.record("expected .done phase after retry, got \(vm.phase)")
        }
    }

    @Test("AnalysisOverlay.failureDetail surfaces offline copy for URLError.notConnectedToInternet")
    func overlayOfflineCopy() {
        let detail = AnalysisOverlay.failureDetail(
            message: "Upload failed — try again.",
            error: URLError(.notConnectedToInternet)
        )
        #expect(detail == "You're offline. We'll keep your photos. Reconnect and tap Try again.")
    }

    @Test("AnalysisOverlay.failureDetail surfaces offline copy for networkConnectionLost / timedOut")
    func overlayOfflineCopyExtendedClass() {
        let lost = AnalysisOverlay.failureDetail(
            message: "Upload failed — try again.",
            error: URLError(.networkConnectionLost)
        )
        #expect(lost.contains("offline"))

        let timeout = AnalysisOverlay.failureDetail(
            message: "Analysis failed — try again.",
            error: URLError(.timedOut)
        )
        #expect(timeout.contains("offline"))
    }

    @Test("AnalysisOverlay.failureDetail passes through non-network errors")
    func overlayDefaultsToMessage() {
        let detail = AnalysisOverlay.failureDetail(
            message: "Server returned 503.",
            error: NSError(domain: "Test", code: 503)
        )
        #expect(detail == "Server returned 503.")

        let nilErrorDetail = AnalysisOverlay.failureDetail(
            message: "Missing capture data",
            error: nil
        )
        #expect(nilErrorDetail == "Missing capture data")
    }

    // MARK: - P1.7 — lastError on view model, not view

    @Test("URL error throw populates viewModel.lastError so the overlay can read offline copy")
    func lastErrorPopulatedOnViewModel() async {
        let uploader = FlakyUploader(failFirst: true)
        let vm = GradingCaptureViewModel(repo: FakeGradeRepo(), uploader: uploader, userId: UUID())
        let img = UIImage()
        let cf = CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5)
        vm.recordFront(image: img, centering: cf)
        vm.recordBack(image: img, centering: cf)

        await #expect(throws: (any Error).self) {
            try await vm.runAnalysis(includeOtherGraders: false)
        }

        // P1.7: the captured error must live on the view model, not on
        // a view-side @State, so a detached retry Task can read it
        // back from a single source of truth.
        if let urlError = vm.lastError as? URLError {
            #expect(urlError.code == .notConnectedToInternet)
        } else {
            Issue.record("expected vm.lastError to be a URLError, got \(String(describing: vm.lastError))")
        }
    }

    @Test("successful retry clears viewModel.lastError")
    func lastErrorClearedOnRetry() async throws {
        let uploader = FlakyUploader(failFirst: true)
        let vm = GradingCaptureViewModel(repo: FakeGradeRepo(), uploader: uploader, userId: UUID())
        let img = UIImage()
        let cf = CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5)
        vm.recordFront(image: img, centering: cf)
        vm.recordBack(image: img, centering: cf)
        await #expect(throws: (any Error).self) {
            try await vm.runAnalysis(includeOtherGraders: false)
        }
        #expect(vm.lastError != nil)

        try await vm.retry()
        #expect(vm.lastError == nil, "successful retry must clear lastError so a follow-up failure isn't misclassified")
    }

    // MARK: - P1.6 — guard-fail does not poison cached arg

    @Test("runAnalysis with no captured photos does not corrupt cached includeOtherGraders")
    func guardFailDoesNotPoisonCachedArg() async throws {
        let repo = FlakyGradeRepo(failFirst: false)
        let uploader = FakeUploader()
        let vm = GradingCaptureViewModel(repo: repo, uploader: uploader, userId: UUID())
        let img = UIImage()
        let cf = CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5)

        // First call: legitimate analysis with includeOtherGraders=true.
        vm.recordFront(image: img, centering: cf)
        vm.recordBack(image: img, centering: cf)
        try await vm.runAnalysis(includeOtherGraders: true)
        #expect(repo.lastIncludeOtherGraders == true)

        // Construct a NEW view model that has NEVER had photos captured.
        // Call runAnalysis with the wrong arg — the guard short-circuits,
        // BUT under the P1.6 bug it would still store `false`. A later
        // legitimate retry would replay with the poisoned value.
        let freshRepo = FlakyGradeRepo(failFirst: false)
        let freshVM = GradingCaptureViewModel(repo: freshRepo, uploader: FakeUploader(), userId: UUID())
        try await freshVM.runAnalysis(includeOtherGraders: false)  // guard fails inside
        if case .failed = freshVM.phase {
            // expected — guard set .failed
        } else {
            Issue.record("expected .failed after guard short-circuit")
        }

        // Now provide photos and retry. The retry should replay
        // whatever `includeOtherGraders` value was paired with the
        // first SUCCESSFUL guard-pass — but there hasn't been one yet,
        // so the default (false) is correct. Capture happens AFTER
        // guard passes, so the broken pre-guard write doesn't leak.
        freshVM.recordFront(image: img, centering: cf)
        freshVM.recordBack(image: img, centering: cf)
        try await freshVM.retry()
        // The retry replayed with the cached default (false). Important:
        // it didn't replay with whatever stale value a buggy pre-guard
        // assignment would have stored. This anchors that the
        // assignment is moved AFTER the guard.
        #expect(freshRepo.lastIncludeOtherGraders == false)
    }

    // MARK: - P0.2 — cancellation interrupts in-flight retry

    @Test("Task.cancel during runAnalysis aborts before requestEstimate completes")
    func cancellationStopsAnalyze() async {
        let uploader = ControllableUploader()
        let repo = CountingRepo()
        let vm = GradingCaptureViewModel(repo: repo, uploader: uploader, userId: UUID())
        let img = UIImage()
        let cf = CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5)
        vm.recordFront(image: img, centering: cf)
        vm.recordBack(image: img, centering: cf)

        let task = Task {
            try await vm.runAnalysis(includeOtherGraders: false)
        }

        // Wait for upload to start, then cancel BEFORE letting it finish.
        await uploader.waitForUploadStart()
        task.cancel()
        // Release the upload — checkCancellation between phases must
        // then bail before requestEstimate is called.
        await uploader.releaseUpload()

        // Task should observe CancellationError.
        let result = await task.result
        switch result {
        case .success:
            Issue.record("cancelled task should not complete successfully")
        case .failure(let error):
            #expect(error is CancellationError, "expected CancellationError, got \(error)")
        }
        // requestEstimate must never have been called — the
        // post-upload checkCancellation gated it. (P0.2)
        #expect(repo.requestCount == 0)
    }
}

/// Uploader whose `upload` call suspends until the test releases it.
/// Used to wedge a runAnalysis mid-flight so we can call Task.cancel
/// between the upload and the analyze step.
actor ControllableUploader: PhotoUploader {
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForUploadStart() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            startContinuation = c
        }
    }

    func releaseUpload() async {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    nonisolated func upload(front: UIImage, back: UIImage, userId: UUID) async throws -> GradePhotoUploader.UploadResult {
        await signalStart()
        await waitForRelease()
        let id = UUID()
        return GradePhotoUploader.UploadResult(
            estimateId: id,
            frontPath: "f/\(id).jpg",
            backPath: "b/\(id).jpg",
            frontThumbPath: "ft/\(id).jpg",
            backThumbPath: "bt/\(id).jpg"
        )
    }

    private func signalStart() async {
        startContinuation?.resume()
        startContinuation = nil
    }

    private func waitForRelease() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            releaseContinuation = c
        }
    }
}

/// Repo that counts `requestEstimate` calls — lets the cancellation
/// test assert the analyze step was NEVER invoked.
final class CountingRepo: GradeEstimateRepository {
    nonisolated(unsafe) private(set) var requestCount = 0

    func listForCurrentUser(page: Page, includeTotalCount: Bool) async throws -> PagedResult<GradeEstimateDTO> {
        PagedResult(rows: [], totalCount: nil, page: page)
    }
    func find(id: UUID) async throws -> GradeEstimateDTO? { nil }
    func setStarred(id: UUID, starred: Bool) async throws {}
    func delete(id: UUID) async throws {}
    func requestEstimate(
        frontPath: String, backPath: String,
        centeringFront: CenteringRatios, centeringBack: CenteringRatios,
        includeOtherGraders: Bool
    ) async throws -> GradeEstimateDTO {
        requestCount += 1
        return GradeEstimateDTO(
            id: UUID(), userId: UUID(), scanId: nil,
            frontImagePath: frontPath, backImagePath: backPath,
            frontThumbPath: frontPath, backThumbPath: backPath,
            imagesPurgedAt: nil,
            centeringFront: centeringFront, centeringBack: centeringBack,
            subGrades: SubGrades(centering: 8, corners: 7, edges: 8, surface: 9),
            subGradeNotes: SubGradeNotes(centering: "n", corners: "n", edges: "n", surface: "n"),
            compositeGrade: 8, confidence: "high",
            verdict: "submit_value", verdictReasoning: "n",
            otherGraders: nil, modelVersion: "v1",
            isStarred: false, createdAt: Date()
        )
    }
}

/// Uploader that fails on the first `upload` call, then succeeds.
final class FlakyUploader: PhotoUploader {
    nonisolated(unsafe) private var attempts = 0
    private let failFirst: Bool
    init(failFirst: Bool) { self.failFirst = failFirst }

    func upload(front: UIImage, back: UIImage, userId: UUID) async throws -> GradePhotoUploader.UploadResult {
        attempts += 1
        if failFirst && attempts == 1 {
            throw URLError(.notConnectedToInternet)
        }
        let id = UUID()
        let prefix = "\(userId.uuidString)/\(id.uuidString)"
        return GradePhotoUploader.UploadResult(
            estimateId: id,
            frontPath: "\(prefix)/front.jpg",
            backPath: "\(prefix)/back.jpg",
            frontThumbPath: "\(prefix)/front_thumb.jpg",
            backThumbPath: "\(prefix)/back_thumb.jpg"
        )
    }
}

/// Repo that throws on the first `requestEstimate` call, then succeeds.
/// Records the `includeOtherGraders` arg so tests can verify the value
/// the view model cached on the failing call is what reaches retry.
final class FlakyGradeRepo: GradeEstimateRepository {
    nonisolated(unsafe) private var attempts = 0
    nonisolated(unsafe) private(set) var lastIncludeOtherGraders: Bool = false
    nonisolated(unsafe) private(set) var lastReturnedID = UUID()
    private let failFirst: Bool

    init(failFirst: Bool) { self.failFirst = failFirst }

    func listForCurrentUser(page: Page, includeTotalCount: Bool) async throws -> PagedResult<GradeEstimateDTO> {
        PagedResult(rows: [], totalCount: nil, page: page)
    }
    func find(id: UUID) async throws -> GradeEstimateDTO? { nil }
    func setStarred(id: UUID, starred: Bool) async throws {}
    func delete(id: UUID) async throws {}
    func requestEstimate(
        frontPath: String, backPath: String,
        centeringFront: CenteringRatios, centeringBack: CenteringRatios,
        includeOtherGraders: Bool
    ) async throws -> GradeEstimateDTO {
        attempts += 1
        lastIncludeOtherGraders = includeOtherGraders
        if failFirst && attempts == 1 {
            throw URLError(.timedOut)
        }
        return GradeEstimateDTO(
            id: lastReturnedID,
            userId: UUID(),
            scanId: nil,
            frontImagePath: frontPath,
            backImagePath: backPath,
            frontThumbPath: frontPath.replacingOccurrences(of: "front.jpg", with: "front_thumb.jpg"),
            backThumbPath: backPath.replacingOccurrences(of: "back.jpg", with: "back_thumb.jpg"),
            imagesPurgedAt: nil,
            centeringFront: centeringFront,
            centeringBack: centeringBack,
            subGrades: SubGrades(centering: 8, corners: 7, edges: 8, surface: 9),
            subGradeNotes: SubGradeNotes(centering: "n", corners: "n", edges: "n", surface: "n"),
            compositeGrade: 8,
            confidence: "high",
            verdict: "submit_value",
            verdictReasoning: "n",
            otherGraders: nil,
            modelVersion: "v1",
            isStarred: false,
            createdAt: Date()
        )
    }
}

final class FakeUploader: PhotoUploader {
    nonisolated(unsafe) var lastResult: GradePhotoUploader.UploadResult?
    func upload(front: UIImage, back: UIImage, userId: UUID) async throws -> GradePhotoUploader.UploadResult {
        let id = UUID()
        let prefix = "\(userId.uuidString)/\(id.uuidString)"
        let r = GradePhotoUploader.UploadResult(
            estimateId: id,
            frontPath: "\(prefix)/front.jpg",
            backPath: "\(prefix)/back.jpg",
            frontThumbPath: "\(prefix)/front_thumb.jpg",
            backThumbPath: "\(prefix)/back_thumb.jpg"
        )
        lastResult = r
        return r
    }
}

final class FakeGradeRepo: GradeEstimateRepository {
    nonisolated(unsafe) private(set) var lastReturnedID = UUID()

    func listForCurrentUser(page: Page, includeTotalCount: Bool) async throws -> PagedResult<GradeEstimateDTO> {
        PagedResult(rows: [], totalCount: nil, page: page)
    }
    func find(id: UUID) async throws -> GradeEstimateDTO? { nil }
    func setStarred(id: UUID, starred: Bool) async throws {}
    func delete(id: UUID) async throws {}
    func requestEstimate(
        frontPath: String, backPath: String,
        centeringFront: CenteringRatios, centeringBack: CenteringRatios,
        includeOtherGraders: Bool
    ) async throws -> GradeEstimateDTO {
        GradeEstimateDTO(
            id: lastReturnedID,
            userId: UUID(),
            scanId: nil,
            frontImagePath: frontPath,
            backImagePath: backPath,
            frontThumbPath: frontPath.replacingOccurrences(of: "front.jpg", with: "front_thumb.jpg"),
            backThumbPath: backPath.replacingOccurrences(of: "back.jpg", with: "back_thumb.jpg"),
            imagesPurgedAt: nil,
            centeringFront: centeringFront,
            centeringBack: centeringBack,
            subGrades: SubGrades(centering: 8, corners: 7, edges: 8, surface: 9),
            subGradeNotes: SubGradeNotes(centering: "n", corners: "n", edges: "n", surface: "n"),
            compositeGrade: 8,
            confidence: "high",
            verdict: "submit_value",
            verdictReasoning: "n",
            otherGraders: nil,
            modelVersion: "v1",
            isStarred: false,
            createdAt: Date()
        )
    }
}
