import Foundation
import SwiftData

@Model
final class OutboxItem {
    @Attribute(.unique) var id: UUID
    var kind: OutboxKind
    var payload: Data
    var status: OutboxItemStatus
    var attempts: Int
    var lastError: String?
    var createdAt: Date
    var nextAttemptAt: Date

    init(
        id: UUID,
        kind: OutboxKind,
        payload: Data,
        status: OutboxItemStatus = .pending,
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

    /// Build a fresh `.pending` row for `payload`, eligible immediately.
    ///
    /// Every write surface enqueues the same way: encode the payload, stamp
    /// `createdAt == nextAttemptAt == now`, status `.pending`, zero attempts.
    /// This funnels that into one place so producers can't drift — and,
    /// critically, `encode` THROWS rather than the old `(try? encode) ??
    /// Data()` pattern that silently queued an empty payload the drainer
    /// could never decode (permanent silent write loss). Callers `try` it
    /// inside their existing throwing enqueue path.
    static func pending<P: Encodable>(
        _ kind: OutboxKind,
        _ payload: P,
        now: Date = Date()
    ) throws -> OutboxItem {
        OutboxItem(
            id: UUID(),
            kind: kind,
            payload: try JSONEncoder().encode(payload),
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        )
    }
}
