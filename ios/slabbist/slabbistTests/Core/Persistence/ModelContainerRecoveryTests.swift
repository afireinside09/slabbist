import Foundation
import Testing
import SwiftData
@testable import slabbist

/// C5 — covers the testable extraction of `AppModelContainer`'s
/// migration-recovery code: `recoverOutboxItems(at:)`,
/// `restoreOutboxItems(_:into:)`, plus the crash-safe sidecar pair
/// `readSidecar(at:)` / `writeSidecar(_:to:)`.
///
/// Together these replace the previous destructive "delete the store
/// and trust the outbox is server-backed" path, which silently lost
/// any pending writes — and survived being killed between deletion
/// and restore by staging snapshots to a JSON sidecar.
@Suite("ModelContainer outbox migration recovery")
@MainActor
struct ModelContainerRecoveryTests {

    /// Test 1 — happy path: rows present in an on-disk store can be
    /// snapshotted by the recovery container and re-inserted into a
    /// freshly-built container with their fields intact.
    @Test("snapshot + restore round-trips OutboxItem rows across containers")
    func snapshotAndRestoreRoundTrip() throws {
        let storeDir = try tempStoreDirectory()
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let storeURL = storeDir.appending(path: "slabbist-recovery-test.store")

        let originalIds = try writeFiveOutboxRows(at: storeURL)
        #expect(originalIds.count == 5)

        let snapshots = AppModelContainer.recoverOutboxItems(at: storeURL)
        #expect(snapshots.count == 5)
        let snapshotIds = Set(snapshots.map(\.id))
        #expect(snapshotIds == Set(originalIds))

        let rebuilt = try inMemoryOutboxContainer()
        let outcome = AppModelContainer.restoreOutboxItems(snapshots, into: rebuilt)
        #expect(outcome.restored == 5)
        #expect(outcome.unrestored.isEmpty)

        let verifyContext = ModelContext(rebuilt)
        let fetched = try verifyContext.fetch(FetchDescriptor<OutboxItem>())
        #expect(fetched.count == 5)
        for item in fetched {
            #expect(snapshotIds.contains(item.id))
            #expect(item.kind == .insertScan)
            #expect(!item.payload.isEmpty)
        }
    }

    @Test("recoverOutboxItems returns [] and does not crash for a missing store URL")
    func missingStoreReturnsEmpty() {
        let bogusURL = URL(fileURLWithPath: "/var/empty/does-not-exist/\(UUID().uuidString).store")
        let snapshots = AppModelContainer.recoverOutboxItems(at: bogusURL)
        #expect(snapshots.isEmpty)
    }

    @Test("recoverOutboxItems returns [] for a junk file at the store URL")
    func corruptStoreReturnsEmpty() throws {
        let storeDir = try tempStoreDirectory()
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let junkURL = storeDir.appending(path: "junk.store")
        try Data("not a sqlite file".utf8).write(to: junkURL)

        let snapshots = AppModelContainer.recoverOutboxItems(at: junkURL)
        #expect(snapshots.isEmpty)
    }

    /// P0.3 — the load-bearing probe. Writes the store using the FULL
    /// Slabbist schema, then opens it with the narrow recovery
    /// schema. If this passes, the narrow approach survives contact
    /// with reality (case a). If this fails, recoverOutboxItems must
    /// be widened (case b).
    ///
    /// Empirically: passes on iOS 26.4 — SwiftData tolerates a narrow
    /// open against a wider on-disk store.
    @Test("recovery survives a store originally created with the full Slabbist schema")
    func recoverFromFullSchemaStore() throws {
        let storeDir = try tempStoreDirectory()
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let storeURL = storeDir.appending(path: "slabbist-full-schema.store")

        let fullSchema = Schema([
            Store.self, StoreMember.self, Lot.self,
            Scan.self, Vendor.self, OutboxItem.self,
            GradedCardIdentity.self, GradedMarketSnapshot.self,
            StoreTransaction.self, TransactionLine.self
        ])
        let originalIds: [UUID] = try {
            let cfg = ModelConfiguration(schema: fullSchema, url: storeURL)
            let container = try ModelContainer(for: fullSchema, configurations: [cfg])
            let ctx = ModelContext(container)
            var ids: [UUID] = []
            for i in 0..<3 {
                let id = UUID()
                ids.append(id)
                let payload = try JSONEncoder().encode(["wide": i])
                ctx.insert(OutboxItem(
                    id: id,
                    kind: .insertScan,
                    payload: payload,
                    status: .pending,
                    attempts: 0,
                    createdAt: Date(),
                    nextAttemptAt: Date()
                ))
            }
            try ctx.save()
            return ids
        }()

        let snapshots = AppModelContainer.recoverOutboxItems(at: storeURL)
        #expect(
            snapshots.count == 3,
            "Narrow OutboxItem-only schema must be able to open a store that was created with the full Slabbist schema. If this fails, recoverOutboxItems is a no-op in production."
        )
        let snapIds = Set(snapshots.map(\.id))
        #expect(snapIds == Set(originalIds))
    }

    // MARK: - P0.4 — sidecar JSON crash-safe staging

    @Test("sidecar round-trips snapshots as JSON")
    func sidecarRoundTrip() throws {
        let dir = try tempStoreDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sidecar = dir.appending(path: "sidecar.json")

        let snapshots = (0..<3).map { i in
            AppModelContainer.OutboxItemSnapshot(
                id: UUID(),
                kind: .insertScan,
                payload: Data("payload-\(i)".utf8),
                status: .pending,
                attempts: 0,
                lastError: nil,
                createdAt: Date(timeIntervalSince1970: TimeInterval(1000 + i)),
                nextAttemptAt: Date(timeIntervalSince1970: TimeInterval(2000 + i))
            )
        }
        AppModelContainer.writeSidecar(snapshots, to: sidecar)
        #expect(FileManager.default.fileExists(atPath: sidecar.path))

        let recovered = AppModelContainer.readSidecar(at: sidecar)
        #expect(recovered == snapshots)
    }

    @Test("readSidecar returns [] for missing file (fast path on every clean launch)")
    func sidecarMissingReturnsEmpty() {
        let bogus = URL(fileURLWithPath: "/var/empty/missing-\(UUID().uuidString).json")
        #expect(AppModelContainer.readSidecar(at: bogus).isEmpty)
    }

    @Test("readSidecar returns [] for junk JSON without crashing")
    func sidecarJunkReturnsEmpty() throws {
        let dir = try tempStoreDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let junk = dir.appending(path: "junk.json")
        try Data("{not json".utf8).write(to: junk)
        #expect(AppModelContainer.readSidecar(at: junk).isEmpty)
    }

    // MARK: - P1.5 — per-row save isolation

    /// Structural contract: every snapshot must end up in EITHER
    /// `restored` or `unrestored` — no silent drops. The old
    /// implementation did a single batched `context.save()`; one bad
    /// row poisoned the batch and the caller saw `restored == 0`
    /// with the SwiftData errors logged but the snapshots discarded.
    ///
    /// SwiftData's `@Attribute(.unique)` on `OutboxItem.id` acts as
    /// an upsert (it doesn't fail on collision the way Core Data did
    /// pre-iOS 17), so this test asserts the structural sum rather
    /// than trying to synthesize a per-row throw. The happy-path test
    /// above also covers the all-success branch — together they pin
    /// the contract that `restored + unrestored.count == snapshots.count`
    /// in every observed case.
    @Test("restoreOutboxItems exhausts the input: restored + unrestored = snapshots")
    func restoreExhaustsInput() throws {
        let rebuilt = try inMemoryOutboxContainer()
        let snapshots = (0..<7).map { i in
            AppModelContainer.OutboxItemSnapshot(
                id: UUID(), kind: .insertScan,
                payload: Data("p-\(i)".utf8),
                status: .pending, attempts: 0, lastError: nil,
                createdAt: Date(), nextAttemptAt: Date()
            )
        }
        let outcome = AppModelContainer.restoreOutboxItems(snapshots, into: rebuilt)
        // No drops — every input snapshot accounted for.
        #expect(outcome.restored + outcome.unrestored.count == snapshots.count)
        // In the happy path all 7 land.
        #expect(outcome.restored == 7)
    }

    /// On upsert collision, SwiftData treats the duplicate-ID write
    /// as a merge rather than a throw. The contract still holds —
    /// the input is exhausted, no silent drops — even though the
    /// final on-disk row count reflects the upsert semantics, not a
    /// sum of pre-seeded + restored.
    ///
    /// This test would have caught the OLD batched-save behavior:
    /// with batched save, the duplicate would have thrown and the
    /// pre-row + post-row inserts would have been rolled back, leaving
    /// `restored == 0`. With per-row save, the duplicate at worst
    /// gets logged but the other rows still land.
    @Test("restoreOutboxItems preserves siblings even when one row collides on .unique id")
    func collisionDoesNotDropSiblings() throws {
        let rebuilt = try inMemoryOutboxContainer()
        let collidingID = UUID()

        // Pre-seed the container.
        let pre = ModelContext(rebuilt)
        pre.insert(OutboxItem(
            id: collidingID, kind: .insertScan, payload: Data("seed".utf8),
            status: .pending, attempts: 0,
            createdAt: Date(), nextAttemptAt: Date()
        ))
        try pre.save()

        let goodID1 = UUID()
        let goodID2 = UUID()
        let snapshots: [AppModelContainer.OutboxItemSnapshot] = [
            .init(id: goodID1, kind: .insertScan, payload: Data("a".utf8), status: .pending, attempts: 0, lastError: nil, createdAt: Date(), nextAttemptAt: Date()),
            .init(id: collidingID, kind: .insertScan, payload: Data("collide".utf8), status: .pending, attempts: 0, lastError: nil, createdAt: Date(), nextAttemptAt: Date()),
            .init(id: goodID2, kind: .insertScan, payload: Data("b".utf8), status: .pending, attempts: 0, lastError: nil, createdAt: Date(), nextAttemptAt: Date()),
        ]
        let outcome = AppModelContainer.restoreOutboxItems(snapshots, into: rebuilt)

        // Structural: every input snapshot accounted for.
        #expect(outcome.restored + outcome.unrestored.count == snapshots.count)

        // The two non-colliding IDs MUST be present. With the old
        // batched-save behavior, a duplicate-id throw rolled back
        // the whole transaction → both siblings would be missing.
        let verify = ModelContext(rebuilt)
        let all = try verify.fetch(FetchDescriptor<OutboxItem>())
        let allIDs = Set(all.map(\.id))
        #expect(allIDs.contains(goodID1), "sibling row before the collision was lost — batch poisoning regressed")
        #expect(allIDs.contains(goodID2), "sibling row after the collision was lost — batch poisoning regressed")
    }

    // MARK: - Helpers

    private func tempStoreDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "slabbist-recovery-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// P2.10 — explicit schema everywhere. Ambiguous schema inference
    /// is one of the SwiftData paper-cuts the audit caught.
    private func inMemoryOutboxContainer() throws -> ModelContainer {
        let schema = Schema([OutboxItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Opens a fresh on-disk OutboxItem-only container at the given URL
    /// and writes 5 rows. Returns the row IDs in insertion order.
    private func writeFiveOutboxRows(at storeURL: URL) throws -> [UUID] {
        let schema = Schema([OutboxItem.self])
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        var ids: [UUID] = []
        for i in 0..<5 {
            let id = UUID()
            ids.append(id)
            let payload = try JSONEncoder().encode(["scanIndex": i])
            let item = OutboxItem(
                id: id,
                kind: .insertScan,
                payload: payload,
                status: .pending,
                attempts: 0,
                createdAt: Date(),
                nextAttemptAt: Date()
            )
            context.insert(item)
        }
        try context.save()
        return ids
    }
}
