import Foundation
import OSLog
import SwiftData
import Supabase

/// Background actor that drains the outbox.
///
/// Group A complete (insertScan, insertLot, deleteLot,
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
        var failedCount: Int
        var isDraining: Bool
        var isPaused: Bool?
        var authState: AuthPauseState?
        var lastError: String?
    }

    /// Stranded-`.inFlight` recovery threshold. A row that has been
    /// `.inFlight` longer than this is treated as a crash mid-dispatch and
    /// demoted to `.pending` so it can retry on the next drain pass.
    static let strandedInFlightThreshold: TimeInterval = 60

    /// Number of consecutive auth pauses before the pill escalates from
    /// "Reconnecting…" to "Sign in to sync". supabase-swift auto-refresh
    /// usually resolves within one or two retries; sustained 401s are the
    /// "session is really gone" signal.
    static let signedOutEscalationThreshold: Int = 2

    private let repositories: AppRepositories
    private let clock: any OutboxClock
    private let statusSink: @Sendable (StatusUpdate) -> Void
    private var isDraining: Bool = false
    private var pausedForAuth: Bool = false
    /// A5: consecutive auth-pause attempts. Resets on a successful
    /// dispatch (not on `unpause()`). Drives the `.reconnecting →
    /// .signedOut` escalation in the pill copy.
    private var consecutiveAuthAttempts: Int = 0

    // Note: there is intentionally no `kickPending` coalesce flag. The
    // drainer's outer `while true { let batch = fetchBatch ...; if empty
    // break; for item in batch { await dispatchItem } }` loop already
    // catches rows enqueued mid-drain — each iteration re-fetches. A
    // separate flag would only help if SwiftData returned a stale fetch
    // result (drainer's context lagging the producer's commit); we've
    // never observed that and the test suite exercises mid-drain enqueue
    // via the natural-loop path.

    /// Called by the auth resume path (Task 10) when SessionStore signs back
    /// in. Clears the auth-pause flag so the next kick can proceed.
    /// Does NOT clear `consecutiveAuthAttempts` — the counter persists
    /// across unpause cycles so that supabase-swift's auto-refresh hitting
    /// repeated 401s eventually escalates the pill copy to "Sign in to
    /// sync". A successful dispatch (or any non-auth disposition) resets
    /// the counter; that's what proves auth actually recovered.
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
        nextAttemptAt: Date,
        status: OutboxItemStatus = .pending
    ) throws {
        let item = OutboxItem(
            id: id,
            kind: kind,
            payload: payload,
            status: status,
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

    /// Test-only: count rows whose status equals `status`. Used by A3
    /// starvation tests to assert the .pending lane drained even with a
    /// fat .failed neighbourhood.
    func _testCount(status: OutboxItemStatus) -> Int {
        let target = status
        let rows = (try? context.fetch(FetchDescriptor<OutboxItem>())) ?? []
        return rows.lazy.filter { $0.status == target }.count
    }

    /// Test-only: force a row into `.inFlight` with a stale `nextAttemptAt`
    /// so the A1 recovery pass can be exercised without flakily relying on
    /// real-time clocks. Inserts a `.pending` row first, then mutates.
    func _testSeedStrandedInFlight(
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
            status: .inFlight,
            attempts: 0,
            createdAt: createdAt,
            nextAttemptAt: nextAttemptAt
        )
        context.insert(item)
        try context.save()
    }

    /// Test-only: snapshot the row count by status by fetching from disk
    /// (bypasses the actor's cached counts so tests can verify storage
    /// truth independent of cache correctness).
    func _testStatusSnapshot() -> (pending: Int, failed: Int) {
        let rows = (try? context.fetch(FetchDescriptor<OutboxItem>())) ?? []
        var pending = 0
        var failed = 0
        for row in rows {
            switch row.status {
            case .pending:  pending += 1
            case .failed:   failed += 1
            case .inFlight, .completed: break
            }
        }
        return (pending, failed)
    }

    /// Test-only: read the cached counts the drainer publishes via
    /// `publishStatus()`. Used to verify the cache stays in sync with
    /// disk across the per-dispatch mutation path.
    func _testCachedCounts() -> (pending: Int, failed: Int) {
        (cachedPendingCount, cachedFailedCount)
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
        guard !isDraining else {
            // A second kick landed while we're draining. The outer loop
            // re-fetches every iteration, so any row that's already in
            // the local SwiftData store will be picked up before we exit;
            // no flag-and-re-pass needed.
            return
        }
        guard !pausedForAuth else { return }
        isDraining = true
        // Refresh from disk first so the "Syncing N…" copy reflects the
        // post-producer state (producers write from other contexts and
        // the actor wouldn't otherwise see those rows in its cache).
        refreshStatusCache()
        publishStatus()
        defer {
            isDraining = false
            publishStatus()
        }

        // A1: any row left `.inFlight` from a previous run (crash, abrupt
        // termination) needs to come back to `.pending` so it gets retried.
        // Run this before the first fetch so the recovered rows show up in
        // the batch.
        recoverStrandedInFlight()

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

    /// A1: demote rows stuck in `.inFlight` longer than the strand
    /// threshold. These come from a crash / suspension mid-dispatch where
    /// the row got flipped but never made it through `context.delete`.
    /// Without this, `fetchBatch` (which only returns `.pending`) would
    /// skip them forever.
    private func recoverStrandedInFlight() {
        let cutoff = clock.current().addingTimeInterval(-Self.strandedInFlightThreshold)
        // SwiftData `#Predicate` enum equality is unreliable on iOS 26.4
        // (see fetchBatch). Fetch by Date and filter in memory — the
        // expected count of stranded rows is at most "a handful per launch."
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> { item in
                item.nextAttemptAt <= cutoff
            }
        )
        let candidates = (try? context.fetch(descriptor)) ?? []
        let stranded = candidates.filter { $0.status == .inFlight }
        guard !stranded.isEmpty else { return }
        for item in stranded {
            item.status = .pending
            // Eligible immediately; the row's been stuck long enough that
            // we want it to compete for the next batch fairly.
            item.nextAttemptAt = clock.current()
        }
        do {
            try context.save()
            AppLog.outbox.notice("recovered \(stranded.count, privacy: .public) stranded inFlight row(s)")
            // Stranded rows just rejoined the pending lane.
            adjustCache(pendingDelta: stranded.count)
        } catch {
            AppLog.outbox.error("failed to save inFlight recovery: \(String(describing: error), privacy: .public)")
        }
    }

    private func fetchBatch(now: Date) -> [OutboxItem] {
        // A3: SwiftData's `#Predicate` doesn't reliably support equality
        // against a captured enum case on iOS 26.4 (the SQLite layer
        // assertionFailure'd in practice under our @Model schema). The
        // workaround that keeps the pending lane from starving without
        // touching the schema: drop `fetchLimit` from the SwiftData call
        // entirely and apply the cap AFTER the in-memory filter. We
        // assume the local outbox stays modest (< a few thousand rows
        // in the worst case) and predicate-pushdown isn't worth a
        // brittle macro dance.
        let d = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> { item in
                item.nextAttemptAt <= now
            },
            sortBy: [SortDescriptor(\OutboxItem.nextAttemptAt, order: .forward)]
        )
        // Intentionally NO fetchLimit. A `fetchLimit` here caps the SQL slice
        // BEFORE the in-memory `.pending` filter runs, so a fat backlog of
        // `.failed` rows (which also satisfy `nextAttemptAt <= now`) could
        // fill the slice and starve the pending lane forever — the exact
        // pathology the comment above warns about, which a stray
        // `fetchLimit = 1000` had quietly reintroduced. The `.pending`
        // filter + post-sort `.prefix(50)` cap wire effort instead, and
        // `refreshStatusCache` already scans the full table each pass, so
        // this adds no new worst-case fetch cost.
        let allRows = (try? context.fetch(d)) ?? []
        let rows = Array(allRows.lazy.filter { $0.status == .pending }.prefix(50))
        // Sort by priority desc, then createdAt asc. Doing this in-memory
        // keeps the SwiftData predicate simple — fetchLimit caps the slice.
        return rows.sorted { lhs, rhs in
            if lhs.kind.priority != rhs.kind.priority {
                return lhs.kind.priority > rhs.kind.priority
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// A1: persist a SwiftData save. Returns true on success. Logs the
    /// concrete error on failure so we can debug strands without guessing
    /// at root cause from "save quietly returned".
    ///
    /// No retry: SwiftData `save()` failures from disk-full / FK violation
    /// / context contention don't self-heal on an immediate same-context
    /// retry (the Critic was right). If save throws, the caller falls
    /// back — revert in-memory mutation, leave the row pending, let the
    /// next external kick re-try with potentially-cleared pressure.
    @discardableResult
    private func tryPersist(reason: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            AppLog.outbox.error("context.save() failed for \(reason, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func dispatchItem(_ item: OutboxItem) async {
        // A1: flip to .inFlight. If the save fails here the row never
        // makes it into the .inFlight lane in storage, but we already
        // mutated the in-memory model. Revert the mutation and bail out
        // — the next drain pass will pick it up. A1's recoverStrandedInFlight
        // is the second safety net for cases where the save *succeeded*
        // but we crash before completing dispatch.
        item.status = .inFlight
        // Stamp the in-flight start time onto `nextAttemptAt`. Recovery
        // (`recoverStrandedInFlight`) treats `nextAttemptAt <= now -
        // threshold` as "stranded", so this field has to mean "in-flight
        // since" while a row is `.inFlight`. Previously it kept the prior
        // backoff value, which for a retried row sits in the future — so a
        // crash mid-dispatch left the row `.inFlight` with a future
        // `nextAttemptAt` that the recovery predicate could never match,
        // stranding the write permanently. A transient failure in `handle`
        // overwrites this with a fresh backoff; a success deletes the row.
        item.nextAttemptAt = clock.current()
        if !tryPersist(reason: "mark inFlight (\(item.kind))") {
            item.status = .pending
            // Don't propagate — caller is the drain loop and the row
            // will be retried on the next external kick or scheduled pass.
            return
        }
        // Row left the .pending lane.
        adjustCache(pendingDelta: -1)

        do {
            try await dispatch(kind: item.kind, payload: item.payload)
            // A5: a real wire success proves auth is good — reset the
            // sustained-auth counter so any future 401 starts at
            // .reconnecting again instead of immediately accusing the
            // user of being signed out.
            consecutiveAuthAttempts = 0
            // Successful dispatch on the wire — drop the row.
            context.delete(item)
            if !tryPersist(reason: "delete after dispatch (\(item.kind))") {
                // A1: we already succeeded server-side. If we can't
                // persist the delete, the next launch would re-fire the
                // row (silent double-send). Surface it via lastError so
                // the user sees something went wrong. Cache stays as-is
                // (we already decremented pending; the row is gone from
                // the user's perspective even if SwiftData kept it).
                AppLog.outbox.error("dispatched \(String(describing: item.kind), privacy: .public) but failed to persist delete — row may re-fire on next launch")
                statusSink(StatusUpdate(
                    pendingCount: cachedPendingCount,
                    failedCount: cachedFailedCount,
                    isDraining: isDraining,
                    isPaused: nil,
                    authState: nil,
                    lastError: "Could not persist sync completion"
                ))
            }
        } catch let error {
            // `handle` mutated the row; we track the resulting lane
            // transition via `handle`'s return so the cache stays accurate.
            let postState = handle(error: error, item: item)
            if !tryPersist(reason: "handle error (\(item.kind))") {
                // The `handle` mutation didn't stick. Revert the
                // in-memory `.inFlight` so the row can be retried; the
                // recovery pass + fetchBatch's pending-only predicate
                // means a stuck `.inFlight` is a real correctness bug,
                // not just lossy telemetry.
                item.status = .pending
                // Row is back where we found it: pending lane regains the
                // count we decremented above.
                adjustCache(pendingDelta: +1)
                return
            }
            switch postState {
            case .returnedToPending:
                // .transient / .auth pushed it back to pending — restore.
                adjustCache(pendingDelta: +1)
            case .markedFailed:
                adjustCache(failedDelta: +1)
            case .droppedAsSuccess:
                // Idempotent success — already decremented pending; no
                // failed bucket change.
                break
            }
        }
    }

    /// Post-`handle` lane transition. Used to drive the cache incrementally
    /// so `publishStatus()` doesn't need to re-scan SwiftData.
    private enum DispositionOutcome {
        case returnedToPending  // .transient or .auth
        case markedFailed       // .permanent or bridge error
        case droppedAsSuccess   // idempotent success (row deleted)
    }

    private func handle(error: Error, item: OutboxItem) -> DispositionOutcome {
        let kindStr = String(describing: item.kind)

        // Bridge errors (decode failures, UUID parsing) are always permanent —
        // retrying won't fix corrupt local payload. Route them directly.
        if let bridgeError = error as? OutboxBridgeError {
            item.status = .failed
            item.lastError = String(describing: bridgeError).prefix(1024).description
            item.attempts += 1
            // A5: bridge failures aren't auth pauses — successful classification
            // path so reset the auth counter.
            consecutiveAuthAttempts = 0
            AppLog.outbox.error("permanent failure (bridge) on \(kindStr, privacy: .public): \(String(describing: bridgeError), privacy: .public)")
            return .markedFailed
        }

        let mapped = SupabaseError.map(error)
        let disposition = OutboxErrorClassifier.classify(mapped, for: item.kind)
        let errStr = String(describing: mapped).prefix(1024).description

        switch disposition {
        case .success:
            // Idempotent — treat as if it landed.
            context.delete(item)
            consecutiveAuthAttempts = 0
            return .droppedAsSuccess

        case .transient:
            item.attempts += 1
            item.lastError = errStr
            item.status = .pending
            let exp = pow(2.0, Double(item.attempts))
            let backoff = min(exp, 300.0) // cap at 5 min
            item.nextAttemptAt = clock.current().addingTimeInterval(backoff)
            consecutiveAuthAttempts = 0
            return .returnedToPending

        case let .auth(initialState):
            // Stop the drain pass, mark the queue paused. The auth-resume
            // wiring in slabbistApp (Task 10) calls unpause() + kick() once
            // SessionStore re-establishes the session.
            pausedForAuth = true
            item.status = .pending
            consecutiveAuthAttempts += 1

            // A5: escalate the pill copy from "Reconnecting…" to "Sign in
            // to sync" after repeated auth pauses. supabase-swift auto-
            // refresh usually resolves within one or two attempts; if it
            // keeps failing the refresh token is genuinely gone and the
            // user has to act. We can't always read the distinction off
            // the AuthError at this layer (see OutboxErrorClassifier),
            // so attempts-based escalation is the safer default.
            let escalatedState: AuthPauseState =
                consecutiveAuthAttempts >= Self.signedOutEscalationThreshold
                ? .signedOut
                : initialState
            let copy: String
            switch escalatedState {
            case .reconnecting: copy = "Reconnecting…"
            case .signedOut:    copy = "Sign in to sync"
            }
            item.lastError = copy
            // Use the cache rather than re-scanning. The cache is fresh:
            // dispatchItem just decremented pending by 1 for the row we're
            // about to push back to pending — the caller (dispatchItem)
            // will re-add +1 via the `.returnedToPending` outcome below.
            // We emit the auth-paused status using the post-restore counts.
            statusSink(StatusUpdate(
                pendingCount: cachedPendingCount + 1,
                failedCount: cachedFailedCount,
                isDraining: false,
                isPaused: true,
                authState: escalatedState,
                lastError: copy
            ))
            return .returnedToPending

        case .permanent:
            item.status = .failed
            item.lastError = errStr
            item.attempts += 1
            consecutiveAuthAttempts = 0
            AppLog.outbox.error("permanent failure on \(kindStr, privacy: .public): \(errStr, privacy: .public)")
            return .markedFailed
        }
    }

    // MARK: - Failure-row affordances (A2)

    /// Reset a `.failed` row back to `.pending` so the drainer retries it
    /// from scratch. The failures sheet calls this when the user taps
    /// "Retry". Clears `lastError` so a stale message doesn't linger.
    func retryFailed(id: UUID) {
        let target = id
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> { $0.id == target }
        )
        guard let item = (try? context.fetch(descriptor))?.first else { return }
        guard item.status == .failed else { return }
        item.status = .pending
        item.attempts = 0
        item.lastError = nil
        item.nextAttemptAt = clock.current()
        if tryPersist(reason: "retry failed (\(item.kind))") {
            adjustCache(pendingDelta: +1, failedDelta: -1)
        }
        publishStatus()
    }

    /// Permanently drop a `.failed` row. The failures sheet calls this
    /// when the user taps "Discard" — the local mutation is the only
    /// source for an outbox row, so removing it cleanly is the user-
    /// initiated escape hatch.
    func discardFailed(id: UUID) {
        let target = id
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> { $0.id == target }
        )
        guard let item = (try? context.fetch(descriptor))?.first else { return }
        guard item.status == .failed else { return }
        context.delete(item)
        if tryPersist(reason: "discard failed (\(item.kind))") {
            adjustCache(failedDelta: -1)
        }
        publishStatus()
    }

    /// Snapshot of every `.failed` row, sorted oldest-first. The failures
    /// sheet renders this list. Returns plain value types so it can cross
    /// the actor boundary safely. Filters in memory because SwiftData
    /// `#Predicate` enum equality is brittle on iOS 26.4.
    func listFailed() -> [FailedRowSnapshot] {
        let descriptor = FetchDescriptor<OutboxItem>(
            sortBy: [SortDescriptor(\OutboxItem.createdAt, order: .forward)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        let rows = all.filter { $0.status == .failed }
        return rows.map { item in
            FailedRowSnapshot(
                id: item.id,
                kind: item.kind,
                lastError: item.lastError,
                attempts: item.attempts,
                createdAt: item.createdAt
            )
        }
    }

    /// Sendable snapshot of an outbox row for the failures sheet.
    struct FailedRowSnapshot: Sendable, Identifiable, Equatable {
        let id: UUID
        let kind: OutboxKind
        let lastError: String?
        let attempts: Int
        let createdAt: Date
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
            if let cents = p.vendor_ask_cents {
                guard let safe = Int(exactly: cents) else {
                    throw OutboxBridgeError.malformedPayload(reason: "UpdateScanOffer: vendor_ask_cents overflows Int")
                }
                fields["vendor_ask_cents"] = .integer(safe)
            } else {
                fields["vendor_ask_cents"] = .null
            }
            try await repositories.scans.patch(id: id, fields: fields)

        case .updateScanBuyPrice:
            let p = try decode(OutboxPayloads.UpdateScanBuyPrice.self, payload)
            guard let id = UUID(uuidString: p.id) else {
                throw OutboxBridgeError.malformedPayload(reason: "UpdateScanBuyPrice: invalid UUID")
            }
            var fields: [String: AnyJSON] = [
                "buy_price_overridden": .bool(p.buy_price_overridden),
                "updated_at": .string(p.updated_at)
            ]
            if let cents = p.buy_price_cents {
                guard let safe = Int(exactly: cents) else {
                    throw OutboxBridgeError.malformedPayload(reason: "UpdateScanBuyPrice: buy_price_cents overflows Int")
                }
                fields["buy_price_cents"] = .integer(safe)
            } else {
                fields["buy_price_cents"] = .null
            }
            try await repositories.scans.patch(id: id, fields: fields)

        case .updateScanComp:
            let p = try decode(OutboxPayloads.UpdateScanComp.self, payload)
            guard let id = UUID(uuidString: p.id) else {
                throw OutboxBridgeError.malformedPayload(reason: "UpdateScanComp: invalid UUID")
            }
            var fields: [String: AnyJSON] = [
                "comp_snapshot_at": .string(p.comp_snapshot_at),
                "updated_at":       .string(p.updated_at)
            ]
            fields["comp_snapshot"] = p.comp_snapshot.map(AnyJSON.string) ?? .null
            try await repositories.scans.patch(id: id, fields: fields)

        case .updateLotOffer:
            let p = try decode(OutboxPayloads.UpdateLotOffer.self, payload)
            guard let id = UUID(uuidString: p.id) else {
                throw OutboxBridgeError.malformedPayload(reason: "UpdateLotOffer: invalid UUID")
            }
            // These fields are sent unconditionally (null when locally
            // cleared) because the local lot is the offline-first authority
            // for the offer. The previous `if let` guards dropped nil fields
            // from the patch, so detaching a vendor or reverting the lot
            // margin to the ladder mutated SwiftData but never reached the
            // server — the two sides diverged silently and forever.
            var fields: [String: AnyJSON] = [
                "updated_at":           .string(p.updated_at),
                "vendor_id":            p.vendor_id.map(AnyJSON.string) ?? .null,
                "vendor_name_snapshot": p.vendor_name_snapshot.map(AnyJSON.string) ?? .null,
                "margin_pct_snapshot":  p.margin_pct_snapshot.map(AnyJSON.double) ?? .null
            ]
            if let v = p.lot_offer_state           { fields["lot_offer_state"]            = .string(v) }
            if let v = p.lot_offer_state_updated_at {
                fields["lot_offer_state_updated_at"] = .string(v)
            }
            try await repositories.lots.patch(id: id, fields: fields)

        case .recomputeLotOffer:
            let p = try decode(OutboxPayloads.RecomputeLotOffer.self, payload)
            guard let lotId = UUID(uuidString: p.lot_id) else {
                throw OutboxBridgeError.malformedPayload(reason: "RecomputeLotOffer: invalid lot_id")
            }
            // The Edge Function returns 409 when the lot is in a terminal
            // state (the iOS local state is the authority for completed
            // lots); treat that as success so the outbox item drains.
            //
            // D2: when the call succeeds, hydrate the response back onto
            // the local Lot. The server-computed offered_total_cents +
            // lot_offer_state used to be discarded — any server-driven
            // state change (admin override, future auto-expiry) would be
            // invisible to the iOS client. The hydrator runs on mainContext
            // so @Query-subscribed views update without a re-render.
            do {
                let response = try await repositories.lots.recomputeOffer(lotId: lotId)
                try await LotOfferRecomputeHydrator.apply(
                    response: response,
                    container: modelContainer
                )
            } catch let error as FunctionsError {
                if case let .httpError(code, _) = error, code == 409 {
                    // Terminal-state guard; local cache is fine.
                } else {
                    throw error
                }
            }

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

        case .commitTransaction:
            let p = try decode(OutboxPayloads.CommitTransaction.self, payload)
            // The Edge Function returns 409 (WRONG_STATE / LOT_STATE_RACED)
            // when the lot is no longer in `.accepted` by the time the
            // server tries to flip it. Treat that as a resolved outcome
            // for this outbox attempt: a future producer (or a manual
            // operator action) is the authority for what state the lot
            // should land in. Without this, the FunctionsError 409 falls
            // through SupabaseError.map → .transport → .transient and the
            // outbox retries forever. Mirrors the recomputeLotOffer case.
            do {
                let resp = try await repositories.transactions.commit(payload: .init(
                    lot_id: p.lot_id,
                    payment_method: p.payment_method,
                    payment_reference: p.payment_reference,
                    vendor_id: p.vendor_id,
                    vendor_name_override: p.vendor_name_override
                ))
                try await TransactionsHydrator.upsert(commitResponse: resp, container: modelContainer)
            } catch let error as FunctionsError {
                if case let .httpError(code, _) = error, code == 409 {
                    // Conflict drained — local state will reconcile via the
                    // next patch from another producer.
                } else {
                    throw error
                }
            }

        case .voidTransaction:
            let p = try decode(OutboxPayloads.VoidTransaction.self, payload)
            guard let txnId = UUID(uuidString: p.transaction_id) else {
                throw OutboxBridgeError.malformedPayload(reason: "VoidTransaction: invalid UUID")
            }
            // 409 (ALREADY_VOIDED) is convergent — the server already has the
            // void row. Drain the outbox item; the hydrator will pick the
            // server's authoritative `voided_at` up on the next sync.
            do {
                let resp = try await repositories.transactions.void(transactionId: txnId, reason: p.reason)
                try await TransactionsHydrator.upsert(voidResponse: resp, container: modelContainer)
            } catch let error as FunctionsError {
                if case let .httpError(code, _) = error, code == 409 {
                    // Already voided server-side; nothing more to do here.
                } else {
                    throw error
                }
            }

        case .updateStoreMargin:
            let p = try decode(OutboxPayloads.UpdateStoreMargin.self, payload)
            guard let id = UUID(uuidString: p.id) else {
                throw OutboxBridgeError.malformedPayload(reason: "UpdateStoreMargin: invalid UUID")
            }
            // `margin_ladder` is a JSONB column on `stores`; the payload
            // carries the canonical JSON string the iOS app already
            // serialized. Decode it into AnyJSON so Postgrest sends the
            // value as a true JSON array, not a JSON-encoded string.
            guard let ladderData = p.margin_ladder_json.data(using: .utf8) else {
                throw OutboxBridgeError.malformedPayload(reason: "UpdateStoreMargin: ladder JSON not UTF-8")
            }
            let ladder: AnyJSON
            do {
                ladder = try JSONDecoder().decode(AnyJSON.self, from: ladderData)
            } catch {
                throw OutboxBridgeError.malformedPayload(reason: "UpdateStoreMargin: ladder JSON decode failed: \(error)")
            }
            try await repositories.stores.patch(
                id: id,
                fields: ["margin_ladder": ladder]
            )

        case .certLookupJob, .priceCompJob:
            // Group B kinds are out of scope for v1 — surface as permanent
            // failure so the classifier (7.3) routes them to .failed.
            throw OutboxBridgeError.malformedPayload(reason: "\(kind) not wired in v1 (Group B)")
        }
    }

    // MARK: - Status publishing

    /// Cached lane counts so the hot publish path (called after every
    /// dispatched item) doesn't re-scan the entire OutboxItem table.
    /// `refreshStatusCache()` reloads from SwiftData at the start of each
    /// drain pass (and after recovery); the drainer's own transitions
    /// update the cache incrementally via `adjustCache`.
    private var cachedPendingCount: Int = 0
    private var cachedFailedCount: Int = 0

    private func publishStatus() {
        statusSink(StatusUpdate(
            pendingCount: cachedPendingCount,
            failedCount: cachedFailedCount,
            isDraining: isDraining,
            isPaused: nil,
            authState: nil,
            lastError: nil
        ))
    }

    /// Reload `(pending, failed)` from SwiftData. Called at the start of
    /// every drain pass (after `recoverStrandedInFlight` may have demoted
    /// rows) so producer-driven inserts from other contexts are reflected.
    /// In-memory bucketing is the only correct path here — see
    /// `OutboxPredicateProbeTests` for why the predicate-pushed forms trap.
    /// This is the ONLY place the full table is scanned per drain.
    private func refreshStatusCache() {
        let rows = (try? context.fetch(FetchDescriptor<OutboxItem>())) ?? []
        var pending = 0
        var failed = 0
        for row in rows {
            switch row.status {
            case .pending:  pending += 1
            case .failed:   failed += 1
            case .inFlight, .completed: break
            }
        }
        cachedPendingCount = pending
        cachedFailedCount = failed
    }

    /// Incremental cache update applied by the drainer when it knows the
    /// transition. Keeps the per-dispatch `publishStatus()` cost at O(1).
    private func adjustCache(pendingDelta: Int = 0, failedDelta: Int = 0) {
        cachedPendingCount = max(0, cachedPendingCount + pendingDelta)
        cachedFailedCount = max(0, cachedFailedCount + failedDelta)
    }
}

// MARK: - Payload → DTO bridging

enum OutboxBridgeError: Error {
    case malformedPayload(reason: String)
}

nonisolated extension ScanDTO {
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
            vendorAskCents: nil,
            buyPriceCents: nil,
            buyPriceOverridden: false,
            createdAt: iso.date(from: p.created_at) ?? Date(),
            updatedAt: iso.date(from: p.updated_at) ?? Date()
        )
    }
}

nonisolated extension LotDTO {
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

nonisolated extension VendorDTO {
    /// Bridge an `OutboxPayloads.UpsertVendor` (snake_case wire shape) to
    /// the camelCase `VendorDTO` the repository expects. Throws
    /// `OutboxBridgeError.malformedPayload` if any UUID or timestamp field
    /// is invalid. The wire payload carries the original `created_at` so
    /// the Postgres on-conflict UPSERT preserves it instead of overwriting
    /// it with a synthesised value at retry time.
    init(from p: OutboxPayloads.UpsertVendor) throws {
        guard let id = UUID(uuidString: p.id),
              let storeId = UUID(uuidString: p.store_id) else {
            throw OutboxBridgeError.malformedPayload(reason: "UpsertVendor: invalid UUID")
        }
        let iso = OutboxDateFormatter.iso8601
        guard let createdAt = iso.date(from: p.created_at) else {
            throw OutboxBridgeError.malformedPayload(reason: "UpsertVendor: invalid created_at")
        }
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
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// Cached `ISO8601DateFormatter` — the type is heavy to allocate (locale,
/// calendar, regex). One per process is enough; the formatter is thread-safe
/// per Apple docs.
nonisolated enum OutboxDateFormatter {
    static let iso8601: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()
}
