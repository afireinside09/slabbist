import Foundation
import Supabase

/// Wire shape for the `lots` Postgres table.
///
/// `transactionStamp` maps to a `jsonb` column and is represented as
/// `AnyJSON` so callers can round-trip arbitrary shapes without us
/// having to pin a schema here. The domain mapping layer converts
/// it to/from `Data` for the SwiftData `Lot` @Model.
nonisolated struct LotDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var storeId: UUID
    var createdByUserId: UUID
    var name: String
    var notes: String?
    var status: String
    var vendorName: String?
    var vendorContact: String?
    var offeredTotalCents: Int64?
    var marginRuleId: UUID?
    var transactionStamp: AnyJSON?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case createdByUserId = "created_by_user_id"
        case name
        case notes
        case status
        case vendorName = "vendor_name"
        case vendorContact = "vendor_contact"
        case offeredTotalCents = "offered_total_cents"
        case marginRuleId = "margin_rule_id"
        case transactionStamp = "transaction_stamp"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
