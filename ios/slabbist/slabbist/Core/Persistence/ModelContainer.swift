import Foundation
import OSLog
import SwiftData

enum AppModelContainer {
    /// Sidecar filename living next to the SwiftData store. Holds JSON-
    /// encoded `OutboxItemSnapshot`s while migration recovery is in
    /// progress. Survives app kill: every static-init pass replays an
    /// orphan sidecar BEFORE attempting normal container open, so a
    /// kill between "delete store" and "save restored rows" can't lose
    /// the user's writes silently.
    static let recoverySidecarFilename = "slabbist.outbox-recovery.json"

    static let shared: ModelContainer = {
        let schema = Schema([
            Store.self,
            StoreMember.self,
            Lot.self,
            Scan.self,
            Vendor.self,
            OutboxItem.self,
            GradedCardIdentity.self,
            GradedMarketSnapshot.self,
            StoreTransaction.self,
            TransactionLine.self
            // Plan 2 adds: GradedCard
        ])
        let configurationName = "slabbist"
        let config = ModelConfiguration(configurationName, schema: schema, isStoredInMemoryOnly: false)
        let appSupport = URL.applicationSupportDirectory
        let sidecarURL = appSupport.appending(path: recoverySidecarFilename)

        // P0.4 — Orphan sidecar replay. If a previous launch crashed
        // between "delete store" and "save restored rows", a sidecar
        // JSON file is still on disk. We must NOT proceed into normal
        // container open until we've at least logged its existence,
        // because that container open *might* succeed (the new store
        // file is empty) and we'd be hiding the surviving snapshots
        // forever. We replay AFTER the rebuild step below — that's the
        // only context with a usable container — but discovering the
        // sidecar here lets us route through recovery regardless of
        // whether the normal open path succeeds.
        let orphanSnapshots = readSidecar(at: sidecarURL)
        if !orphanSnapshots.isEmpty {
            AppLog.outbox.notice(
                "ModelContainer: found orphan recovery sidecar with \(orphanSnapshots.count, privacy: .public) outbox snapshot(s) from a prior crashed migration"
            )
        }

        // Fast path: no orphan sidecar AND normal open succeeds.
        if orphanSnapshots.isEmpty {
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                AppLog.outbox.notice(
                    "ModelContainer normal open failed (\(String(describing: type(of: error)), privacy: .public)); entering migration recovery"
                )
                // Fall through to recovery path below.
            }
        }

        // Recovery path. GradedMarketSnapshot reshapes are mostly
        // lightweight-migratable when new attributes have default
        // values. When migration still fails — e.g. from a previous
        // build that landed before the default existed, leaving the
        // store in a half-migrated state — we have to blow the store
        // away. BUT: the outbox is the only place unsynced user writes
        // live. Naively deleting the store throws those rows away —
        // silent data loss. So before deletion, try to open a tiny
        // OutboxItem-only container against the same store file,
        // snapshot the rows, persist them to a sidecar JSON, and only
        // then delete.
        //
        // The store file basename matches the ModelConfiguration name —
        // ModelConfiguration("slabbist", …) → slabbist.store. SQLite WAL
        // mode means the persistent store is actually three files; all
        // three must be removed together or the rebuild can re-hydrate
        // the schema mismatch from the WAL.
        let storeURL = appSupport.appending(path: "\(configurationName).store")

        // Snapshot from the (maybe still readable via narrow schema)
        // store. If we already have orphan snapshots from a previous
        // crashed pass, prefer those — the store deletion was probably
        // attempted last time, so re-reading the store would return
        // nothing useful.
        let liveSnapshots = orphanSnapshots.isEmpty
            ? recoverOutboxItems(at: storeURL)
            : []
        let allSnapshots = orphanSnapshots + liveSnapshots
        if !liveSnapshots.isEmpty {
            AppLog.outbox.notice(
                "ModelContainer migration recovery: snapshotted \(liveSnapshots.count, privacy: .public) outbox row(s) from live store"
            )
        }

        // Persist BEFORE deletion so a crash here doesn't erase the
        // snapshots. Idempotent: on next launch the orphan-sidecar
        // path picks them up.
        if !allSnapshots.isEmpty {
            writeSidecar(allSnapshots, to: sidecarURL)
        }

        for suffix in [".store", ".store-shm", ".store-wal"] {
            let url = appSupport.appending(path: "\(configurationName)\(suffix)")
            try? FileManager.default.removeItem(at: url)
        }
        let rebuilt: ModelContainer
        do {
            rebuilt = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // We deliberately omit `error.localizedDescription` from
            // the public log — SwiftData migration errors can echo
            // column values from user data. The error type alone is
            // diagnostic.
            AppLog.outbox.fault(
                "ModelContainer rebuild after migration failure failed: \(String(describing: type(of: error)), privacy: .public)"
            )
            fatalError(
                "AppModelContainer: rebuild after migration failure also failed (\(type(of: error))). " +
                "The recovery sidecar at \(sidecarURL.lastPathComponent) holds the unsaved outbox rows for a follow-up attempt."
            )
        }

        // Re-insert the snapshotted outbox rows. We pick `AppLog.outbox`
        // logging over a UserDefaults-driven banner because the rare
        // migration-recovery path is already invisible (the user just
        // sees their pending writes draining), and surfacing a one-time
        // UI banner from a static initializer is awkward and adds UX
        // friction for a path the user can't act on. Console logs give
        // engineering visibility; tests assert the behavioral contract.
        if !allSnapshots.isEmpty {
            let outcome = restoreOutboxItems(allSnapshots, into: rebuilt)
            AppLog.outbox.notice(
                "ModelContainer migration recovery: restored \(outcome.restored, privacy: .public) of \(allSnapshots.count, privacy: .public) outbox row(s); \(outcome.unrestored.count, privacy: .public) failed"
            )
            if outcome.unrestored.isEmpty {
                // Clean success — drop the sidecar so the next launch
                // takes the fast path.
                try? FileManager.default.removeItem(at: sidecarURL)
            } else {
                // Partial failure — rewrite the sidecar with only the
                // rows that didn't make it, so the next launch retries
                // them. Preserves the bad-payload-poisons-the-batch
                // resilience (P1.5).
                writeSidecar(outcome.unrestored, to: sidecarURL)
            }
        } else if FileManager.default.fileExists(atPath: sidecarURL.path) {
            // No snapshots but a sidecar exists — corrupt JSON from a
            // prior pass, or all rows were already restored. Drop it.
            try? FileManager.default.removeItem(at: sidecarURL)
        }

        return rebuilt
    }()

    /// In-memory container for tests and previews.
    static func inMemory() -> ModelContainer {
        let schema = Schema([
            Store.self, StoreMember.self, Lot.self,
            Scan.self, Vendor.self, OutboxItem.self,
            GradedCardIdentity.self,
            GradedMarketSnapshot.self,
            StoreTransaction.self, TransactionLine.self
        ])
        let config = ModelConfiguration("slabbist-tests", schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Recovery helpers (testable)

    /// Pure-data snapshot of an `OutboxItem`. We can't move SwiftData
    /// model instances between containers, so we copy the columns into
    /// a plain value type and re-insert fresh `OutboxItem` rows into
    /// the rebuilt container.
    struct OutboxItemSnapshot: Sendable, Equatable, Codable {
        var id: UUID
        var kind: OutboxKind
        var payload: Data
        var status: OutboxItemStatus
        var attempts: Int
        var lastError: String?
        var createdAt: Date
        var nextAttemptAt: Date
    }

    /// Outcome of a restore pass. `restored` is the count that made it
    /// to disk; `unrestored` is the snapshots that couldn't (used to
    /// rewrite the sidecar JSON for the next attempt).
    struct RestoreOutcome: Equatable {
        var restored: Int
        var unrestored: [OutboxItemSnapshot]
    }

    /// Attempts to open a minimal `OutboxItem`-only `ModelContainer`
    /// against the store file at `storeURL` and return snapshots of all
    /// `OutboxItem` rows. Returns an empty array on any failure — the
    /// caller treats that as "nothing to restore" rather than fatal.
    ///
    /// Visible for testing. Never throws — defensive by design.
    ///
    /// Confirmed by `ModelContainerRecoveryTests.recoverFromFullSchemaStore`:
    /// the narrow schema opens cleanly against a store originally
    /// written with the full Slabbist schema. SwiftData tolerates extra
    /// tables on disk that the open-time schema doesn't reference.
    static func recoverOutboxItems(at storeURL: URL) -> [OutboxItemSnapshot] {
        do {
            let outboxSchema = Schema([OutboxItem.self])
            let recoveryConfig = ModelConfiguration(
                schema: outboxSchema,
                url: storeURL
            )
            let recoveryContainer = try ModelContainer(
                for: outboxSchema,
                configurations: [recoveryConfig]
            )
            let context = ModelContext(recoveryContainer)
            let descriptor = FetchDescriptor<OutboxItem>()
            let items = try context.fetch(descriptor)
            return items.map { item in
                OutboxItemSnapshot(
                    id: item.id,
                    kind: item.kind,
                    payload: item.payload,
                    status: item.status,
                    attempts: item.attempts,
                    lastError: item.lastError,
                    createdAt: item.createdAt,
                    nextAttemptAt: item.nextAttemptAt
                )
            }
        } catch {
            // PII-safe: skip the storeURL path (Application Support
            // location is user-identifying) and skip the error's
            // localized description (SwiftData migration errors echo
            // user-data column values). Type alone is diagnostic.
            AppLog.outbox.error(
                "ModelContainer outbox recovery: recovery container open failed: \(String(describing: type(of: error)), privacy: .public)"
            )
            return []
        }
    }

    /// Inserts snapshotted outbox rows into the given container's main
    /// context. Saves PER ROW so a single bad payload (e.g. SwiftData
    /// constraint violation on an encoded column) only loses that one
    /// row, not the whole batch. Failed rows come back in
    /// `RestoreOutcome.unrestored` so the caller can rewrite the
    /// sidecar JSON and try again on the next launch.
    ///
    /// Visible for testing.
    @discardableResult
    static func restoreOutboxItems(
        _ snapshots: [OutboxItemSnapshot],
        into container: ModelContainer
    ) -> RestoreOutcome {
        let context = ModelContext(container)
        var restored = 0
        var unrestored: [OutboxItemSnapshot] = []

        for snap in snapshots {
            let item = OutboxItem(
                id: snap.id,
                kind: snap.kind,
                payload: snap.payload,
                status: snap.status,
                attempts: snap.attempts,
                lastError: snap.lastError,
                createdAt: snap.createdAt,
                nextAttemptAt: snap.nextAttemptAt
            )
            context.insert(item)
            do {
                try context.save()
                restored += 1
            } catch {
                // Roll the failed insert out of the context so the next
                // row's save doesn't re-encounter it. Then bank the
                // snapshot for the sidecar rewrite.
                context.delete(item)
                unrestored.append(snap)
                AppLog.outbox.error(
                    "ModelContainer outbox recovery: per-row save failed for kind=\(snap.kind.rawValue, privacy: .public): \(String(describing: type(of: error)), privacy: .public)"
                )
            }
        }
        return RestoreOutcome(restored: restored, unrestored: unrestored)
    }

    // MARK: - Sidecar JSON (idempotent crash-safe staging)

    /// Reads and decodes the recovery sidecar at `url`. Returns `[]`
    /// for missing file, junk file, or decode failure — caller treats
    /// every error as "no orphan snapshots". Defensive by design.
    ///
    /// Visible for testing.
    static func readSidecar(at url: URL) -> [OutboxItemSnapshot] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode([OutboxItemSnapshot].self, from: data)
        } catch {
            AppLog.outbox.error(
                "ModelContainer outbox recovery: sidecar decode failed: \(String(describing: type(of: error)), privacy: .public)"
            )
            return []
        }
    }

    /// Writes snapshots to the sidecar at `url`. Best-effort: a write
    /// failure is logged but doesn't throw — the caller has nothing
    /// useful to do with the error inside the static initializer.
    ///
    /// Visible for testing.
    static func writeSidecar(_ snapshots: [OutboxItemSnapshot], to url: URL) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(snapshots)
            try data.write(to: url, options: [.atomic])
        } catch {
            AppLog.outbox.error(
                "ModelContainer outbox recovery: sidecar write failed: \(String(describing: type(of: error)), privacy: .public)"
            )
        }
    }
}
