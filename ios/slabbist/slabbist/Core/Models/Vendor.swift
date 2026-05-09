import Foundation
import SwiftData

@Model
final class Vendor {
    @Attribute(.unique) var id: UUID
    var storeId: UUID
    var displayName: String
    /// Mirrors Postgres `contact_method` enum string; one of:
    /// "phone" | "email" | "instagram" | "in_person" | "other".
    /// Optional because contact info may be unknown at first capture.
    var contactMethod: String?
    var contactValue: String?
    var notes: String?
    /// Soft-archive timestamp. Active vendors have `archivedAt == nil`;
    /// archived vendors are excluded from pickers but readable for history.
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        storeId: UUID,
        displayName: String,
        contactMethod: String? = nil,
        contactValue: String? = nil,
        notes: String? = nil,
        archivedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.storeId = storeId
        self.displayName = displayName
        self.contactMethod = contactMethod
        self.contactValue = contactValue
        self.notes = notes
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
