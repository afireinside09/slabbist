import Foundation
import OSLog
import SwiftData
import Supabase

/// Background actor that drains the outbox.
///
/// Group A complete (insertScan, insertLot, updateLot, deleteLot,
/// updateScan, updateScanOffer, deleteScan, upsertVendor, archiveVendor).
/// Group B kinds (certLookupJob, priceCompJob) throw
/// `OutboxBridgeError.malformedPayload` — the classifier (added in 7.3)
/// will route them to `.failed`.
///
/// The `@ModelActor` macro is convenient but doesn't allow injecting
/// custom dependencies through the synthesized init. We use the
/// manual form here: hold our own `ModelExecutor` and a private
/// `ModelContext`, and conform to `ModelActor` ourselves. The actor
/// isolation already gives us the serial drain loop for free.
actor OutboxDrainer: ModelActor {
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let modelContainer: ModelContainer
    private let context: ModelContext

    /// Status surface for the SwiftUI pill. Sent off-actor via the
    /// supplied `@Sendable` sink so the drainer never imports the
    /// MainActor `OutboxStatus` type directly.
    struct StatusUpdate: Sendable {
        var pendingCount: Int
        var isDraining: Bool
        var isPaused: Bool?
        var lastError: String?
    }

    private static let log = Logger(subsystem: "com.slabbist.sync", category: "outbox")

    private let repositories: AppRepositories
    private let clock: any OutboxClock
    private let statusSink: @Sendable (StatusUpdate) -> Void
    private var isDraining: Bool = false
    private var pausedForAuth: Bool = false

    /// Called by the auth resume path (Task 10) when SessionStore signs back
    /// in. Clears the auth-pause flag so the next kick can proceed.
    func unpause() {
        pausedForAuth = false
    }

    init(
        modelContainer: ModelContainer,
        repositories: AppRepositories,
        clock: any OutboxClock,
        statusSink: @escaping @Sendable (StatusUpdate) -> Void
    ) {
        self.modelContainer = modelContainer
        let ctx = ModelContext(modelContainer)
        self.context = ctx
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ctx)
        self.repositories = repositories
        self.clock = clock
        self.statusSink = statusSink
    }

    /// Fire-and-forget drain trigger. Producers / lifecycle hooks call
    /// this through `OutboxKicker`.
    func kick() async {
        await drainOnce()
    }

    /// Test seam — same body as `kick()` but the await actually waits
    /// for the drain to complete. The actor's serial isolation already
    /// gives us this for free; the alias makes test intent clear.
    func kickAndWait() async {
        await drainOnce()
    }

    #if DEBUG
    /// Test-only enqueue that constructs the `OutboxItem` on the drainer's
    /// own executor, then inserts and saves through the drainer's
    /// `ModelContext`. SwiftData `@Model` instances aren't Sendable, so
    /// the model has to be created on the same isolation domain that
    /// will fetch it back — building it on MainActor and passing the
    /// reference across actor boundaries is undefined.
    func _testEnqueue(
        id: UUID,
        kind: OutboxKind,
        payload: Data,
        createdAt: Date,
        nextAttemptAt: Date
    ) throws {
        let item = OutboxItem(
            id: id,
            kind: kind,
            payload: payload,
            status: .pending,
            attempts: 0,
            createdAt: createdAt,
            nextAttemptAt: nextAttemptAt
        )
        context.insert(item)
        try context.save()
    }

    func _testOutboxCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<OutboxItem>())) ?? 0
    }

    /// Snapshot of an `OutboxItem`'s key fields. `OutboxItem` is a
    /// SwiftData `@Model` class and is not `Sendable`; returning it
    /// across the actor boundary is undefined. This struct captures
    /// only plain value types so tests can inspect them safely.
    struct OutboxItemSnapshot: Sendable {
        let id: UUID
        let kind: OutboxKind
        let status: OutboxItemStatus
        let attempts: Int
        let lastError: String?
        let nextAttemptAt: Date
    }

    func _testFirstOutboxItem() throws -> OutboxItemSnapshot {
        var d = FetchDescriptor<OutboxItem>()
        d.fetchLimit = 1
        let items = try context.fetch(d)
        guard let item = items.first else {
            throw OutboxBridgeError.malformedPayload(reason: "no items in outbox")
        }
        return OutboxItemSnapshot(
            id: item.id, kind: item.kind, status: item.status,
            attempts: item.attempts, lastError: item.lastError,
            nextAttemptAt: item.nextAttemptAt
        )
    }
    #endif

    // MARK: - Drain loop

    private func drainOnce() async {
        guard !isDraining else { return }
        guard !pausedForAuth else { return }
        isDraining = true
        publishStatus()
        defer {
            isDraining = false
            publishStatus()
        }

        while true {
            guard !pausedForAuth else { break }
            let now = clock.current()
            let batch = fetchBatch(now: now)
            if batch.isEmpty { break }

            for item in batch {
                await dispatchItem(item)
                publishStatus()
                if pausedForAuth { break }
            }
        }
    }

    private func fetchBatch(now: Date) -> [OutboxItem] {
        // SwiftData's predicate compiler handles enum equality via
        // rawValue lookup; comparing the row's `status` to a captured
        // enum value works in tests but is brittle across SwiftData
        // versions. We do a coarse fetch (just the time window) and
        // filter pending in memory, which is robust and the batch
        // size cap (50) keeps the cost trivial.
        //
        // The `sortBy: nextAttemptAt asc` ensures that when 7.3 introduces
        // inFlight/failed rows they don't crowd out eligible .pending rows
        // before the in-memory filter gets a chance to see them.
        var d = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> {
                $0.nextAttemptAt <= now
            },
            sortBy: [SortDescriptor(\OutboxItem.nextAttemptAt, order: .forward)]
        )
        d.fetchLimit = 50
        let rows = (try? context.fetch(d)) ?? []
        let pending = rows.filter { $0.status == .pending }
        // Sort by priority desc, then createdAt asc. Doing this in-memory
        // keeps the SwiftData predicate simple — fetchLimit caps the slice.
        return pending.sorted { lhs, rhs in
            if lhs.kind.priority != rhs.kind.priority {
                return lhs.kind.priority > rhs.kind.priority
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func dispatchItem(_ item: OutboxItem) async {
        item.status = .inFlight
        try? context.save()

        do {
            try await dispatch(kind: item.kind, payload: item.payload)
            context.delete(item)
            try? context.save()
        } catch let error {
            handle(error: error, item: item)
            try? context.save()
        }
    }

    private func handle(error: Error, item: OutboxItem) {
        let kindStr = String(describing: item.kind)

        // Bridge errors (decode failures, UUID parsing) are always permanent —
        // retrying won't fix corrupt local payload. Route them directly.
        if let bridgeError = error as? OutboxBridgeError {
            item.status = .failed
            item.lastError = String(describing: bridgeError).prefix(1024).description
            item.attempts += 1
            Self.log.error("permanent failure (bridge) on \(kindStr, privacy: .public): \(String(describing: bridgeError), privacy: .public)")
            return
        }

        let mapped = SupabaseError.map(error)
        let disposition = OutboxErrorClassifier.classify(mapped, for: item.kind)
        let errStr = String(describing: mapped).prefix(1024).description

        switch disposition {
        case .success:
            // Idempotent — treat as if it landed.
            context.delete(item)

        case .transient:
            item.attempts += 1
            item.lastError = errStr
            item.status = .pending
            let exp = pow(2.0, Double(item.attempts))
            let backoff = min(exp, 300.0) // cap at 5 min
            item.nextAttemptAt = clock.current().addingTimeInterval(backoff)

        case .auth:
            // Stop the drain pass, mark the queue paused. The auth-resume
            // wiring in slabbistApp (Task 10) calls unpause() + kick() once
            // SessionStore re-establishes the session.
            pausedForAuth = true
            item.status = .pending
            item.lastError = "Sign in to sync"
            statusSink(StatusUpdate(
                pendingCount: pendingCountValue(),
                isDraining: false,
                isPaused: true,
                lastError: nil
            ))

        case .permanent:
            item.status = .failed
            item.lastError = errStr
            item.attempts += 1
            Self.log.error("permanent failure on \(kindStr, privacy: .public): \(errStr, privacy: .public)")
        }
    }

    /// Decode `data` as `T`, rethrowing any `DecodingError` as
    /// `OutboxBridgeError.malformedPayload` so the error classifier
    /// routes it directly to `.failed` instead of the transient-retry path.
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw OutboxBridgeError.malformedPayload(reason: "decode \(type) failed: \(error)")
        }
    }

    private func dispatch(kind: OutboxKind, payload: Data) async throws {
        switch kind {
        case .insertScan:
            let p = try decode(OutboxPayloads.InsertScan.self, payload)
            try await repositories.scans.insert(try ScanDTO(from: p))

        case .insertLot:
            let p = try decode(OutboxPayloads.InsertLot.self, payload)
            try await repositories.lots.insert(try LotDTO(from: p))

        case .updateLot:
            let p = try decode(OutboxPayloads.UpdateLot.self, payload)
            guard let id = UUID(uuidString: p.id) else {
                throw OutboxBridgeError.malformedPayload(reason: "UpdateLot: invalid UUID")
            }
            var fields: [String: AnyJSON] = ["updated_at": .string(p.updated_at)]
            if let v = p.name   { fields["name"]   = .string(v) }
            if let v = p.notes  { fields["notes"]  = .string(v) }
            if let v = p.status { fields["status"] = .string(v) }
            try await repositories.lots.patch(id: id, fields: fields)

        case .deleteLot:
            let p = try decode(OutboxPayloads.DeleteLot.self, payload)
            guard let id = UUID(uuidString: p.id) else {
                throw OutboxBridgeError.malformedPayload(reason: "DeleteLot: invalid UUID")
            }
            try await repositories.lots.delete(id: id)

        case .updateScan:
            let p = try decode(OutboxPayloads.UpdateScan.self, payload)
            guard let id = UUID(uuidString: p.id) else {
                throw OutboxBridgeError.malformedPayload(reason: "UpdateScan: invalid UUID")
            }
            var fields: [String: AnyJSON] = [
                "status":     .string(p.status),
                "updated_at": .string(p.updated_at)
            ]
            if let v = p.graded_card_identity_id { fields["graded_card_identity_id"] = .string(v) }
            if let v = p.grade                   { fields["grade"]                   = .string(v) }
            try await repositories.scans.patch(id: id, fields: fields)

        case .updateScanOffer:
            let p = try decode(OutboxPayloads.UpdateScanOffer.self, payload)
            guard let id = UUID(uuidString: p.id) else {
                throw OutboxBridgeError.malformedPayload(reason: "UpdateScanOffer: invalid UUID")
            }
            var fields: [String: AnyJSON] = ["updated_at": .string(p.updated_at)]
            if let cents = p.offer_cents {
                guard let safe = Int(exactly: cents) else {
                    throw OutboxBridgeError.malformedPayload(reason: "UpdateScanOffer: offer_cents overflows Int")
                }
                fields["offer_cents"] = .integer(safe)
            } else {
                fields["offer_cents"] = .null
            }
            try await repositories.scans.patch(id: id, fields: fields)

        case .deleteScan:
            let p = try decode(OutboxPayloads.DeleteScan.self, payload)
            guard let id = UUID(uuidString: p.id) else {
                throw OutboxBridgeError.malformedPayload(reason: "DeleteScan: invalid UUID")
            }
            try await repositories.scans.delete(id: id)

        case .upsertVendor:
            let p = try decode(OutboxPayloads.UpsertVendor.self, payload)
            let dto = try VendorDTO(from: p)
            try await repositories.vendors.upsert(dto)

        case .archiveVendor:
            let p = try decode(OutboxPayloads.ArchiveVendor.self, payload)
            guard let id = UUID(uuidString: p.id) else {
                throw OutboxBridgeError.malformedPayload(reason: "ArchiveVendor: invalid UUID")
            }
            try await repositories.vendors.patch(
                id: id,
                fields: [
                    "archived_at": .string(p.archived_at),
                    "updated_at": .string(p.archived_at)
                ]
            )

        case .certLookupJob, .priceCompJob:
            // Group B kinds are out of scope for v1 — surface as permanent
            // failure so the classifier (7.3) routes them to .failed.
            throw OutboxBridgeError.malformedPayload(reason: "\(kind) not wired in v1 (Group B)")
        }
    }

    // MARK: - Status publishing

    private func publishStatus() {
        let count = pendingCountValue()
        let draining = isDraining
        statusSink(StatusUpdate(pendingCount: count, isDraining: draining, isPaused: nil, lastError: nil))
    }

    private func pendingCountValue() -> Int {
        // See `fetchBatch` for why we filter status in memory rather
        // than in the predicate.
        let rows = (try? context.fetch(FetchDescriptor<OutboxItem>())) ?? []
        return rows.lazy.filter { $0.status == .pending }.count
    }
}

// MARK: - Payload → DTO bridging

enum OutboxBridgeError: Error {
    case malformedPayload(reason: String)
}

extension ScanDTO {
    /// Bridge an `OutboxPayloads.InsertScan` (snake_case wire shape) to
    /// the camelCase `ScanDTO` the repository expects. Throws
    /// `OutboxBridgeError.malformedPayload` if any UUID field is invalid
    /// so that a corrupted SQLite row is routed to `lastError` rather
    /// than crashing the drain loop.
    init(from p: OutboxPayloads.InsertScan) throws {
        guard let id = UUID(uuidString: p.id),
              let storeId = UUID(uuidString: p.store_id),
              let lotId = UUID(uuidString: p.lot_id),
              let userId = UUID(uuidString: p.user_id) else {
            throw OutboxBridgeError.malformedPayload(reason: "InsertScan: invalid UUID")
        }
        let iso = OutboxDateFormatter.iso8601
        self.init(
            id: id,
            storeId: storeId,
            lotId: lotId,
            userId: userId,
            grader: p.grader,
            certNumber: p.cert_number,
            grade: nil,
            status: p.status,
            ocrRawText: p.ocr_raw_text,
            ocrConfidence: p.ocr_confidence,
            capturedPhotoURL: nil,
            offerCents: nil,
            createdAt: iso.date(from: p.created_at) ?? Date(),
            updatedAt: iso.date(from: p.updated_at) ?? Date()
        )
    }
}

extension LotDTO {
    /// Bridge an `OutboxPayloads.InsertLot` (snake_case wire shape) to
    /// the camelCase `LotDTO` the repository expects. Throws
    /// `OutboxBridgeError.malformedPayload` if any UUID field is invalid.
    /// Optional fields not present in `InsertLot` (vendorName, vendorContact,
    /// offeredTotalCents, marginRuleId, transactionStamp) default to nil.
    init(from p: OutboxPayloads.InsertLot) throws {
        guard let id           = UUID(uuidString: p.id),
              let storeId      = UUID(uuidString: p.store_id),
              let createdById  = UUID(uuidString: p.created_by_user_id) else {
            throw OutboxBridgeError.malformedPayload(reason: "InsertLot: invalid UUID")
        }
        let iso = OutboxDateFormatter.iso8601
        self.init(
            id: id,
            storeId: storeId,
            createdByUserId: createdById,
            name: p.name,
            notes: p.notes,
            status: p.status,
            vendorName: nil,
            vendorContact: nil,
            offeredTotalCents: nil,
            marginRuleId: nil,
            transactionStamp: nil,
            createdAt: iso.date(from: p.created_at) ?? Date(),
            updatedAt: iso.date(from: p.updated_at) ?? Date()
        )
    }
}

extension VendorDTO {
    /// Bridge an `OutboxPayloads.UpsertVendor` (snake_case wire shape) to
    /// the camelCase `VendorDTO` the repository expects. Throws
    /// `OutboxBridgeError.malformedPayload` if any UUID or timestamp field
    /// is invalid. `created_at` is server-defaulted on insert; we mirror
    /// `updated_at` here because the Postgres `on conflict` path preserves
    /// the original `created_at` and the wire shape does not carry it.
    init(from p: OutboxPayloads.UpsertVendor) throws {
        guard let id = UUID(uuidString: p.id),
              let storeId = UUID(uuidString: p.store_id) else {
            throw OutboxBridgeError.malformedPayload(reason: "UpsertVendor: invalid UUID")
        }
        let iso = OutboxDateFormatter.iso8601
        guard let updatedAt = iso.date(from: p.updated_at) else {
            throw OutboxBridgeError.malformedPayload(reason: "UpsertVendor: invalid updated_at")
        }
        let archivedAt = p.archived_at.flatMap { iso.date(from: $0) }
        self.init(
            id: id,
            storeId: storeId,
            displayName: p.display_name,
            contactMethod: p.contact_method,
            contactValue: p.contact_value,
            notes: p.notes,
            archivedAt: archivedAt,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}

/// Cached `ISO8601DateFormatter` — the type is heavy to allocate (locale,
/// calendar, regex). One per process is enough; the formatter is thread-safe
/// per Apple docs.
enum OutboxDateFormatter {
    static let iso8601: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()
}
