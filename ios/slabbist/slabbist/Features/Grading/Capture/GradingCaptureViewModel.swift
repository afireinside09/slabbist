import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class GradingCaptureViewModel {
    enum Phase: Equatable {
        case front
        case back
        case uploading
        case analyzing
        case done(estimateId: UUID)
        case failed(message: String)
    }

    private(set) var phase: Phase = .front

    private let repo: any GradeEstimateRepository
    private let uploader: any PhotoUploader
    private let userId: UUID

    private var frontImage: UIImage?
    private var frontCentering: CenteringRatios?
    private var backImage: UIImage?
    private var backCentering: CenteringRatios?

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

    func runAnalysis(includeOtherGraders: Bool) async throws {
        guard let frontImage, let frontCentering, let backImage, let backCentering else {
            phase = .failed(message: "Missing capture data")
            return
        }
        phase = .uploading
        let upload: GradePhotoUploader.UploadResult
        do {
            upload = try await uploader.upload(front: frontImage, back: backImage, userId: userId)
        } catch {
            phase = .failed(message: "Upload failed — try again.")
            throw error
        }
        phase = .analyzing
        do {
            let row = try await repo.requestEstimate(
                frontPath: upload.frontPath,
                backPath: upload.backPath,
                centeringFront: frontCentering,
                centeringBack: backCentering,
                includeOtherGraders: includeOtherGraders
            )
            phase = .done(estimateId: row.id)
        } catch {
            phase = .failed(message: "Analysis failed — try again.")
            throw error
        }
    }
}
