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
