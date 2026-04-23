import Foundation
import SwiftData

enum Grader: String, Codable, CaseIterable {
    case PSA, BGS, CGC, SGC, TAG
}

enum ScanStatus: String, Codable, CaseIterable {
    case pendingValidation = "pending_validation"
    case validated
    case validationFailed = "validation_failed"
    case manualEntry = "manual_entry"
}

@Model
final class Scan {
    @Attribute(.unique) var id: UUID
    var storeId: UUID
    var lotId: UUID
    var userId: UUID
    var grader: Grader
    var certNumber: String
    var grade: String?
    var status: ScanStatus
    var ocrRawText: String?
    var ocrConfidence: Double?
    var capturedPhotoURL: String?
    var offerCents: Int64?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        storeId: UUID,
        lotId: UUID,
        userId: UUID,
        grader: Grader,
        certNumber: String,
        status: ScanStatus = .pendingValidation,
        ocrRawText: String? = nil,
        ocrConfidence: Double? = nil,
        capturedPhotoURL: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.storeId = storeId
        self.lotId = lotId
        self.userId = userId
        self.grader = grader
        self.certNumber = certNumber
        self.grade = nil
        self.status = status
        self.ocrRawText = ocrRawText
        self.ocrConfidence = ocrConfidence
        self.capturedPhotoURL = capturedPhotoURL
        self.offerCents = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
