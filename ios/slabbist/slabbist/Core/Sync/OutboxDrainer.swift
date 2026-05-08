import Foundation
import SwiftData

/// Background actor that drains the outbox.
///
/// 7.1 scope: skeleton + `insertScan` happy path. Other kinds will
/// trip a `fatalError` on dispatch — sub-phases 7.2–7.5 fill them in.
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
    }

    private let repositories: AppRepositories
    private let clock: any OutboxClock
    private let statusSink: @Sendable (StatusUpdate) -> Void
    private var isDraining: Bool = false

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
    #endif

    // MARK: - Drain loop

    private func drainOnce() async {
        guard !isDraining else { return }
        isDraining = true
        publishStatus()
        defer {
            isDraining = false
            publishStatus()
        }

        while true {
            let now = clock.current()
            let batch = fetchBatch(now: now)
            if batch.isEmpty { break }

            for item in batch {
                await dispatchItem(item)
                publishStatus()
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
        } catch {
            // Full error handling lands in 7.3 (classifier + backoff).
            // For 7.1 we simply revert to .pending so the drain loop
            // can break out (the predicate `nextAttemptAt <= now` keeps
            // it eligible). The lastError string is best-effort context.
            item.status = .pending
            item.lastError = String(describing: error).prefix(1024).description
            try? context.save()
        }
    }

    private func dispatch(kind: OutboxKind, payload: Data) async throws {
        switch kind {
        case .insertScan:
            let p = try JSONDecoder().decode(OutboxPayloads.InsertScan.self, from: payload)
            try await repositories.scans.insert(try ScanDTO(from: p))
        case .insertLot,
             .updateLot,
             .deleteLot,
             .updateScan,
             .updateScanOffer,
             .deleteScan,
             .certLookupJob,
             .priceCompJob:
            fatalError("dispatch for \(kind) not yet implemented (lands in 7.2)")
        }
    }

    // MARK: - Status publishing

    private func publishStatus() {
        let count = pendingCountValue()
        let draining = isDraining
        statusSink(StatusUpdate(pendingCount: count, isDraining: draining, isPaused: nil))
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

/// Cached `ISO8601DateFormatter` — the type is heavy to allocate (locale,
/// calendar, regex). One per process is enough; the formatter is thread-safe
/// per Apple docs.
enum OutboxDateFormatter {
    static let iso8601: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()
}
