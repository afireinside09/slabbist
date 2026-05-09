import Foundation

extension VendorDTO {
    init(_ model: Vendor) {
        self.init(
            id: model.id,
            storeId: model.storeId,
            displayName: model.displayName,
            contactMethod: model.contactMethod,
            contactValue: model.contactValue,
            notes: model.notes,
            archivedAt: model.archivedAt,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }
}

extension Vendor {
    convenience init(dto: VendorDTO) {
        self.init(
            id: dto.id,
            storeId: dto.storeId,
            displayName: dto.displayName,
            contactMethod: dto.contactMethod,
            contactValue: dto.contactValue,
            notes: dto.notes,
            archivedAt: dto.archivedAt,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    func apply(_ dto: VendorDTO) {
        self.storeId = dto.storeId
        self.displayName = dto.displayName
        self.contactMethod = dto.contactMethod
        self.contactValue = dto.contactValue
        self.notes = dto.notes
        self.archivedAt = dto.archivedAt
        self.createdAt = dto.createdAt
        self.updatedAt = dto.updatedAt
    }
}
