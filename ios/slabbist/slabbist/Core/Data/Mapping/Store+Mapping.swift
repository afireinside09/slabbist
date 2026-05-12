import Foundation

extension StoreDTO {
    init(_ model: Store) {
        self.init(
            id: model.id,
            name: model.name,
            ownerUserId: model.ownerUserId,
            createdAt: model.createdAt,
            defaultMarginPct: model.defaultMarginPct,
            marginLadder: model.marginLadder
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
            defaultMarginPct: dto.defaultMarginPct,
            marginLadderJSON: Self.encodeLadder(dto.marginLadder)
        )
    }

    func apply(_ dto: StoreDTO) {
        self.name = dto.name
        self.ownerUserId = dto.ownerUserId
        self.createdAt = dto.createdAt
        self.defaultMarginPct = dto.defaultMarginPct
        self.marginLadderJSON = Self.encodeLadder(dto.marginLadder)
    }

    /// Hydration helper: encode a `[MarginTier]` to the JSON String form
    /// SwiftData persists. Canonicalizes on the way in so locally-stored
    /// data is lookup-ready without an extra sort on read. Returns `nil`
    /// on encoding failure so the computed `marginLadder` falls back to
    /// the canonical default instead of writing junk.
    fileprivate static func encodeLadder(_ tiers: [MarginTier]) -> String? {
        let canonical = tiers.canonicalized()
        guard let data = try? JSONEncoder().encode(canonical) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
