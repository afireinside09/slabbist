import Foundation

/// Wire shape for the `vendors` Postgres table.
///
/// `archivedAt` is a soft-archive marker (NULL = active). The
/// `contactMethod` column is a Postgres enum string; we keep it as
/// `String?` here so the wire layer doesn't pin the enum cases — the
/// domain layer is free to validate or surface them however it wants.
nonisolated struct VendorDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var storeId: UUID
    var displayName: String
    var contactMethod: String?
    var contactValue: String?
    var notes: String?
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case displayName = "display_name"
        case contactMethod = "contact_method"
        case contactValue = "contact_value"
        case notes
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
