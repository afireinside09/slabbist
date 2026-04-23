import Foundation
import SwiftData

enum LotStatus: String, Codable, CaseIterable {
    case open, closed, converted
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
    var offeredTotalCents: Int64?
    var marginRuleId: UUID?
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
        self.offeredTotalCents = nil
        self.marginRuleId = nil
        self.transactionStamp = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
