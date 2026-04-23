import Foundation
import SwiftData

@Model
final class Store {
    @Attribute(.unique) var id: UUID
    var name: String
    var ownerUserId: UUID
    var createdAt: Date

    init(id: UUID, name: String, ownerUserId: UUID, createdAt: Date) {
        self.id = id
        self.name = name
        self.ownerUserId = ownerUserId
        self.createdAt = createdAt
    }
}
