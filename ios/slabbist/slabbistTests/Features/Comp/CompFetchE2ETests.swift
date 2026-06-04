import Testing
import Foundation
import SwiftData
@testable import slabbist

/// End-to-end coverage of the comp fetch lifecycle:
///   `Scan → CompRepository.fetchComp → persistSnapshot → state flip`
///
/// Stubs the network layer with `MockURLProtocol` and runs the real
/// `CompFetchService` + `CompRepository` against an in-memory SwiftData
/// container, so each scenario exercises the full pipeline.
///
/// `.serialized` because `MockURLProtocol` is a process-wide singleton and
/// `CompFetchService.shared` keeps in-flight task state across calls — both
/// would race if these tests ran in parallel.
@Suite("CompFetch end-to-end", .serialized)
@MainActor
struct CompFetchE2ETests {

    // MARK: - Fixture builders

    // Static fixtures are Sendable constants — readable from the `@Sendable`
    // closures passed to `MockURLProtocol.requestHandler` even though the
    // surrounding suite type is `@MainActor`.
    static let baseURL = URL(string: "https://test.invalid/functions/v1")!

    static let fixedIdentityId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let fixedStoreId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let fixedLotId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let fixedUserId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    /// Builds a fresh in-memory container + a `ModelContext` rooted in it,
    /// alongside a `CompRepository` wired to `MockURLProtocol`'s session.
    /// Always reset the mock + service singleton up front so cross-test
    /// state can't leak.
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

    /// Inserts a freshly-validated `Scan` (cert-lookup already happened) into
    /// the in-memory context. Uses the canonical fixture identity so the
    /// service's `flipMatching` predicate finds it.
    private static func insertValidatedScan(
        in context: ModelContext,
        certNumber: String = "00000001",
        grader: Grader = .PSA,
        grade: String = "10"
    ) -> Scan {
        let now = Date()
        let scan = Scan(
            id: UUID(),
            storeId: fixedStoreId,
            lotId: fixedLotId,
            userId: fixedUserId,
            grader: grader,
            certNumber: certNumber,
            grade: grade,
            gradedCardIdentityId: fixedIdentityId,
            status: .validated,
            createdAt: now,
            updatedAt: now
        )
        context.insert(scan)
        try? context.save()
        return scan
    }

    /// Builds an `HTTPURLResponse` for a given status code against the test
    /// base URL. Used by every `requestHandler` closure below. Marked
    /// `nonisolated` so the closures (which are `@Sendable` and run off the
    /// main actor inside `URLProtocol`) can reference it directly.
    nonisolated static func httpResponse(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL.appendingPathComponent("/price-comp"),
                        statusCode: status,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"])!
    }

    /// Polls a `Scan` row until its `compFetchState` moves off `fetching` or
    /// the deadline elapses. Returns the resolved state string for asserting.
    /// Necessary because `CompFetchService.fetch` kicks off a detached
    /// `Task { @MainActor }` and returns immediately — the test must wait for
    /// the async tail to land before reading state.
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

    /// Canonical v3 Poketrace payload used by the happy-path test.
    /// Matches the `CompRepository.Wire` v3 shape exactly.
    static let v3FullJSON: String = """
    {
      "grading_service": "PSA",
      "grade": "10",
      "headline_price_cents": 19500,
      "poketrace": {
        "card_id": "22222222-2222-2222-2222-222222222222",
        "tier": "PSA_10",
        "avg_cents": 19500,
        "low_cents": 18000,
        "high_cents": 21000,
        "avg_1d_cents": null,
        "avg_7d_cents": 19400,
        "avg_30d_cents": 19200,
        "median_3d_cents": 19500,
        "median_7d_cents": 19350,
        "median_30d_cents": 19000,
        "trend": "stable",
        "confidence": "high",
        "sale_count": 24,
        "tier_prices_cents": { "psa_10": 19500, "psa_9": 6800 },
        "price_history": [
          { "ts": "2026-04-30T00:00:00Z", "price_cents": 19200 }
        ],
        "fetched_at": "2026-05-07T22:14:03Z"
      },
      "sold_listings": [
        {
          "source_listing_id": "ebay-001",
          "title": "Charizard PSA 10",
          "price_cents": 19500,
          "sold_at": "2026-04-28T10:00:00Z",
          "grader": "PSA",
          "grade": "10",
          "condition": "Graded",
          "url": "https://www.ebay.com/itm/001",
          "anomaly_flag": null
        },
        {
          "source_listing_id": "ebay-002",
          "title": "Charizard PSA 10 Base",
          "price_cents": 20000,
          "sold_at": "2026-04-25T14:00:00Z",
          "grader": "PSA",
          "grade": "10",
          "condition": "Graded",
          "url": "https://www.ebay.com/itm/002",
          "anomaly_flag": null
        }
      ],
      "marketplace_url": "https://www.ebay.com/sch/i.html?_nkw=charizard+psa+10",
      "fetched_at": "2026-05-07T22:14:03Z",
      "cache_hit": false
    }
    """

    // MARK: - 1. Happy path

    @Test("happy path: 200 → single poketrace snapshot persisted, soldListingsJSON set, scan resolved")
    func happyPath() async throws {
        let h = try Self.makeHarness()
        MockURLProtocol.requestHandler = { _ in
            (Self.httpResponse(status: 200), Self.v3FullJSON.data(using: .utf8))
        }

        // Direct repository assertion — the v3 wire shape decodes correctly.
        let decoded = try await h.repository.fetchComp(
            identityId: Self.fixedIdentityId,
            gradingService: "PSA",
            grade: "10"
        )
        #expect(decoded.headlinePriceCents == 19500)
        #expect(decoded.poketrace?.avgCents == 19500)
        #expect(decoded.soldListings.count == 2)
        #expect(decoded.marketplaceURL != nil)
        #expect(decoded.cacheHit == false)

        // Now the service path: persists a single snapshot, flips state to .resolved.
        let scan = Self.insertValidatedScan(in: h.context)
        CompFetchService.fetch(scan: scan, repository: h.repository, context: h.context)
        let finalState = await Self.waitForCompFetch(scanId: scan.id, in: h.context)
        #expect(finalState == CompFetchState.resolved.rawValue)

        let snapshots = try h.context.fetch(FetchDescriptor<GradedMarketSnapshot>())
        // Single poketrace snapshot — no PPT row.
        #expect(snapshots.count == 1)
        let snap = try #require(snapshots.first)
        #expect(snap.identityId == Self.fixedIdentityId)
        #expect(snap.gradingService == "PSA")
        #expect(snap.grade == "10")
        #expect(snap.source == GradedMarketSnapshot.sourcePoketrace)
        #expect(snap.headlinePriceCents == 19500)
        #expect(snap.ptAvgCents == 19500)
        #expect(snap.cacheHit == false)
        #expect(snap.soldListingsJSON != nil)
        #expect(snap.soldListings.count == 2)
        #expect(snap.marketplaceURL != nil)
    }

    // MARK: - 2. Network failure (URLError.timedOut)

    @Test("network timeout → service marks scan failed, no snapshot")
    func networkTimeout() async throws {
        let h = try Self.makeHarness()
        MockURLProtocol.requestHandler = { _ in throw URLError(.timedOut) }

        // fetchComp itself throws — the inner URLError propagates up.
        await #expect(throws: (any Error).self) {
            _ = try await h.repository.fetchComp(
                identityId: Self.fixedIdentityId,
                gradingService: "PSA",
                grade: "10"
            )
        }

        // Through the service: scan ends up `.failed`, no snapshot row.
        let scan = Self.insertValidatedScan(in: h.context)
        CompFetchService.fetch(scan: scan, repository: h.repository, context: h.context)
        let finalState = await Self.waitForCompFetch(scanId: scan.id, in: h.context)
        #expect(finalState == CompFetchState.failed.rawValue)

        let snapshots = try h.context.fetch(FetchDescriptor<GradedMarketSnapshot>())
        #expect(snapshots.isEmpty)
    }

    // MARK: - 3. 404 IDENTITY_NOT_FOUND

    @Test("404 IDENTITY_NOT_FOUND → identityNotFound + re-scan copy")
    func identityNotFound() async throws {
        let h = try Self.makeHarness()
        let body = #"{"code":"IDENTITY_NOT_FOUND"}"#.data(using: .utf8)
        MockURLProtocol.requestHandler = { _ in (Self.httpResponse(status: 404), body) }

        await #expect(throws: CompRepository.Error.identityNotFound) {
            _ = try await h.repository.fetchComp(
                identityId: Self.fixedIdentityId,
                gradingService: "PSA",
                grade: "10"
            )
        }

        let (state, message) = CompFetchService.classify(CompRepository.Error.identityNotFound)
        #expect(state == .failed)
        #expect(message == "Card identity not on file — re-scan to refresh the cert.")
    }

    // MARK: - 4. 404 PRODUCT_NOT_RESOLVED

    @Test("404 PRODUCT_NOT_RESOLVED → noData + couldn't-find copy")
    func productNotResolved() async throws {
        let h = try Self.makeHarness()
        let body = #"{"code":"PRODUCT_NOT_RESOLVED"}"#.data(using: .utf8)
        MockURLProtocol.requestHandler = { _ in (Self.httpResponse(status: 404), body) }

        await #expect(throws: CompRepository.Error.productNotResolved) {
            _ = try await h.repository.fetchComp(
                identityId: Self.fixedIdentityId,
                gradingService: "PSA",
                grade: "10"
            )
        }

        let (state, message) = CompFetchService.classify(CompRepository.Error.productNotResolved)
        #expect(state == .noData)
        #expect(message == "We couldn't find this card on Poketrace.")
    }

    // MARK: - 5. 404 NO_MARKET_DATA

    @Test("404 NO_MARKET_DATA → noData + Poketrace-flavored copy")
    func noMarketData() async throws {
        let h = try Self.makeHarness()
        let body = #"{"code":"NO_MARKET_DATA"}"#.data(using: .utf8)
        MockURLProtocol.requestHandler = { _ in (Self.httpResponse(status: 404), body) }

        await #expect(throws: CompRepository.Error.noMarketData) {
            _ = try await h.repository.fetchComp(
                identityId: Self.fixedIdentityId,
                gradingService: "PSA",
                grade: "10"
            )
        }

        let (state, message) = CompFetchService.classify(CompRepository.Error.noMarketData)
        #expect(state == .noData)
        #expect(message == "Poketrace has no comp for this slab yet.")
    }

    // MARK: - 6. 503 UPSTREAM_UNAVAILABLE

    @Test("503 UPSTREAM_UNAVAILABLE → upstreamUnavailable + try-again copy")
    func upstreamUnavailable() async throws {
        let h = try Self.makeHarness()
        let body = #"{"code":"UPSTREAM_UNAVAILABLE"}"#.data(using: .utf8)
        MockURLProtocol.requestHandler = { _ in (Self.httpResponse(status: 503), body) }

        await #expect(throws: CompRepository.Error.upstreamUnavailable) {
            _ = try await h.repository.fetchComp(
                identityId: Self.fixedIdentityId,
                gradingService: "PSA",
                grade: "10"
            )
        }

        let (state, message) = CompFetchService.classify(CompRepository.Error.upstreamUnavailable)
        #expect(state == .failed)
        #expect(message == "Poketrace lookup unavailable — try again.")
    }

    // MARK: - 7. Decoding error (malformed JSON)

    @Test("malformed 200 body → decoding error surfaces")
    func decodingError() async throws {
        let h = try Self.makeHarness()
        let bogus = #"{"this":"is broken"}"#.data(using: .utf8)
        MockURLProtocol.requestHandler = { _ in (Self.httpResponse(status: 200), bogus) }

        // The thrown error is `CompRepository.Error.decoding(_)` — we can't
        // pattern-match the associated value directly with `#expect(throws:)`,
        // so capture and inspect manually.
        var captured: (any Error)?
        do {
            _ = try await h.repository.fetchComp(
                identityId: Self.fixedIdentityId,
                gradingService: "PSA",
                grade: "10"
            )
        } catch {
            captured = error
        }
        let err = try #require(captured as? CompRepository.Error)
        guard case .decoding = err else {
            Issue.record("expected .decoding, got \(err)")
            return
        }

        let (state, message) = CompFetchService.classify(err)
        #expect(state == .failed)
        #expect(message.localizedCaseInsensitiveContains("couldn't decode"))
    }

    // MARK: - 8. In-flight de-dup

    @Test("two scans of same (identity, grader, grade) share one network call")
    func inFlightDedup() async throws {
        let h = try Self.makeHarness()

        // Hold the network response on a continuation so the second `fetch`
        // call lands while the first is still in flight (the only window
        // during which de-dup is observable).
        let gate = DispatchSemaphore(value: 0)
        MockURLProtocol.requestHandler = { _ in
            // Block the URLProtocol thread until the test releases the gate.
            // The handler runs off the main actor so this doesn't deadlock
            // the test's @MainActor body.
            gate.wait()
            return (Self.httpResponse(status: 200), Self.v3FullJSON.data(using: .utf8))
        }

        let scanA = Self.insertValidatedScan(in: h.context, certNumber: "AAA")
        let scanB = Self.insertValidatedScan(in: h.context, certNumber: "BBB")
        #expect(scanA.id != scanB.id)

        // Kick off both fetches synchronously (both are @MainActor calls
        // that return immediately after spawning their detached Task).
        CompFetchService.fetch(scan: scanA, repository: h.repository, context: h.context)
        CompFetchService.fetch(scan: scanB, repository: h.repository, context: h.context)

        // Yield enough times that the URLProtocol thread is blocked inside
        // the handler before we release it. ~50ms is plenty of margin.
        try await Task.sleep(for: .milliseconds(50))

        // Release the network response.
        gate.signal()

        let stateA = await Self.waitForCompFetch(scanId: scanA.id, in: h.context)
        let stateB = await Self.waitForCompFetch(scanId: scanB.id, in: h.context)
        #expect(stateA == CompFetchState.resolved.rawValue)
        #expect(stateB == CompFetchState.resolved.rawValue)

        // The de-dup contract: exactly one network request was issued.
        #expect(MockURLProtocol.capturedRequests.count == 1)

        // And only one snapshot row (persistSnapshot runs once per fetch task).
        let snapshots = try h.context.fetch(FetchDescriptor<GradedMarketSnapshot>())
        #expect(snapshots.count == 1)
    }

    // MARK: - 9. D4 — sibling-scan price isolation

    /// D4: refreshing ScanA's comp must NOT silently move ScanB's hero
    /// number. `reconciledHeadlinePriceCents` is the per-scan mirror of
    /// the server-computed headline; broadcasting it across every scan
    /// with the same `(identityId, grader, grade)` makes the user see a
    /// price flip with no surface explanation — the offending refresh
    /// happened on a different row.
    ///
    /// Locks in the existing scoping: persistSnapshots writes the
    /// headline mirror only to `scanId`. Siblings keep their old
    /// reconciled value (or `nil`) until they trigger their own fetch.
    @Test("D4: refresh on one scan does not mutate sibling's reconciledHeadlinePriceCents")
    func refreshDoesNotBroadcastReconciledHeadline() async throws {
        let h = try Self.makeHarness()
        MockURLProtocol.requestHandler = { _ in
            (Self.httpResponse(status: 200), Self.v3FullJSON.data(using: .utf8))
        }

        // Two scans of the same slab — same identity, same grader, same grade.
        let scanA = Self.insertValidatedScan(in: h.context, certNumber: "AAA")
        let scanB = Self.insertValidatedScan(in: h.context, certNumber: "BBB")

        // Seed ScanB with a prior reconciled value the user has been
        // looking at. If a refresh on ScanA broadcasts, this value gets
        // silently overwritten without the user's ScanB ever fetching.
        scanB.reconciledHeadlinePriceCents = 12_300
        try h.context.save()

        // Bind ids to locals so `#Predicate` can capture them cleanly.
        let aId = scanA.id
        let bId = scanB.id

        // Trigger a fetch on ScanA only.
        CompFetchService.fetch(scan: scanA, repository: h.repository, context: h.context)
        let stateA = await Self.waitForCompFetch(scanId: aId, in: h.context)
        #expect(stateA == CompFetchState.resolved.rawValue)

        // ScanA picks up the server's headline (19500 from the v3 fixture).
        let fetchedA = try h.context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate { $0.id == aId })
        ).first
        #expect(fetchedA?.reconciledHeadlinePriceCents == 19500)

        // ScanB's mirror stayed put — siblings are not silently rewritten.
        let fetchedB = try h.context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate { $0.id == bId })
        ).first
        #expect(fetchedB?.reconciledHeadlinePriceCents == 12_300)
    }

    /// D4 follow-on: after the first refresh, ScanB can still trigger its
    /// own fetch and pick up the fresh number. This proves the sibling
    /// isolation isn't a freshness-bypass — it's just a "no silent
    /// broadcast." User-initiated retry on ScanB always works.
    @Test("D4: sibling can still fetch its own comp and update its reconciled value")
    func siblingCanFetchAfterPeerRefresh() async throws {
        let h = try Self.makeHarness()
        MockURLProtocol.requestHandler = { _ in
            (Self.httpResponse(status: 200), Self.v3FullJSON.data(using: .utf8))
        }

        let scanA = Self.insertValidatedScan(in: h.context, certNumber: "AAA")
        let scanB = Self.insertValidatedScan(in: h.context, certNumber: "BBB")
        scanB.reconciledHeadlinePriceCents = 12_300
        try h.context.save()
        let aId = scanA.id
        let bId = scanB.id

        // First refresh: ScanA only. Then wait for the in-flight task to
        // clear so ScanB's fetch isn't absorbed into ScanA's.
        CompFetchService.fetch(scan: scanA, repository: h.repository, context: h.context)
        _ = await Self.waitForCompFetch(scanId: aId, in: h.context)

        // Second refresh: ScanB now. Must end up with the same fresh
        // headline as ScanA — whether through a cache hit or a fresh
        // network round-trip, both outcomes satisfy "user-initiated
        // retry surfaces the current number."
        CompFetchService.fetch(scan: scanB, repository: h.repository, context: h.context)
        let stateB = await Self.waitForCompFetch(scanId: bId, in: h.context)
        #expect(stateB == CompFetchState.resolved.rawValue)

        let fetchedB = try h.context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate { $0.id == bId })
        ).first
        #expect(fetchedB?.reconciledHeadlinePriceCents == 19500)
    }
}
