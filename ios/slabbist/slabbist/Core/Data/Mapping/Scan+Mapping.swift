import Foundation

extension ScanDTO {
    init(_ model: Scan) {
        self.init(
            id: model.id,
            storeId: model.storeId,
            lotId: model.lotId,
            userId: model.userId,
            grader: model.grader.rawValue,
            certNumber: model.certNumber,
            grade: model.grade,
            status: model.status.rawValue,
            ocrRawText: model.ocrRawText,
            ocrConfidence: model.ocrConfidence,
            capturedPhotoURL: model.capturedPhotoURL,
            offerCents: model.offerCents,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }
}

extension Scan {
    convenience init(dto: ScanDTO) throws {
        guard let grader = Grader(rawValue: dto.grader) else {
            throw ModelMappingError.unknownEnumCase(type: "Grader", value: dto.grader)
        }
        guard let status = ScanStatus(rawValue: dto.status) else {
            throw ModelMappingError.unknownEnumCase(type: "ScanStatus", value: dto.status)
        }

        self.init(
            id: dto.id,
            storeId: dto.storeId,
            lotId: dto.lotId,
            userId: dto.userId,
            grader: grader,
            certNumber: dto.certNumber,
            status: status,
            ocrRawText: dto.ocrRawText,
            ocrConfidence: dto.ocrConfidence,
            capturedPhotoURL: dto.capturedPhotoURL,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )

        self.grade = dto.grade
        self.offerCents = dto.offerCents
    }

    func apply(_ dto: ScanDTO) throws {
        guard let grader = Grader(rawValue: dto.grader) else {
            throw ModelMappingError.unknownEnumCase(type: "Grader", value: dto.grader)
        }
        guard let status = ScanStatus(rawValue: dto.status) else {
            throw ModelMappingError.unknownEnumCase(type: "ScanStatus", value: dto.status)
        }
        self.storeId = dto.storeId
        self.lotId = dto.lotId
        self.userId = dto.userId
        self.grader = grader
        self.certNumber = dto.certNumber
        self.grade = dto.grade
        self.status = status
        self.ocrRawText = dto.ocrRawText
        self.ocrConfidence = dto.ocrConfidence
        self.capturedPhotoURL = dto.capturedPhotoURL
        self.offerCents = dto.offerCents
        self.createdAt = dto.createdAt
        self.updatedAt = dto.updatedAt
    }
}
