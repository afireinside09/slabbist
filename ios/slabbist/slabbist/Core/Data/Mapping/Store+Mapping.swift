import Foundation

extension StoreDTO {
    init(_ model: Store) {
        self.init(
            id: model.id,
            name: model.name,
            ownerUserId: model.ownerUserId,
            createdAt: model.createdAt,
            defaultMarginPct: model.defaultMarginPct
        )
    }
}

extension Store {
    convenience init(dto: StoreDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            ownerUserId: dto.ownerUserId,
            createdAt: dto.createdAt,
            defaultMarginPct: dto.defaultMarginPct
        )
    }

    func apply(_ dto: StoreDTO) {
        self.name = dto.name
        self.ownerUserId = dto.ownerUserId
        self.createdAt = dto.createdAt
        self.defaultMarginPct = dto.defaultMarginPct
    }
}
