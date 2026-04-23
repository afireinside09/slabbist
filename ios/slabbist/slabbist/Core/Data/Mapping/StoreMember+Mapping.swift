import Foundation

extension StoreMemberDTO {
    init(_ model: StoreMember) {
        self.init(
            storeId: model.storeId,
            userId: model.userId,
            role: model.role.rawValue,
            createdAt: model.createdAt
        )
    }
}

extension StoreMember {
    convenience init(dto: StoreMemberDTO) throws {
        guard let role = StoreRole(rawValue: dto.role) else {
            throw ModelMappingError.unknownEnumCase(type: "StoreRole", value: dto.role)
        }
        self.init(
            storeId: dto.storeId,
            userId: dto.userId,
            role: role,
            createdAt: dto.createdAt
        )
    }

    func apply(_ dto: StoreMemberDTO) throws {
        guard let role = StoreRole(rawValue: dto.role) else {
            throw ModelMappingError.unknownEnumCase(type: "StoreRole", value: dto.role)
        }
        self.role = role
        self.createdAt = dto.createdAt
    }
}
