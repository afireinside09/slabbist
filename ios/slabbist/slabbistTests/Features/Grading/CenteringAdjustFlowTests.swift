import Foundation
import Testing
import UIKit
@testable import slabbist

/// The centering-adjust step is the whole point of this feature: the grade
/// estimate must consume the centering the *user corrected*, not the raw
/// auto-measurement. These tests pin that the corrected ratios survive the
/// capture → adjust → confirm → analysis path and reach the estimate.
@Suite("Centering adjust flow")
@MainActor
struct CenteringAdjustFlowTests {
    @Test("beginAdjust on front parks the still and enters the adjust step")
    func beginAdjustFront() {
        let vm = GradingCaptureViewModel(repo: FakeGradeRepo(), uploader: FakeUploader(), userId: UUID())
        vm.beginAdjust(image: UIImage(), guides: .centeredDefault)
        #expect(vm.phase == .adjustFront)
        #expect(vm.pendingAdjustImage != nil)
    }

    @Test("confirmFront commits and advances to back capture")
    func confirmFrontAdvances() {
        let vm = GradingCaptureViewModel(repo: FakeGradeRepo(), uploader: FakeUploader(), userId: UUID())
        vm.beginAdjust(image: UIImage(), guides: .centeredDefault)
        vm.confirmFront(centering: CenteringRatios(left: 0.58, right: 0.42, top: 0.5, bottom: 0.5))
        #expect(vm.phase == .back)
        #expect(vm.pendingAdjustImage == nil)
    }

    /// The load-bearing assertion: the exact ratios the user dialled in on
    /// each side are the ones the estimate is computed from. If the flow
    /// silently fell back to a default or the seed, this fails.
    @Test("user-corrected front and back ratios reach the estimate")
    func correctedRatiosReachEstimate() async throws {
        let repo = FakeGradeRepo()
        let vm = GradingCaptureViewModel(repo: repo, uploader: FakeUploader(), userId: UUID())

        vm.beginAdjust(image: UIImage(), guides: .centeredDefault) // adjustFront
        let front = CenteringRatios(left: 0.6, right: 0.4, top: 0.5, bottom: 0.5)
        vm.confirmFront(centering: front)                          // → back

        vm.beginAdjust(image: UIImage(), guides: .centeredDefault) // adjustBack
        let back = CenteringRatios(left: 0.45, right: 0.55, top: 0.52, bottom: 0.48)
        vm.confirmBack(centering: back)

        try await vm.runAnalysis(includeOtherGraders: false)
        #expect(vm.result?.centeringFront == front)
        #expect(vm.result?.centeringBack == back)
    }

    @Test("cancelAdjust drops the still and returns to the same capture side")
    func cancelReturns() {
        let vm = GradingCaptureViewModel(repo: FakeGradeRepo(), uploader: FakeUploader(), userId: UUID())
        vm.beginAdjust(image: UIImage(), guides: .centeredDefault)
        vm.cancelAdjust()
        #expect(vm.phase == .front)
        #expect(vm.pendingAdjustImage == nil)
    }
}
