import Foundation
import SwiftData

@Model
final class OutboxItem {
    @Attribute(.unique) var id: UUID
    var kind: OutboxKind
    var payload: Data
    var status: OutboxStatus
    var attempts: Int
    var lastError: String?
    var createdAt: Date
    var nextAttemptAt: Date

    init(
        id: UUID,
        kind: OutboxKind,
        payload: Data,
        status: OutboxStatus = .pending,
        attempts: Int = 0,
        lastError: String? = nil,
        createdAt: Date,
        nextAttemptAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.status = status
        self.attempts = attempts
        self.lastError = lastError
        self.createdAt = createdAt
        self.nextAttemptAt = nextAttemptAt
    }
}
