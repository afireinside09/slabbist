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

    /// Canonical full-ladder PPT payload used by the happy-path test. Mirrors
    /// the `CompRepository.Wire` shape exactly.
    static let fullLadderJSON: String = """
    {
      "headline_price_cents": 18500,
      "grading_service": "PSA",
      "grade": "10",
      "loose_price_cents": 400,
      "psa_7_price_cents": 2400,
      "psa_8_price_cents": 3400,
      "psa_9_price_cents": 6800,
      "psa_9_5_price_cents": 11200,
      "psa_10_price_cents": 18500,
      "bgs_10_price_cents": 21500,
      "cgc_10_price_cents": 16800,
      "sgc_10_price_cents": 16500,
      "price_history": [
        { "ts": "2025-11-08T00:00:00Z", "price_cents": 16200 },
        { "ts": "2025-11-15T00:00:00Z", "price_cents": 16850 }
      ],
      "ppt_tcgplayer_id": "243172",
      "ppt_url": "https://www.pokemonpricetracker.com/card/charizard-base-set",
      "fetched_at": "2026-05-07T22:14:03Z",
      "cache_hit": false,
      "is_stale_fallback": false
    }
    """

    // MARK: - 1. Happy path

    @Test("happy path: 200 → snapshot persisted, scan resolved")
    func happyPath() async throws {
        let h = try Self.makeHarness()
        MockURLProtocol.requestHandler = { _ in
            (Self.httpResponse(status: 200), Self.fullLadderJSON.data(using: .utf8))
        }

        // Direct repository assertion — the wire shape decodes correctly.
        let decoded = try await h.repository.fetchComp(
            identityId: Self.fixedIdentityId,
            gradingService: "PSA",
            grade: "10"
        )
        #expect(decoded.headlinePriceCents == 18500)
        #expect(decoded.psa10PriceCents == 18500)
        #expect(decoded.bgs10PriceCents == 21500)
        #expect(decoded.psa9_5PriceCents == 11200)
        #expect(decoded.loosePriceCents == 400)
        #expect(decoded.priceHistory.count == 2)
        #expect(decoded.pptTCGPlayerId == "243172")
        #expect(decoded.isStaleFallback == false)

        // Now the service path: persists a snapshot, flips state to .resolved.
        let scan = Self.insertValidatedScan(in: h.context)
        CompFetchService.fetch(scan: scan, repository: h.repository, context: h.context)
        let finalState = await Self.waitForCompFetch(scanId: scan.id, in: h.context)
        #expect(finalState == CompFetchState.resolved.rawValue)

        let snapshots = try h.context.fetch(FetchDescriptor<GradedMarketSnapshot>())
        #expect(snapshots.count == 1)
        let snap = try #require(snapshots.first)
        #expect(snap.identityId == Self.fixedIdentityId)
        #expect(snap.gradingService == "PSA")
        #expect(snap.grade == "10")
        #expect(snap.headlinePriceCents == 18500)
        #expect(snap.psa10PriceCents == 18500)
        #expect(snap.bgs10PriceCents == 21500)
        #expect(snap.loosePriceCents == 400)
        #expect(snap.pptTCGPlayerId == "243172")
        #expect(snap.isStaleFallback == false)
        #expect(snap.priceHistory.count == 2)
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
        #expect(message == "We couldn't find this card on Pokemon Price Tracker.")
    }

    // MARK: - 5. 404 NO_MARKET_DATA

    @Test("404 NO_MARKET_DATA → noData + supported-tier copy")
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
        #expect(message == "Pokemon Price Tracker has no comp for this slab yet.")
    }

    // MARK: - 6. 502 AUTH_INVALID

    @Test("502 AUTH_INVALID → authInvalid + misconfigured copy")
    func authInvalid() async throws {
        let h = try Self.makeHarness()
        let body = #"{"code":"AUTH_INVALID"}"#.data(using: .utf8)
        MockURLProtocol.requestHandler = { _ in (Self.httpResponse(status: 502), body) }

        await #expect(throws: CompRepository.Error.authInvalid) {
            _ = try await h.repository.fetchComp(
                identityId: Self.fixedIdentityId,
                gradingService: "PSA",
                grade: "10"
            )
        }

        let (state, message) = CompFetchService.classify(CompRepository.Error.authInvalid)
        #expect(state == .failed)
        #expect(message == "Comp lookup misconfigured — contact support.")
    }

    // MARK: - 7. 503 UPSTREAM_UNAVAILABLE

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
        #expect(message == "Pokemon Price Tracker lookup unavailable — try again.")
    }

    // MARK: - 8. Stale fallback

    @Test("stale fallback → snapshot persisted with isStaleFallback=true")
    func staleFallback() async throws {
        let h = try Self.makeHarness()
        let staleJSON = """
        {
          "headline_price_cents": 12000,
          "grading_service": "PSA",
          "grade": "10",
          "loose_price_cents": 350,
          "psa_7_price_cents": null,
          "psa_8_price_cents": null,
          "psa_9_price_cents": 5000,
          "psa_9_5_price_cents": null,
          "psa_10_price_cents": 12000,
          "bgs_10_price_cents": null,
          "cgc_10_price_cents": null,
          "sgc_10_price_cents": null,
          "price_history": [],
          "ppt_tcgplayer_id": "111",
          "ppt_url": "https://www.pokemonpricetracker.com/card/stale",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": true,
          "is_stale_fallback": true
        }
        """
        MockURLProtocol.requestHandler = { _ in
            (Self.httpResponse(status: 200), staleJSON.data(using: .utf8))
        }

        let decoded = try await h.repository.fetchComp(
            identityId: Self.fixedIdentityId,
            gradingService: "PSA",
            grade: "10"
        )
        #expect(decoded.isStaleFallback == true)
        #expect(decoded.cacheHit == true)

        let scan = Self.insertValidatedScan(in: h.context)
        CompFetchService.fetch(scan: scan, repository: h.repository, context: h.context)
        let finalState = await Self.waitForCompFetch(scanId: scan.id, in: h.context)
        #expect(finalState == CompFetchState.resolved.rawValue)

        let snapshots = try h.context.fetch(FetchDescriptor<GradedMarketSnapshot>())
        let snap = try #require(snapshots.first)
        #expect(snap.isStaleFallback == true)
        #expect(snap.cacheHit == true)
    }

    // MARK: - 9. JP card (only loose populated)

    @Test("JP card → only loosePriceCents populated, all PSA tiers nil")
    func jpRawOnly() async throws {
        let h = try Self.makeHarness()
        let jpJSON = """
        {
          "headline_price_cents": null,
          "grading_service": "PSA",
          "grade": "10",
          "loose_price_cents": 800,
          "psa_7_price_cents": null,
          "psa_8_price_cents": null,
          "psa_9_price_cents": null,
          "psa_9_5_price_cents": null,
          "psa_10_price_cents": null,
          "bgs_10_price_cents": null,
          "cgc_10_price_cents": null,
          "sgc_10_price_cents": null,
          "price_history": [],
          "ppt_tcgplayer_id": "999",
          "ppt_url": "https://www.pokemonpricetracker.com/card/jp",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": false,
          "is_stale_fallback": false
        }
        """
        MockURLProtocol.requestHandler = { _ in
            (Self.httpResponse(status: 200), jpJSON.data(using: .utf8))
        }

        let decoded = try await h.repository.fetchComp(
            identityId: Self.fixedIdentityId,
            gradingService: "PSA",
            grade: "10"
        )
        #expect(decoded.headlinePriceCents == nil)
        #expect(decoded.loosePriceCents == 800)
        #expect(decoded.psa10PriceCents == nil)
        #expect(decoded.bgs10PriceCents == nil)
        #expect(decoded.cgc10PriceCents == nil)
        #expect(decoded.sgc10PriceCents == nil)
        #expect(decoded.priceHistory.isEmpty)

        let scan = Self.insertValidatedScan(in: h.context)
        CompFetchService.fetch(scan: scan, repository: h.repository, context: h.context)
        let finalState = await Self.waitForCompFetch(scanId: scan.id, in: h.context)
        #expect(finalState == CompFetchState.resolved.rawValue)

        let snapshots = try h.context.fetch(FetchDescriptor<GradedMarketSnapshot>())
        let snap = try #require(snapshots.first)
        #expect(snap.loosePriceCents == 800)
        #expect(snap.headlinePriceCents == nil)
        #expect(snap.psa10PriceCents == nil)
        #expect(snap.bgs10PriceCents == nil)
        #expect(snap.priceHistoryJSON == nil)
    }

    // MARK: - 10. Decoding error (malformed JSON)

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

    // MARK: - 11. In-flight de-dup

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
            return (Self.httpResponse(status: 200), Self.fullLadderJSON.data(using: .utf8))
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
}
