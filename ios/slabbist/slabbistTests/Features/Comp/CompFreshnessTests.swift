import Testing
import Foundation
import SwiftData
@testable import slabbist

/// C2 — `CompFetchService` must not lie about freshness and must surface
/// a recovery affordance when a `.fetching` scan is left stranded.
///
/// Pre-C2 behavior these tests guard against:
///   * `fetch` stamped `scan.compFetchedAt = Date()` before the network
///     call resolved. The "Last refreshed just now" caption appeared in
///     the UI while the spinner was still up — a North Star violation.
///   * Persisted `.fetching` state from a prior session (e.g. app kill
///     mid-fetch) had no recovery hatch anywhere except `ScanDetailView`.
///     The queue row and lot-detail row stayed stuck on "fetching…".
///
/// Both failure modes are covered here:
///   1. `compFetchedAt` is **not** stamped at fetch entry.
///   2. `compFetchStartedAt` IS stamped at fetch entry and drives
///      `CompFetchService.isStaleFetching`.
///   3. A successful landing stamps `compFetchedAt` after the snapshot
///      persists, with the resolved state.
@Suite("CompFetchService freshness (C2)", .serialized)
@MainActor
struct CompFreshnessTests {

    // MARK: - Fixtures

    static let identityId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let storeId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let lotId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let userId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let baseURL = URL(string: "https://test.invalid/functions/v1")!

    private static func makeHarness() throws -> (
        container: ModelContainer,
        context: ModelContext,
        repository: CompRepository
    ) {
        MockURLProtocol.reset()
        CompFetchService.shared._resetForTests()
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let repository = CompRepository(
            urlSession: MockURLProtocol.session(),
            baseURL: baseURL,
            authTokenProvider: { "test-token" }
        )
        return (container, context, repository)
    }

    private static func insertValidatedScan(in context: ModelContext) -> Scan {
        let now = Date()
        let scan = Scan(
            id: UUID(),
            storeId: storeId,
            lotId: lotId,
            userId: userId,
            grader: .PSA,
            certNumber: "FRESH001",
            grade: "10",
            gradedCardIdentityId: identityId,
            status: .validated,
            createdAt: now,
            updatedAt: now
        )
        context.insert(scan)
        try? context.save()
        return scan
    }

    nonisolated static func httpResponse(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL.appendingPathComponent("/price-comp"),
                        statusCode: status,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"])!
    }

    // MARK: - 1. compFetchedAt must not be stamped before the network resolves

    @Test("compFetchedAt is NOT stamped at fetch entry — only after the network lands")
    func compFetchedAtNotStampedAtEntry() async throws {
        let h = try Self.makeHarness()

        // Hold the network on a continuation so the in-flight window is
        // observable from the test body. Without this gate, the request
        // resolves too fast to assert against the "still spinning" state.
        let gate = DispatchSemaphore(value: 0)
        MockURLProtocol.requestHandler = { _ in
            gate.wait()
            return (Self.httpResponse(status: 200), CompFetchE2ETests.v3FullJSON.data(using: .utf8))
        }

        let scan = Self.insertValidatedScan(in: h.context)
        #expect(scan.compFetchedAt == nil, "Pre-fetch: scan has never been fetched, compFetchedAt should be nil")

        CompFetchService.fetch(scan: scan, repository: h.repository, context: h.context)

        // Yield so the Task spawned inside `fetch` runs through its first
        // synchronous prologue (which is where pre-C2 stamped the lie).
        try await Task.sleep(for: .milliseconds(50))

        // Read state while the network is still blocked.
        let scanId = scan.id
        var fetched = try h.context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate { $0.id == scanId })
        ).first!
        #expect(fetched.compFetchState == CompFetchState.fetching.rawValue, "Scan should be in fetching state")
        #expect(fetched.compFetchedAt == nil,
                "compFetchedAt must remain nil while the fetch is in flight — otherwise the UI lies about freshness")
        #expect(fetched.compFetchStartedAt != nil,
                "compFetchStartedAt must be stamped so stale-fetch detection has an anchor")

        // Release the network, wait for the Task tail to land.
        gate.signal()
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(2_000))
        while ContinuousClock.now < deadline {
            fetched = try h.context.fetch(
                FetchDescriptor<Scan>(predicate: #Predicate { $0.id == scanId })
            ).first!
            if fetched.compFetchState == CompFetchState.resolved.rawValue { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        // Post-landing: now compFetchedAt is finally stamped.
        #expect(fetched.compFetchState == CompFetchState.resolved.rawValue)
        #expect(fetched.compFetchedAt != nil,
                "After a successful landing, compFetchedAt must be stamped so the UI can show 'Last refreshed …'")
    }

    // MARK: - 2. isStaleFetching surfaces ghost in-flight rows

    @Test("isStaleFetching returns true for a .fetching scan whose start is older than 90s")
    func staleFetchingDetectedByThreshold() throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let scan = Self.insertValidatedScan(in: context)

        // Simulate a fetch that started 2 minutes ago and never landed
        // (the app was killed mid-fetch; the Task is gone).
        let now = Date()
        scan.compFetchState = CompFetchState.fetching.rawValue
        scan.compFetchStartedAt = now.addingTimeInterval(-120)
        scan.compFetchedAt = nil
        try context.save()

        #expect(CompFetchService.isStaleFetching(scan, now: now),
                "A .fetching scan started 120s ago must read as stale (>90s threshold)")
    }

    @Test("isStaleFetching returns false for a fresh .fetching scan")
    func freshFetchingNotStale() throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let scan = Self.insertValidatedScan(in: context)

        let now = Date()
        scan.compFetchState = CompFetchState.fetching.rawValue
        scan.compFetchStartedAt = now.addingTimeInterval(-5)  // 5s in
        try context.save()

        #expect(!CompFetchService.isStaleFetching(scan, now: now),
                "A .fetching scan started 5s ago must NOT read as stale — the network call is plausibly still alive")
    }

    @Test("isStaleFetching returns true for a .fetching scan with no start timestamp")
    func legacyFetchingWithoutStartedAtIsStale() throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let scan = Self.insertValidatedScan(in: context)

        // Legacy row: SwiftData migration backfilled .fetching but
        // compFetchStartedAt is nil. Treat that as definitively stale —
        // no anchor means no plausible in-flight task.
        scan.compFetchState = CompFetchState.fetching.rawValue
        scan.compFetchStartedAt = nil
        try context.save()

        #expect(CompFetchService.isStaleFetching(scan),
                "A .fetching row with no compFetchStartedAt anchor must read as stale")
    }

    @Test("isStaleFetching ignores non-fetching states")
    func nonFetchingStatesNeverStale() throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let scan = Self.insertValidatedScan(in: context)

        let now = Date()
        for state in [CompFetchState.resolved, .noData, .failed] {
            scan.compFetchState = state.rawValue
            scan.compFetchStartedAt = now.addingTimeInterval(-9_999)
            try context.save()
            #expect(!CompFetchService.isStaleFetching(scan, now: now),
                    "State \(state.rawValue) should never read as stale — staleness applies only to .fetching")
        }
    }

    // MARK: - 3. Successful fetch stamps compFetchedAt at landing

    @Test("happy path: successful landing stamps compFetchedAt with the resolved-state timestamp")
    func successfulFetchStampsFetchedAt() async throws {
        let h = try Self.makeHarness()
        MockURLProtocol.requestHandler = { _ in
            (Self.httpResponse(status: 200), CompFetchE2ETests.v3FullJSON.data(using: .utf8))
        }

        let scan = Self.insertValidatedScan(in: h.context)
        let beforeKickoff = Date()

        let scanId = scan.id
        CompFetchService.fetch(scan: scan, repository: h.repository, context: h.context)

        // Poll until the resolved state lands.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(2_000))
        var fetched: Scan!
        while ContinuousClock.now < deadline {
            fetched = try h.context.fetch(
                FetchDescriptor<Scan>(predicate: #Predicate { $0.id == scanId })
            ).first
            if fetched.compFetchState == CompFetchState.resolved.rawValue { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(fetched.compFetchState == CompFetchState.resolved.rawValue)
        let landedAt = try #require(fetched.compFetchedAt,
                                    "Successful fetch must stamp compFetchedAt")
        #expect(landedAt >= beforeKickoff,
                "compFetchedAt must be no earlier than fetch kickoff — otherwise it's a leftover from a previous run")
    }

    @Test("network failure stamps compFetchedAt at landing with .failed state")
    func failedFetchStampsFetchedAt() async throws {
        let h = try Self.makeHarness()
        MockURLProtocol.requestHandler = { _ in throw URLError(.timedOut) }

        let scan = Self.insertValidatedScan(in: h.context)
        let beforeKickoff = Date()
        let scanId = scan.id

        CompFetchService.fetch(scan: scan, repository: h.repository, context: h.context)

        let deadline = ContinuousClock.now.advanced(by: .milliseconds(2_000))
        var fetched: Scan!
        while ContinuousClock.now < deadline {
            fetched = try h.context.fetch(
                FetchDescriptor<Scan>(predicate: #Predicate { $0.id == scanId })
            ).first
            if fetched.compFetchState == CompFetchState.failed.rawValue { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(fetched.compFetchState == CompFetchState.failed.rawValue)
        let landedAt = try #require(fetched.compFetchedAt,
                                    "Failed fetch must stamp compFetchedAt so the user sees when we last tried")
        #expect(landedAt >= beforeKickoff)
    }

    // MARK: - 4. P1.5 — legacy `.fetching` rows on first launch after
    // C2 upgrade. The auto-recovery hatch fires `CompFetchService.fetch`
    // for every legacy row; the service de-dupes by
    // `(identityId, service, grade)` so two legacy rows of the same
    // slab tier collapse to one network call.

    @Test("legacy nil-start fetches dedupe — same identity/grade pair → one upstream call")
    func legacyRecoveryDedupesByIdentity() async throws {
        let h = try Self.makeHarness()
        let gate = DispatchSemaphore(value: 0)
        MockURLProtocol.requestHandler = { _ in
            gate.wait()
            return (Self.httpResponse(status: 200), CompFetchE2ETests.v3FullJSON.data(using: .utf8))
        }

        // Two scans, same `(identityId, grader, grade)` — like two
        // copies of the same slab tier across different lots in a real
        // store. Both pre-date the C2 migration: `.fetching` with no
        // `compFetchStartedAt`.
        let now = Date()
        let scanA = Scan(
            id: UUID(),
            storeId: Self.storeId, lotId: Self.lotId, userId: Self.userId,
            grader: .PSA, certNumber: "LEGACY-A", grade: "10",
            gradedCardIdentityId: Self.identityId,
            status: .validated,
            createdAt: now, updatedAt: now
        )
        scanA.compFetchState = CompFetchState.fetching.rawValue
        scanA.compFetchStartedAt = nil
        h.context.insert(scanA)
        let scanB = Scan(
            id: UUID(),
            storeId: Self.storeId, lotId: Self.lotId, userId: Self.userId,
            grader: .PSA, certNumber: "LEGACY-B", grade: "10",
            gradedCardIdentityId: Self.identityId,
            status: .validated,
            createdAt: now, updatedAt: now
        )
        scanB.compFetchState = CompFetchState.fetching.rawValue
        scanB.compFetchStartedAt = nil
        h.context.insert(scanB)
        try h.context.save()

        // Simulate the per-screen recovery walk: fire fetch for every
        // legacy row. Real call sites are LotDetailView.task /
        // BulkScanView.onAppear; the dedup test exercises the
        // service-level invariant.
        CompFetchService.fetch(scan: scanA, repository: h.repository, context: h.context)
        CompFetchService.fetch(scan: scanB, repository: h.repository, context: h.context)

        // Give the spawned tasks a moment to land their handler.
        try await Task.sleep(for: .milliseconds(50))
        gate.signal()

        _ = await Self.waitForCompFetch(scanId: scanA.id, in: h.context)
        _ = await Self.waitForCompFetch(scanId: scanB.id, in: h.context)

        #expect(MockURLProtocol.capturedRequests.count == 1,
                "Two legacy rows for the same slab tier must collapse to one upstream call — alarm fatigue avoidance")
    }

    /// Polls a `Scan` row until its `compFetchState` moves off `fetching`
    /// or the deadline elapses. Mirrors `CompFetchE2ETests.waitForCompFetch`
    /// so the legacy-recovery test reads cleanly.
    private static func waitForCompFetch(
        scanId: UUID,
        in context: ModelContext,
        timeout: Duration = .milliseconds(2_000)
    ) async -> String? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            var descriptor = FetchDescriptor<Scan>(predicate: #Predicate { $0.id == scanId })
            descriptor.fetchLimit = 1
            let state = (try? context.fetch(descriptor).first)?.compFetchState
            if let state, state != CompFetchState.fetching.rawValue {
                return state
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }
}
