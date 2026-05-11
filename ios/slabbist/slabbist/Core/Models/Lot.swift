import Foundation
import SwiftData

enum LotStatus: String, Codable, CaseIterable {
    case open, closed, converted
}

/// Where the lot sits inside the vendor offer flow. Distinct from `LotStatus`,
/// which tracks the overall lifecycle (open/closed/converted): `LotOfferState`
/// is the narrower workflow Plan 2 introduces around pricing + presenting a
/// numeric offer to the seller.
enum LotOfferState: String, Codable, CaseIterable {
    case drafting, priced, presented, accepted, declined, paid, voided
}

@Model
final class Lot {
    @Attribute(.unique) var id: UUID
    var storeId: UUID
    var createdByUserId: UUID
    var name: String
    var notes: String?
    var status: LotStatus
    var vendorName: String?
    var vendorContact: String?
    /// FK into the local `Vendor` table (and the `vendors.id` Postgres column).
    /// Populated when the user picks a known vendor for the lot; the loose
    /// `vendorName` / `vendorContact` strings above stay as a free-form fallback
    /// for ad-hoc walk-ins that don't yet have a Vendor row.
    var vendorId: UUID?
    /// Snapshot of the vendor's display name at the moment the offer was priced.
    /// Persisted so the lot's offer math + presentation copy stays stable even
    /// if the underlying `Vendor.displayName` is later renamed.
    var vendorNameSnapshot: String?
    /// Snapshot of the margin percentage applied when this lot was priced
    /// (0.0...1.0). Captured so re-opening a priced lot reproduces the same
    /// numbers even if the store's default margin rule has drifted.
    var marginPctSnapshot: Double?
    var offeredTotalCents: Int64?
    var marginRuleId: UUID?
    /// Where this lot sits in the offer workflow. Stored as `String` (the raw
    /// value of `LotOfferState`) so SwiftData lightweight migration doesn't
    /// need to learn about the enum case set; consumers cast through
    /// `LotOfferState(rawValue:)`.
    var lotOfferState: String
    /// Timestamp of the last `lotOfferState` transition. `nil` while the lot
    /// has only ever been in the default `.drafting` state.
    var lotOfferStateUpdatedAt: Date?
    var transactionStamp: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        storeId: UUID,
        createdByUserId: UUID,
        name: String,
        notes: String? = nil,
        status: LotStatus = .open,
        lotOfferState: LotOfferState = .drafting,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.storeId = storeId
        self.createdByUserId = createdByUserId
        self.name = name
        self.notes = notes
        self.status = status
        self.vendorName = nil
        self.vendorContact = nil
        self.vendorId = nil
        self.vendorNameSnapshot = nil
        self.marginPctSnapshot = nil
        self.offeredTotalCents = nil
        self.marginRuleId = nil
        self.lotOfferState = lotOfferState.rawValue
        self.lotOfferStateUpdatedAt = nil
        self.transactionStamp = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
