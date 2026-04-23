import Foundation
import SwiftData

enum StoreRole: String, Codable, CaseIterable {
    case owner, manager, associate
}

@Model
final class StoreMember {
    var storeId: UUID
    var userId: UUID
    var role: StoreRole
    var createdAt: Date

    init(storeId: UUID, userId: UUID, role: StoreRole, createdAt: Date) {
        self.storeId = storeId
        self.userId = userId
        self.role = role
        self.createdAt = createdAt
    }
}
