import Foundation
import SwiftData

@Model
final class Store {
    @Attribute(.unique) var id: UUID
    var name: String
    var ownerUserId: UUID
    var createdAt: Date
    var defaultMarginPct: Double
    /// JSON-encoded `[MarginTier]`. Optional so SwiftData lightweight
    /// migration can add the column without requiring a default value at
    /// the SQLite layer — older rows simply read `nil` and the computed
    /// `marginLadder` falls back to the canonical default ladder. Mirrors
    /// the `priceHistoryJSON` / `ptTierPricesJSON` pattern on
    /// `GradedMarketSnapshot`.
    var marginLadderJSON: String?

    init(
        id: UUID,
        name: String,
        ownerUserId: UUID,
        createdAt: Date,
        defaultMarginPct: Double = 0.7,
        marginLadderJSON: String? = nil
    ) {
        self.id = id
        self.name = name
        self.ownerUserId = ownerUserId
        self.createdAt = createdAt
        self.defaultMarginPct = defaultMarginPct
        self.marginLadderJSON = marginLadderJSON
    }

    /// Decoded view of `marginLadderJSON`. Falls back to the canonical
    /// default ladder when the JSON is nil or malformed so the pricing
    /// surface always has something to read.
    var marginLadder: [MarginTier] {
        guard let json = marginLadderJSON,
              let data = json.data(using: .utf8) else {
            return .defaultMarginLadder
        }
        return (try? JSONDecoder().decode([MarginTier].self, from: data))
            ?? .defaultMarginLadder
    }

    /// Persists a new ladder. Canonicalizes (sort + clamp) so the stored
    /// blob is always in lookup-ready shape — callers don't have to
    /// re-sort on every read.
    func applyMarginLadder(_ tiers: [MarginTier]) {
        let canonical = tiers.canonicalized()
        guard let data = try? JSONEncoder().encode(canonical),
              let s = String(data: data, encoding: .utf8) else {
            return
        }
        self.marginLadderJSON = s
    }
}
