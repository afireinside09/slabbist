import Foundation
import SwiftData
import Supabase
@testable import slabbist

// MARK: - Harness

/// Test scaffolding shared across all `OutboxDrainer` sub-phase tests.
/// Owns: in-memory ModelContainer, fakes, status surface, deterministic
/// clock, and the drainer-under-test wired together.
@MainActor
final class Harness {
    let container: ModelContainer
    let context: ModelContext
    let fakeLots = FakeLotRepository()
    let fakeScans = FakeScanRepository()
    let status = OutboxStatus()
    let clock = TestClock()
    let drainer: OutboxDrainer

    init() {
        // Build a fresh in-memory container per harness instance. We don't
        // use `AppModelContainer.inMemory()` because its named configuration
        // can collide across parallel test workers (Swift Testing fans
        // tests out across simulator clones), producing flaky cross-test
        // bleed. An unnamed in-memory config is fully scoped to this
        // instance.
        let schema = Schema([
            Store.self, StoreMember.self, Lot.self,
            Scan.self, OutboxItem.self,
            GradedCardIdentity.self,
            GradedMarketSnapshot.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try! ModelContainer(for: schema, configurations: [config])
        self.context = ModelContext(container)
        let repos = AppRepositories(
            stores: NullStoreRepo(),
            members: NullStoreMemberRepo(),
            lots: fakeLots,
            scans: fakeScans,
            gradeEstimates: NullGradeEstimateRepo()
        )
        let statusBox = self.status
        self.drainer = OutboxDrainer(
            modelContainer: container,
            repositories: repos,
            clock: clock,
            statusSink: { update in
                Task { @MainActor in
                    statusBox.update(
                        pendingCount: update.pendingCount,
                        isDraining: update.isDraining
                    )
                    if let isPaused = update.isPaused {
                        statusBox.setPaused(isPaused, reason: nil)
                    }
                }
            }
        )
    }

    func enqueueInsertScan(id: UUID, createdAt: Date? = nil) async throws {
        // Default `createdAt` to the test clock's current value so the
        // drainer's `nextAttemptAt <= now` predicate matches. Calling
        // `Date()` here would set `nextAttemptAt` far in the future
        // relative to the test clock and the item would never get
        // picked up.
        let createdAt = createdAt ?? clock.current()
        let dto = OutboxPayloads.InsertScan(
            id: id.uuidString,
            store_id: UUID().uuidString,
            lot_id: UUID().uuidString,
            user_id: UUID().uuidString,
            grader: "PSA",
            cert_number: "12345",
            status: "pending_validation",
            ocr_raw_text: nil,
            ocr_confidence: nil,
            created_at: ISO8601DateFormatter().string(from: createdAt),
            updated_at: ISO8601DateFormatter().string(from: createdAt)
        )
        let payload = try JSONEncoder().encode(dto)
        // Insert through the drainer's own context to avoid cross-context
        // staleness issues under parallel test workers. The `@Model`
        // instance is constructed inside the actor since `OutboxItem`
        // isn't Sendable.
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .insertScan,
            payload: payload,
            createdAt: createdAt,
            nextAttemptAt: createdAt
        )
    }

    func outboxCount() async -> Int {
        await drainer._testOutboxCount()
    }
}

// MARK: - Repository fakes

/// Fake `ScanRepository`. Recorders are wrapped in an actor to keep
/// concurrent writes from the drainer + test main actor safe.
final class FakeScanRepository: ScanRepository, @unchecked Sendable {
    private let recorder = Recorder()
    var nextError: Error?

    actor Recorder {
        var insertedIds: [UUID] = []
        func append(_ id: UUID) { insertedIds.append(id) }
        func snapshot() -> [UUID] { insertedIds }
    }

    func snapshotInsertedIds() async -> [UUID] { await recorder.snapshot() }

    func listItems(
        lotId: UUID,
        page: Page,
        includeTotalCount: Bool
    ) async throws -> PagedResult<ScanListItemDTO> { fatalError("unused") }

    func listItems(
        storeId: UUID,
        status: ScanStatus,
        page: Page,
        includeTotalCount: Bool
    ) async throws -> PagedResult<ScanListItemDTO> { fatalError("unused") }

    func countPending(storeId: UUID) async throws -> Int { 0 }

    func find(id: UUID) async throws -> ScanDTO? { nil }

    func insert(_ scan: ScanDTO) async throws {
        if let e = nextError { nextError = nil; throw e }
        await recorder.append(scan.id)
    }

    func insertAndReturn(_ scan: ScanDTO) async throws -> ScanDTO {
        try await insert(scan)
        return scan
    }

    func upsert(_ scan: ScanDTO) async throws {}
    func upsertMany(_ scans: [ScanDTO]) async throws {}
    func delete(id: UUID) async throws {}
    func patch(id: UUID, fields: [String: AnyJSON]) async throws {}
}

/// Fake `LotRepository`. Same shape as `FakeScanRepository`.
final class FakeLotRepository: LotRepository, @unchecked Sendable {
    private let recorder = Recorder()
    var nextError: Error?

    actor Recorder {
        var insertedIds: [UUID] = []
        func append(_ id: UUID) { insertedIds.append(id) }
        func snapshot() -> [UUID] { insertedIds }
    }

    func snapshotInsertedIds() async -> [UUID] { await recorder.snapshot() }

    func listItems(
        storeId: UUID,
        status: LotStatus?,
        page: Page,
        includeTotalCount: Bool
    ) async throws -> PagedResult<LotListItemDTO> { fatalError("unused") }

    func listItemsAfter(
        storeId: UUID,
        createdAtBefore cursor: Date,
        limit: Int
    ) async throws -> [LotListItemDTO] { [] }

    func countOpen(storeId: UUID) async throws -> Int { 0 }

    func find(id: UUID) async throws -> LotDTO? { nil }

    func insert(_ lot: LotDTO) async throws {
        if let e = nextError { nextError = nil; throw e }
        await recorder.append(lot.id)
    }

    func insertAndReturn(_ lot: LotDTO) async throws -> LotDTO {
        try await insert(lot)
        return lot
    }

    func upsert(_ lot: LotDTO) async throws {}
    func upsertMany(_ lots: [LotDTO]) async throws {}
    func patch(id: UUID, fields: [String: AnyJSON]) async throws {}
    func delete(id: UUID) async throws {}
}

// MARK: - Null repositories (unused dependencies)

struct NullStoreRepo: StoreRepository {
    func listForCurrentUser(page: Page) async throws -> [StoreDTO] { [] }
    func find(id: UUID) async throws -> StoreDTO? { nil }
    func listOwnedBy(userId: UUID, page: Page) async throws -> [StoreDTO] { [] }
    func upsert(_ store: StoreDTO) async throws {}
    func upsertAndReturn(_ store: StoreDTO) async throws -> StoreDTO { store }
}

struct NullStoreMemberRepo: StoreMemberRepository {
    func listMembers(storeId: UUID, page: Page) async throws -> [StoreMemberDTO] { [] }
    func listMemberships(userId: UUID, page: Page) async throws -> [StoreMemberDTO] { [] }
    func membership(storeId: UUID, userId: UUID) async throws -> StoreMemberDTO? { nil }
    func upsert(_ member: StoreMemberDTO) async throws {}
    func remove(storeId: UUID, userId: UUID) async throws {}
}

struct NullGradeEstimateRepo: GradeEstimateRepository {
    func listForCurrentUser(
        page: Page,
        includeTotalCount: Bool
    ) async throws -> PagedResult<GradeEstimateDTO> { fatalError("unused") }

    func find(id: UUID) async throws -> GradeEstimateDTO? { nil }
    func setStarred(id: UUID, starred: Bool) async throws {}
    func delete(id: UUID) async throws {}

    func requestEstimate(
        frontPath: String,
        backPath: String,
        centeringFront: CenteringRatios,
        centeringBack: CenteringRatios,
        includeOtherGraders: Bool
    ) async throws -> GradeEstimateDTO { fatalError("unused") }
}

// MARK: - Deterministic clock

final class TestClock: OutboxClock, @unchecked Sendable {
    private let lock = NSLock()
    private var now: Date = Date(timeIntervalSince1970: 1_700_000_000)

    func current() -> Date {
        lock.lock(); defer { lock.unlock() }
        return now
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        now = now.addingTimeInterval(seconds)
    }
}
