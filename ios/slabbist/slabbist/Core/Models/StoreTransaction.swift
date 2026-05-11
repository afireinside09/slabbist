import Foundation
import SwiftData

/// "Transaction" collides with Combine; "StoreTransaction" disambiguates.
@Model
final class StoreTransaction {
    @Attribute(.unique) var id: UUID
    var storeId: UUID
    var lotId: UUID
    var vendorId: UUID?
    var vendorNameSnapshot: String
    var totalBuyCents: Int64
    /// Mirrors Postgres `payment_method` enum string.
    var paymentMethod: String
    var paymentReference: String?
    var paidAt: Date
    var paidByUserId: UUID
    var voidedAt: Date?
    var voidedByUserId: UUID?
    var voidReason: String?
    var voidOfTransactionId: UUID?
    var createdAt: Date

    init(
        id: UUID, storeId: UUID, lotId: UUID,
        vendorId: UUID?, vendorNameSnapshot: String,
        totalBuyCents: Int64, paymentMethod: String,
        paymentReference: String?,
        paidAt: Date, paidByUserId: UUID,
        voidedAt: Date? = nil, voidedByUserId: UUID? = nil,
        voidReason: String? = nil, voidOfTransactionId: UUID? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.storeId = storeId
        self.lotId = lotId
        self.vendorId = vendorId
        self.vendorNameSnapshot = vendorNameSnapshot
        self.totalBuyCents = totalBuyCents
        self.paymentMethod = paymentMethod
        self.paymentReference = paymentReference
        self.paidAt = paidAt
        self.paidByUserId = paidByUserId
        self.voidedAt = voidedAt
        self.voidedByUserId = voidedByUserId
        self.voidReason = voidReason
        self.voidOfTransactionId = voidOfTransactionId
        self.createdAt = createdAt
    }

    /// Convenience: a row is "active" (counts toward totals) if it isn't voided AND isn't itself a void.
    var isActive: Bool { voidedAt == nil && voidOfTransactionId == nil }
}
