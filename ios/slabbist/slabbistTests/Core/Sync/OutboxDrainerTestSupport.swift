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
    let fakeLots = FakeLotRepository()
    let fakeScans = FakeScanRepository()
    let fakeVendors = FakeVendorRepository()
    let fakeTransactions = FakeTransactionRepository()
    let status = OutboxStatus()
    let clock = TestClock()
    let drainer: OutboxDrainer

    /// Records every StatusUpdate the drainer publishes. The harness can
    /// await transitions against this buffer instead of `Task.sleep`.
    private let observed = StatusObserver()

    init() {
        // Build a fresh in-memory container per harness instance. We don't
        // use `AppModelContainer.inMemory()` because its named configuration
        // can collide across parallel test workers (Swift Testing fans
        // tests out across simulator clones), producing flaky cross-test
        // bleed. An unnamed in-memory config is fully scoped to this
        // instance.
        let schema = Schema([
            Store.self, StoreMember.self, Lot.self,
            Scan.self, Vendor.self, OutboxItem.self,
            GradedCardIdentity.self,
            GradedMarketSnapshot.self,
            StoreTransaction.self, TransactionLine.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try! ModelContainer(for: schema, configurations: [config])
        let repos = AppRepositories(
            stores: NullStoreRepo(),
            members: NullStoreMemberRepo(),
            lots: fakeLots,
            scans: fakeScans,
            vendors: fakeVendors,
            gradeEstimates: NullGradeEstimateRepo(),
            transactions: fakeTransactions
        )
        let statusBox = self.status
        let observer = self.observed
        self.drainer = OutboxDrainer(
            modelContainer: container,
            repositories: repos,
            clock: clock,
            statusSink: { update in
                Task {
                    await observer.record(update)
                    await MainActor.run {
                        statusBox.update(
                            pendingCount: update.pendingCount,
                            isDraining: update.isDraining
                        )
                        if let isPaused = update.isPaused {
                            statusBox.setPaused(isPaused, reason: update.lastError)
                        }
                    }
                }
            }
        )
    }

    /// Block until the drainer has published at least one update with
    /// `isDraining == false` after `kickAndWait()` returns, AND the
    /// MainActor status box reflects the matching pendingCount.
    /// Replaces `try? await Task.sleep(nanoseconds: 100_000_000)`.
    func waitForIdle() async {
        await observed.waitForIdle()
        // One MainActor hop to ensure the statusBox.update side-effect
        // has flushed (it's enqueued in the same Task that called
        // observed.record, so by the time observed.waitForIdle returns,
        // any pending MainActor.run is at most one hop away).
        await MainActor.run { _ = status.pendingCount }
    }

    func enqueueInsertScan(id: UUID, createdAt: Date? = nil) async throws {
        // Default `createdAt` to the test clock's current value so the
        // drainer's `nextAttemptAt <= now` predicate matches. Calling
        // `Date()` here would set `nextAttemptAt` far in the future
        // relative to the test clock and the item would never get
        // picked up.
        let stamp = createdAt ?? clock.current()
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
            created_at: ISO8601DateFormatter().string(from: stamp),
            updated_at: ISO8601DateFormatter().string(from: stamp)
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
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func enqueueInsertLot(id: UUID, createdAt: Date? = nil) async throws {
        let stamp = createdAt ?? clock.current()
        let dto = OutboxPayloads.InsertLot(
            id: id.uuidString,
            store_id: UUID().uuidString,
            created_by_user_id: UUID().uuidString,
            name: "Test Lot",
            notes: nil,
            status: "open",
            created_at: ISO8601DateFormatter().string(from: stamp),
            updated_at: ISO8601DateFormatter().string(from: stamp)
        )
        let payload = try JSONEncoder().encode(dto)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .insertLot,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func enqueueDeleteScan(id: UUID, createdAt: Date? = nil) async throws {
        let stamp = createdAt ?? clock.current()
        let dto = OutboxPayloads.DeleteScan(
            id: id.uuidString,
            deleted_at: ISO8601DateFormatter().string(from: stamp)
        )
        let payload = try JSONEncoder().encode(dto)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .deleteScan,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func enqueueDeleteLot(id: UUID, createdAt: Date? = nil) async throws {
        let stamp = createdAt ?? clock.current()
        let dto = OutboxPayloads.DeleteLot(
            id: id.uuidString,
            deleted_at: ISO8601DateFormatter().string(from: stamp)
        )
        let payload = try JSONEncoder().encode(dto)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .deleteLot,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func enqueueUpdateScan(id: UUID, createdAt: Date? = nil) async throws {
        let stamp = createdAt ?? clock.current()
        let dto = OutboxPayloads.UpdateScan(
            id: id.uuidString,
            graded_card_identity_id: nil,
            grade: nil,
            status: "identified",
            updated_at: ISO8601DateFormatter().string(from: stamp)
        )
        let payload = try JSONEncoder().encode(dto)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .updateScan,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func enqueueUpdateScanOffer(id: UUID, cents: Int64?, createdAt: Date? = nil) async throws {
        let stamp = createdAt ?? clock.current()
        let dto = OutboxPayloads.UpdateScanOffer(
            id: id.uuidString,
            vendor_ask_cents: cents,
            updated_at: ISO8601DateFormatter().string(from: stamp)
        )
        let payload = try JSONEncoder().encode(dto)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .updateScanOffer,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func enqueueUpdateLot(id: UUID, name: String?, createdAt: Date? = nil) async throws {
        let stamp = createdAt ?? clock.current()
        let dto = OutboxPayloads.UpdateLot(
            id: id.uuidString,
            name: name,
            notes: nil,
            status: nil,
            updated_at: ISO8601DateFormatter().string(from: stamp)
        )
        let payload = try JSONEncoder().encode(dto)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .updateLot,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func enqueueUpsertVendor(
        id: UUID,
        storeId: UUID = UUID(),
        displayName: String = "Acme Cards",
        archivedAt: Date? = nil,
        createdAt: Date? = nil
    ) async throws {
        let stamp = createdAt ?? clock.current()
        let iso = ISO8601DateFormatter()
        let dto = OutboxPayloads.UpsertVendor(
            id: id.uuidString,
            store_id: storeId.uuidString,
            display_name: displayName,
            contact_method: "phone",
            contact_value: "555-0100",
            notes: nil,
            archived_at: archivedAt.map { iso.string(from: $0) },
            created_at: iso.string(from: stamp),
            updated_at: iso.string(from: stamp)
        )
        let payload = try JSONEncoder().encode(dto)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .upsertVendor,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func enqueueArchiveVendor(
        id: UUID,
        archivedAt: Date? = nil,
        createdAt: Date? = nil
    ) async throws {
        let stamp = createdAt ?? clock.current()
        let archStamp = archivedAt ?? stamp
        let iso = ISO8601DateFormatter()
        let dto = OutboxPayloads.ArchiveVendor(
            id: id.uuidString,
            archived_at: iso.string(from: archStamp)
        )
        let payload = try JSONEncoder().encode(dto)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .archiveVendor,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func enqueueUpdateLotOffer(
        id: UUID,
        vendorId: UUID? = nil,
        vendorNameSnapshot: String? = nil,
        marginPctSnapshot: Double? = nil,
        lotOfferState: String? = nil,
        lotOfferStateUpdatedAt: Date? = nil,
        createdAt: Date? = nil
    ) async throws {
        let stamp = createdAt ?? clock.current()
        let iso = ISO8601DateFormatter()
        let dto = OutboxPayloads.UpdateLotOffer(
            id: id.uuidString,
            vendor_id: vendorId?.uuidString,
            vendor_name_snapshot: vendorNameSnapshot,
            margin_pct_snapshot: marginPctSnapshot,
            lot_offer_state: lotOfferState,
            lot_offer_state_updated_at: lotOfferStateUpdatedAt.map { iso.string(from: $0) },
            updated_at: iso.string(from: stamp)
        )
        let payload = try JSONEncoder().encode(dto)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .updateLotOffer,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func enqueueRecomputeLotOffer(lotId: UUID, createdAt: Date? = nil) async throws {
        let stamp = createdAt ?? clock.current()
        let dto = OutboxPayloads.RecomputeLotOffer(lot_id: lotId.uuidString)
        let payload = try JSONEncoder().encode(dto)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .recomputeLotOffer,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func enqueueUpdateScanBuyPrice(
        id: UUID,
        cents: Int64?,
        overridden: Bool,
        createdAt: Date? = nil
    ) async throws {
        let stamp = createdAt ?? clock.current()
        let dto = OutboxPayloads.UpdateScanBuyPrice(
            id: id.uuidString,
            buy_price_cents: cents,
            buy_price_overridden: overridden,
            updated_at: ISO8601DateFormatter().string(from: stamp)
        )
        let payload = try JSONEncoder().encode(dto)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .updateScanBuyPrice,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func enqueueCorruptItem(kind: OutboxKind, createdAt: Date? = nil) async throws {
        let stamp = createdAt ?? clock.current()
        let payload = Data("not json".utf8)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: kind,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }

    func outboxCount() async -> Int {
        await drainer._testOutboxCount()
    }

    func firstOutboxItem() async throws -> OutboxDrainer.OutboxItemSnapshot {
        try await drainer._testFirstOutboxItem()
    }
}

// MARK: - Repository fakes

/// Fake `ScanRepository`. Recorders are wrapped in an actor to keep
/// concurrent writes from the drainer + test main actor safe.
///
/// `insertedIds`, `deletedIds`, and `patchCalls` are mirrored into
/// lock-protected arrays so tests on the MainActor can read them
/// synchronously after `waitForIdle()` — once the drain loop has
/// finished there are no more concurrent writers.
final class FakeScanRepository: ScanRepository, @unchecked Sendable {
    private let recorder = Recorder()
    var nextError: Error?

    actor Recorder {
        var insertedIds: [UUID] = []
        var deletedIds: [UUID] = []
        var patchCalls: [(id: UUID, fields: [String: AnyJSON])] = []
        func appendInserted(_ id: UUID) { insertedIds.append(id) }
        func appendDeleted(_ id: UUID) { deletedIds.append(id) }
        func appendPatch(id: UUID, fields: [String: AnyJSON]) { patchCalls.append((id: id, fields: fields)) }
        func snapshotInserted() -> [UUID] { insertedIds }
    }

    /// Lock-protected mirrors. Safe to read from MainActor after
    /// `Harness.waitForIdle()` has returned (no concurrent writers at that point).
    private let _lock = NSLock()
    private var _insertedIds: [UUID] = []
    private var _deletedIds: [UUID] = []
    private var _patchCalls: [(id: UUID, fields: [String: AnyJSON])] = []

    var insertedIds: [UUID] {
        _lock.lock(); defer { _lock.unlock() }
        return _insertedIds
    }

    var deletedIds: [UUID] {
        _lock.lock(); defer { _lock.unlock() }
        return _deletedIds
    }

    var patchCalls: [(id: UUID, fields: [String: AnyJSON])] {
        _lock.lock(); defer { _lock.unlock() }
        return _patchCalls
    }

    func snapshotInsertedIds() async -> [UUID] { await recorder.snapshotInserted() }

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
        await recorder.appendInserted(scan.id)
        _lock.lock(); defer { _lock.unlock() }
        _insertedIds.append(scan.id)
    }

    func insertAndReturn(_ scan: ScanDTO) async throws -> ScanDTO {
        try await insert(scan)
        return scan
    }

    func upsert(_ scan: ScanDTO) async throws {}
    func upsertMany(_ scans: [ScanDTO]) async throws {}

    func delete(id: UUID) async throws {
        if let e = nextError { nextError = nil; throw e }
        await recorder.appendDeleted(id)
        _lock.lock(); defer { _lock.unlock() }
        _deletedIds.append(id)
    }

    func patch(id: UUID, fields: [String: AnyJSON]) async throws {
        if let e = nextError { nextError = nil; throw e }
        await recorder.appendPatch(id: id, fields: fields)
        _lock.lock(); defer { _lock.unlock() }
        _patchCalls.append((id: id, fields: fields))
    }
}

/// Fake `LotRepository`. Same shape as `FakeScanRepository`.
final class FakeLotRepository: LotRepository, @unchecked Sendable {
    private let recorder = Recorder()
    var nextError: Error?
    /// Optional canned error to throw on the next `recomputeOffer` call.
    /// Separate from `nextError` so dispatch tests can stage a 409 (terminal
    /// state) without disturbing the patch-path recording.
    var nextRecomputeError: Error?
    /// Canned response returned from `recomputeOffer`. Tests can override
    /// to assert downstream behaviour against specific server payloads.
    var recomputeResponse: LotOfferRecomputeResponse = LotOfferRecomputeResponse(
        lot_id: UUID().uuidString,
        offered_total_cents: 0,
        lot_offer_state: "pending"
    )

    actor Recorder {
        var insertedIds: [UUID] = []
        var deletedIds: [UUID] = []
        var patchCalls: [(id: UUID, fields: [String: AnyJSON])] = []
        var recomputeCalls: [UUID] = []
        func appendInserted(_ id: UUID) { insertedIds.append(id) }
        func appendDeleted(_ id: UUID) { deletedIds.append(id) }
        func appendPatch(id: UUID, fields: [String: AnyJSON]) { patchCalls.append((id: id, fields: fields)) }
        func appendRecompute(_ id: UUID) { recomputeCalls.append(id) }
        func snapshotInserted() -> [UUID] { insertedIds }
    }

    private let _lock = NSLock()
    private var _insertedIds: [UUID] = []
    private var _deletedIds: [UUID] = []
    private var _patchCalls: [(id: UUID, fields: [String: AnyJSON])] = []
    private var _recomputeCalls: [UUID] = []

    var insertedIds: [UUID] {
        _lock.lock(); defer { _lock.unlock() }
        return _insertedIds
    }

    var deletedIds: [UUID] {
        _lock.lock(); defer { _lock.unlock() }
        return _deletedIds
    }

    var patchCalls: [(id: UUID, fields: [String: AnyJSON])] {
        _lock.lock(); defer { _lock.unlock() }
        return _patchCalls
    }

    var recomputeCalls: [UUID] {
        _lock.lock(); defer { _lock.unlock() }
        return _recomputeCalls
    }

    func snapshotInsertedIds() async -> [UUID] { await recorder.snapshotInserted() }

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
        await recorder.appendInserted(lot.id)
        _lock.lock(); defer { _lock.unlock() }
        _insertedIds.append(lot.id)
    }

    func insertAndReturn(_ lot: LotDTO) async throws -> LotDTO {
        try await insert(lot)
        return lot
    }

    func upsert(_ lot: LotDTO) async throws {}
    func upsertMany(_ lots: [LotDTO]) async throws {}

    func patch(id: UUID, fields: [String: AnyJSON]) async throws {
        if let e = nextError { nextError = nil; throw e }
        await recorder.appendPatch(id: id, fields: fields)
        _lock.lock(); defer { _lock.unlock() }
        _patchCalls.append((id: id, fields: fields))
    }

    func delete(id: UUID) async throws {
        if let e = nextError { nextError = nil; throw e }
        await recorder.appendDeleted(id)
        _lock.lock(); defer { _lock.unlock() }
        _deletedIds.append(id)
    }

    func recomputeOffer(lotId: UUID) async throws -> LotOfferRecomputeResponse {
        if let e = nextRecomputeError { nextRecomputeError = nil; throw e }
        await recorder.appendRecompute(lotId)
        _lock.lock(); defer { _lock.unlock() }
        _recomputeCalls.append(lotId)
        return recomputeResponse
    }
}

/// Fake `VendorRepository`. Same shape as `FakeLotRepository` /
/// `FakeScanRepository` so dispatch tests can assert that the drainer
/// invoked the right method with the expected DTO / patch fields.
final class FakeVendorRepository: VendorRepository, @unchecked Sendable {
    private let recorder = Recorder()
    var nextError: Error?

    actor Recorder {
        var upsertedVendors: [VendorDTO] = []
        var patchCalls: [(id: UUID, fields: [String: AnyJSON])] = []
        func appendUpsert(_ vendor: VendorDTO) { upsertedVendors.append(vendor) }
        func appendPatch(id: UUID, fields: [String: AnyJSON]) { patchCalls.append((id: id, fields: fields)) }
    }

    private let _lock = NSLock()
    private var _upsertedVendors: [VendorDTO] = []
    private var _patchCalls: [(id: UUID, fields: [String: AnyJSON])] = []

    var upsertedVendors: [VendorDTO] {
        _lock.lock(); defer { _lock.unlock() }
        return _upsertedVendors
    }

    var patchCalls: [(id: UUID, fields: [String: AnyJSON])] {
        _lock.lock(); defer { _lock.unlock() }
        return _patchCalls
    }

    func find(id: UUID) async throws -> VendorDTO? { nil }

    func listActive(storeId: UUID, page: Page) async throws -> [VendorDTO] { [] }

    func upsert(_ vendor: VendorDTO) async throws {
        if let e = nextError { nextError = nil; throw e }
        await recorder.appendUpsert(vendor)
        _lock.lock(); defer { _lock.unlock() }
        _upsertedVendors.append(vendor)
    }

    func patch(id: UUID, fields: [String: AnyJSON]) async throws {
        if let e = nextError { nextError = nil; throw e }
        await recorder.appendPatch(id: id, fields: fields)
        _lock.lock(); defer { _lock.unlock() }
        _patchCalls.append((id: id, fields: fields))
    }
}

/// Fake `TransactionRepository`. Records commit + void invocations and
/// returns canned responses so dispatch tests can verify both the Edge
/// Function call and the resulting hydration.
final class FakeTransactionRepository: TransactionRepository, @unchecked Sendable {
    private let recorder = Recorder()
    var nextCommitError: Error?
    var nextVoidError: Error?

    /// Canned response returned from `commit`. Tests can override before
    /// dispatch to validate hydrator behaviour against a specific shape.
    /// Defaults are placeholder UUIDs / timestamps so the row inserts
    /// without conflicting with any test-owned IDs.
    var commitResponse: TransactionCommitResponse = TransactionCommitResponse(
        transaction: TransactionCommitResponse.TransactionRow(
            id: UUID().uuidString,
            store_id: UUID().uuidString,
            lot_id: UUID().uuidString,
            vendor_id: nil,
            vendor_name_snapshot: "test vendor",
            total_buy_cents: 0,
            payment_method: "cash",
            payment_reference: nil,
            paid_at: ISO8601DateFormatter().string(from: Date()),
            paid_by_user_id: UUID().uuidString,
            voided_at: nil,
            voided_by_user_id: nil,
            void_reason: nil,
            void_of_transaction_id: nil
        ),
        lines: [],
        deduped: nil
    )

    var voidResponse: TransactionVoidResponse = TransactionVoidResponse(
        void_transaction: TransactionCommitResponse.TransactionRow(
            id: UUID().uuidString,
            store_id: UUID().uuidString,
            lot_id: UUID().uuidString,
            vendor_id: nil,
            vendor_name_snapshot: "test vendor",
            total_buy_cents: 0,
            payment_method: "cash",
            payment_reference: nil,
            paid_at: ISO8601DateFormatter().string(from: Date()),
            paid_by_user_id: UUID().uuidString,
            voided_at: ISO8601DateFormatter().string(from: Date()),
            voided_by_user_id: UUID().uuidString,
            void_reason: "test",
            void_of_transaction_id: UUID().uuidString
        ),
        original_id: UUID().uuidString
    )

    actor Recorder {
        var commitCalls: [TransactionCommitPayload] = []
        var voidCalls: [(transactionId: UUID, reason: String)] = []
        func appendCommit(_ payload: TransactionCommitPayload) { commitCalls.append(payload) }
        func appendVoid(_ transactionId: UUID, _ reason: String) {
            voidCalls.append((transactionId: transactionId, reason: reason))
        }
    }

    private let _lock = NSLock()
    private var _commitCalls: [TransactionCommitPayload] = []
    private var _voidCalls: [(transactionId: UUID, reason: String)] = []

    var commitCalls: [TransactionCommitPayload] {
        _lock.lock(); defer { _lock.unlock() }
        return _commitCalls
    }

    var voidCalls: [(transactionId: UUID, reason: String)] {
        _lock.lock(); defer { _lock.unlock() }
        return _voidCalls
    }

    func commit(payload: TransactionCommitPayload) async throws -> TransactionCommitResponse {
        if let e = nextCommitError { nextCommitError = nil; throw e }
        await recorder.appendCommit(payload)
        _lock.lock(); defer { _lock.unlock() }
        _commitCalls.append(payload)
        return commitResponse
    }

    func void(transactionId: UUID, reason: String) async throws -> TransactionVoidResponse {
        if let e = nextVoidError { nextVoidError = nil; throw e }
        await recorder.appendVoid(transactionId, reason)
        _lock.lock(); defer { _lock.unlock() }
        _voidCalls.append((transactionId: transactionId, reason: reason))
        return voidResponse
    }
}

// MARK: - Null repositories (unused dependencies)

struct NullStoreRepo: StoreRepository {
    func listForCurrentUser(page: Page) async throws -> [StoreDTO] { [] }
    func find(id: UUID) async throws -> StoreDTO? { nil }
    func listOwnedBy(userId: UUID, page: Page) async throws -> [StoreDTO] { [] }
    func upsert(_ store: StoreDTO) async throws {}
    func upsertAndReturn(_ store: StoreDTO) async throws -> StoreDTO { store }
    func patch(id: UUID, fields: [String: AnyJSON]) async throws {}
    func createMyStore(name: String) async throws -> UUID { UUID() }
}

struct NullStoreMemberRepo: StoreMemberRepository {
    func listMembers(storeId: UUID, page: Page) async throws -> [StoreMemberDTO] { [] }
    func listMemberships(userId: UUID, page: Page) async throws -> [StoreMemberDTO] { [] }
    func membership(storeId: UUID, userId: UUID) async throws -> StoreMemberDTO? { nil }
    func upsert(_ member: StoreMemberDTO) async throws {}
    func remove(storeId: UUID, userId: UUID) async throws {}
}

struct NullVendorRepo: VendorRepository {
    func find(id: UUID) async throws -> VendorDTO? { nil }
    func listActive(storeId: UUID, page: Page) async throws -> [VendorDTO] { [] }
    func upsert(_ vendor: VendorDTO) async throws {}
    func patch(id: UUID, fields: [String: AnyJSON]) async throws {}
}

struct NullTransactionRepo: TransactionRepository {
    func commit(payload: TransactionCommitPayload) async throws -> TransactionCommitResponse {
        fatalError("unused")
    }
    func void(transactionId: UUID, reason: String) async throws -> TransactionVoidResponse {
        fatalError("unused")
    }
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

// MARK: - StatusObserver

/// Records every StatusUpdate the drainer emits and lets a test await
/// the next `isDraining == false` transition. Replaces fixed Task.sleep
/// waits in the harness — no flake under load.
actor StatusObserver {
    private var buffer: [OutboxDrainer.StatusUpdate] = []
    private var idleContinuations: [CheckedContinuation<Void, Never>] = []

    func record(_ update: OutboxDrainer.StatusUpdate) {
        buffer.append(update)
        if !update.isDraining {
            for c in idleContinuations { c.resume() }
            idleContinuations.removeAll()
        }
    }

    func waitForIdle() async {
        // If we've already seen a non-draining update, return immediately.
        if buffer.contains(where: { !$0.isDraining }) { return }
        await withCheckedContinuation { continuation in
            idleContinuations.append(continuation)
        }
    }

    func updates() -> [OutboxDrainer.StatusUpdate] { buffer }
}
