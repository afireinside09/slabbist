import Foundation
import Testing
import SwiftData
@testable import slabbist

/// C1 — `BulkScanViewModel.triggerCertLookup` & `retryValidation` behavior.
///
/// These suites exercise the post-network outcomes of a cert lookup
/// (URLError-class transient / not-found / not-pokemon / success →
/// retry-success / explicit `Task.cancel()` / offline short-circuit /
/// non-transient retry guard) end to end through the view model +
/// SwiftData persistence layer + the mocked `CertLookupRepository` HTTP
/// surface. The assertions encode the user-facing contract:
///   - transient failures keep `.pendingValidation` AND stamp
///     `validationFailureReason == "transient"` so the queue row can
///     surface a retry pill.
///   - terminal failures flip to `.validationFailed` with the right reason
///     so `ScanDetailView` can fork its empty state.
///   - `retryValidation` re-fires the lookup and lands a fresh terminal
///     outcome — `validationAttemptCount` carries across transient retries
///     but resets to 0 on success, and the method no-ops when called
///     against a non-transient scan.
///
/// Pre-C1 the catch path only logged + emitted a transient pill; every
/// assertion below that checks `validationFailureReason` would fail
/// against that legacy behavior, satisfying Rule 9 (tests verify intent).
@Suite("BulkScanViewModel cert-lookup C1", .serialized)
@MainActor
struct BulkScanCertLookupTests {

    // MARK: - Helpers

    /// Builds a viewModel pre-wired with an in-memory ModelContainer, a
    /// `Lot`, a mocked `CertLookupRepository`, and an optional reachability
    /// closure. Returns the freshly-recorded `Scan.id` for the caller to
    /// fetch / assert against.
    private static func bootstrap(
        reachability: ReachabilityStatus? = nil
    ) throws -> (vm: BulkScanViewModel, lot: Lot, context: ModelContext, repo: CertLookupRepository) {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let userId = UUID()
        let storeId = UUID()
        let lot = Lot(
            id: UUID(), storeId: storeId, createdByUserId: userId,
            name: "Test Lot", createdAt: Date(), updatedAt: Date()
        )
        context.insert(lot)
        try context.save()

        let session = MockURLProtocol.session()
        let repo = CertLookupRepository(
            urlSession: session,
            baseURL: URL(string: "https://example.test/functions/v1")!,
            authTokenProvider: { nil }
        )
        let reach = reachability
        let vm = BulkScanViewModel(
            context: context,
            kicker: OutboxKicker { },
            lot: lot,
            currentUserId: userId,
            compRepository: nil,
            certLookupRepository: repo,
            reachabilityStatus: reach.map { status in { status } }
        )
        return (vm, lot, context, repo)
    }

    /// Spins on a predicate until it returns true or the deadline elapses.
    /// `recordCapture` → `triggerCertLookup` → `Task` → `MainActor.run`
    /// crosses two suspension points; the SwiftData write lands in the
    /// next runloop tick. 5s is a generous ceiling — failing tests fail
    /// in <50ms.
    private static func waitFor(
        _ predicate: @MainActor () -> Bool,
        timeout: TimeInterval = 5
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("waitFor timed out after \(timeout)s")
    }

    private static func fetchScan(_ context: ModelContext, id: UUID) -> Scan? {
        var d = FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    private static let successResponseJSON = """
    {
      "identity_id": "11111111-1111-1111-1111-111111111111",
      "graded_card_id": "22222222-2222-2222-2222-222222222222",
      "grading_service": "PSA",
      "grade": "10",
      "card": {
        "set_name": "POKEMON GAME",
        "card_number": "4",
        "card_name": "CHARIZARD-HOLO",
        "variant": null,
        "year": 1999,
        "language": "en"
      },
      "cache_hit": false
    }
    """

    // MARK: - Smoke: schema migration is lightweight

    /// A freshly-constructed `Scan` defaults the four new C1 fields to nil
    /// / 0. SwiftData lightweight migration relies on these defaults to
    /// backfill rows on upgrade — failing this assertion means the init
    /// signature regressed and an existing store would refuse to open.
    @Test("Scan defaults new C1 fields to nil / 0")
    func scanDefaultsNewFields() throws {
        let scan = Scan(
            id: UUID(),
            storeId: UUID(),
            lotId: UUID(),
            userId: UUID(),
            grader: .PSA,
            certNumber: "12345678",
            createdAt: Date(),
            updatedAt: Date()
        )
        #expect(scan.validationFailureReason == nil)
        #expect(scan.validationFailureMessage == nil)
        #expect(scan.validationLastAttemptAt == nil)
        #expect(scan.validationAttemptCount == 0)
    }

    // MARK: - Transient failure (network / 5xx / cancellation)

    /// A `URLError(.notConnectedToInternet)` from the network is the
    /// canonical transient — the user has an iffy connection. The scan
    /// must stay `.pendingValidation` (so the queue row stays in the
    /// retry-pill flow), and the four new C1 fields must reflect a
    /// recorded attempt.
    @Test("network-level error → transient classification, attempt count = 1")
    func transientClassification() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let (vm, lot, context, _) = try Self.bootstrap()
        let candidate = CertCandidate(
            grader: .PSA, certNumber: "10000001",
            confidence: 0.9, rawText: "PSA 10000001"
        )
        try vm.record(candidate: candidate)
        let lotId = lot.id
        let scanId = try #require(try context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        ).first?.id)

        try await Self.waitFor {
            Self.fetchScan(context, id: scanId)?.validationFailureReason == "transient"
        }

        let scan = try #require(Self.fetchScan(context, id: scanId))
        #expect(scan.status == .pendingValidation)
        #expect(scan.validationFailureReason == "transient")
        #expect(scan.validationLastAttemptAt != nil)
        #expect(scan.validationAttemptCount == 1)
        #expect(scan.validationFailureMessage != nil)
    }

    // MARK: - Retry path

    /// First lookup throws transient; second (after retry) returns 200.
    /// Final state must be `.validated` with `gradedCardIdentityId` set —
    /// proving `retryValidation` re-enters the same code path the initial
    /// trigger uses.
    @Test("retryValidation re-fires lookup; transient → validated")
    func retrySucceedsOnSecondAttempt() async throws {
        MockURLProtocol.reset()
        // Use atomic counter to flip handler behavior across calls.
        let callCount = AtomicInt()
        MockURLProtocol.requestHandler = { _ in
            let n = callCount.increment()
            if n == 1 {
                throw URLError(.timedOut)
            }
            let resp = HTTPURLResponse(
                url: URL(string: "https://example.test/functions/v1/cert-lookup")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (resp, Self.successResponseJSON.data(using: .utf8)!)
        }
        let (vm, lot, context, _) = try Self.bootstrap()
        try vm.record(candidate: CertCandidate(
            grader: .PSA, certNumber: "20000002",
            confidence: 0.92, rawText: "PSA 20000002"
        ))
        let lotId = lot.id
        let scan = try #require(try context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        ).first)

        try await Self.waitFor {
            Self.fetchScan(context, id: scan.id)?.validationFailureReason == "transient"
        }

        vm.retryValidation(scan: scan)

        try await Self.waitFor {
            Self.fetchScan(context, id: scan.id)?.status == .validated
        }

        let final = try #require(Self.fetchScan(context, id: scan.id))
        #expect(final.status == .validated)
        #expect(final.gradedCardIdentityId == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(final.validationFailureReason == nil)
        #expect(final.validationFailureMessage == nil)
        // P0.1: the success branch must zero the attempt counter so a future
        // re-entry into validation starts from a clean slate. Pre-fix this
        // stays at 1 (the count from the failed first attempt).
        #expect(final.validationAttemptCount == 0)
    }

    // MARK: - certNotFound terminal path

    /// PSA returned 404 CERT_NOT_FOUND → flip to `.validationFailed` with
    /// `validationFailureReason == "not_found"`. The detail screen forks
    /// on that exact pair to render its "delete and rescan" empty state.
    @Test("404 CERT_NOT_FOUND → validationFailed + not_found reason")
    func certNotFoundTerminal() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://example.test/functions/v1/cert-lookup")!,
                statusCode: 404, httpVersion: nil, headerFields: nil
            )!
            return (resp, #"{"code":"CERT_NOT_FOUND"}"#.data(using: .utf8)!)
        }
        let (vm, lot, context, _) = try Self.bootstrap()
        try vm.record(candidate: CertCandidate(
            grader: .PSA, certNumber: "30000003",
            confidence: 0.9, rawText: "PSA 30000003"
        ))
        let lotId = lot.id
        let scanId = try #require(try context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        ).first?.id)

        try await Self.waitFor {
            Self.fetchScan(context, id: scanId)?.status == .validationFailed
        }

        let scan = try #require(Self.fetchScan(context, id: scanId))
        #expect(scan.status == .validationFailed)
        #expect(scan.validationFailureReason == "not_found")
        #expect(scan.validationLastAttemptAt != nil)
    }

    // MARK: - notPokemon terminal path

    /// PSA cert resolves to a non-Pokemon product (415 NOT_POKEMON) →
    /// terminal `.validationFailed` + `"not_pokemon"`. Different copy on
    /// the detail screen, but same status flip as `not_found`.
    @Test("415 NOT_POKEMON → validationFailed + not_pokemon reason")
    func notPokemonTerminal() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://example.test/functions/v1/cert-lookup")!,
                statusCode: 415, httpVersion: nil, headerFields: nil
            )!
            return (resp, #"{"code":"NOT_POKEMON"}"#.data(using: .utf8)!)
        }
        let (vm, lot, context, _) = try Self.bootstrap()
        try vm.record(candidate: CertCandidate(
            grader: .PSA, certNumber: "40000004",
            confidence: 0.9, rawText: "PSA 40000004"
        ))
        let lotId = lot.id
        let scanId = try #require(try context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        ).first?.id)

        try await Self.waitFor {
            Self.fetchScan(context, id: scanId)?.status == .validationFailed
        }

        let scan = try #require(Self.fetchScan(context, id: scanId))
        #expect(scan.status == .validationFailed)
        #expect(scan.validationFailureReason == "not_pokemon")
    }

    // MARK: - Attempt counter accumulates

    /// Three transient failures in a row → `validationAttemptCount == 3`.
    /// The queue pill copy and detail-screen "we've tried N times" hint
    /// both depend on this monotonic increment.
    @Test("attempt counter accumulates across three transient failures")
    func attemptCounterAccumulates() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.networkConnectionLost)
        }
        let (vm, lot, context, _) = try Self.bootstrap()
        try vm.record(candidate: CertCandidate(
            grader: .PSA, certNumber: "50000005",
            confidence: 0.9, rawText: "PSA 50000005"
        ))
        let lotId = lot.id
        let scan = try #require(try context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        ).first)

        try await Self.waitFor {
            Self.fetchScan(context, id: scan.id)?.validationAttemptCount == 1
        }

        vm.retryValidation(scan: scan)
        try await Self.waitFor {
            Self.fetchScan(context, id: scan.id)?.validationAttemptCount == 2
        }

        vm.retryValidation(scan: scan)
        try await Self.waitFor {
            Self.fetchScan(context, id: scan.id)?.validationAttemptCount == 3
        }

        let final = try #require(Self.fetchScan(context, id: scan.id))
        #expect(final.validationAttemptCount == 3)
        #expect(final.validationFailureReason == "transient")
        #expect(final.status == .pendingValidation)
    }

    // MARK: - Offline short-circuit

    /// When `Reachability.status == .offline`, the VM must skip the
    /// network call entirely and record a transient failure with the
    /// "Offline" message. Asserts via `capturedRequests.isEmpty` so the
    /// short-circuit really happened — a passing test with a leaked
    /// network call would prove the guard didn't fire.
    @Test("offline reachability short-circuits the network call")
    func offlineShortCircuit() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.badURL)  // sentinel — should never fire
        }
        let (vm, lot, context, _) = try Self.bootstrap(reachability: .offline)
        try vm.record(candidate: CertCandidate(
            grader: .PSA, certNumber: "60000006",
            confidence: 0.9, rawText: "PSA 60000006"
        ))
        let lotId = lot.id
        let scanId = try #require(try context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        ).first?.id)

        try await Self.waitFor {
            Self.fetchScan(context, id: scanId)?.validationFailureReason == "transient"
        }

        let scan = try #require(Self.fetchScan(context, id: scanId))
        #expect(scan.status == .pendingValidation)
        #expect(scan.validationFailureReason == "transient")
        #expect(scan.validationFailureMessage == "Offline — will retry when connected")
        #expect(MockURLProtocol.capturedRequests.isEmpty)
    }

    // MARK: - P0.2: retry honors offline (asymmetry fix)

    /// `retryValidation` is the path the detail screen drives when the user
    /// taps the gold "Retry cert lookup" CTA. The fresh VM built there
    /// forwards the env-injected `Reachability`; this test asserts the
    /// short-circuit fires when that VM is offline. Pre-fix the VM was
    /// constructed with `reachabilityStatus: nil`, so the retry would
    /// always hit the network.
    @Test("retryValidation honors offline reachability")
    func retryHonorsOffline() async throws {
        MockURLProtocol.reset()
        // First the scan lands a transient failure on a live (online) call.
        // Then the second handler invocation should never fire — flipping to
        // a sentinel throw asserts the offline short-circuit prevented the
        // request.
        let callCount = AtomicInt()
        MockURLProtocol.requestHandler = { _ in
            let n = callCount.increment()
            if n == 1 {
                throw URLError(.timedOut)
            }
            Issue.record("retry should not have made a network call while offline")
            throw URLError(.badURL)
        }
        // Bootstrap online, record a scan, wait for the transient stamp.
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let userId = UUID()
        let storeId = UUID()
        let lot = Lot(
            id: UUID(), storeId: storeId, createdByUserId: userId,
            name: "Test", createdAt: Date(), updatedAt: Date()
        )
        context.insert(lot)
        try context.save()
        let session = MockURLProtocol.session()
        let repo = CertLookupRepository(
            urlSession: session,
            baseURL: URL(string: "https://example.test/functions/v1")!,
            authTokenProvider: { nil }
        )
        // Flip reachability between init and retry to simulate the user
        // losing connection between the failed initial call and tapping
        // the retry button.
        var currentStatus: ReachabilityStatus = .online
        let vm = BulkScanViewModel(
            context: context,
            kicker: OutboxKicker { },
            lot: lot,
            currentUserId: userId,
            compRepository: nil,
            certLookupRepository: repo,
            reachabilityStatus: { currentStatus }
        )
        try vm.record(candidate: CertCandidate(
            grader: .PSA, certNumber: "70000007",
            confidence: 0.9, rawText: "PSA 70000007"
        ))
        let lotId = lot.id
        let scan = try #require(try context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        ).first)
        try await Self.waitFor {
            Self.fetchScan(context, id: scan.id)?.validationFailureReason == "transient"
        }

        // Network was hit once for the initial scan.
        #expect(MockURLProtocol.capturedRequests.count == 1)

        // Simulate going offline before the user taps retry.
        currentStatus = .offline
        vm.retryValidation(scan: scan)

        // The retry should record a transient failure synchronously (no
        // network call), with the canonical offline message.
        let after = try #require(Self.fetchScan(context, id: scan.id))
        #expect(after.validationFailureReason == "transient")
        #expect(after.validationFailureMessage == "Offline — will retry when connected")
        // Still exactly one network request — the retry skipped the wire.
        #expect(MockURLProtocol.capturedRequests.count == 1)
    }

    // MARK: - P1.3: retryValidation guards against non-transient states

    /// Called against `.validated` → no-op. Pre-guard this would wipe
    /// identity metadata and re-fire PSA.
    @Test("retryValidation against validated scan is a no-op")
    func retryGuardsAgainstValidated() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://example.test/functions/v1/cert-lookup")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (resp, Self.successResponseJSON.data(using: .utf8)!)
        }
        let (vm, lot, context, _) = try Self.bootstrap()
        try vm.record(candidate: CertCandidate(
            grader: .PSA, certNumber: "80000008",
            confidence: 0.9, rawText: "PSA 80000008"
        ))
        let lotId = lot.id
        let scan = try #require(try context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        ).first)
        try await Self.waitFor {
            Self.fetchScan(context, id: scan.id)?.status == .validated
        }
        let identityBefore = scan.gradedCardIdentityId
        let requestsBefore = MockURLProtocol.capturedRequests.count

        vm.retryValidation(scan: scan)

        // Identity preserved, no new network request fired.
        let after = try #require(Self.fetchScan(context, id: scan.id))
        #expect(after.gradedCardIdentityId == identityBefore)
        #expect(after.status == .validated)
        #expect(MockURLProtocol.capturedRequests.count == requestsBefore)
    }

    /// Called against `.validationFailed` with `not_found` → no-op. The
    /// recourse for that state is delete-and-rescan, not retry. Pre-guard
    /// the method would have cleared the reason and re-fired the lookup
    /// just to land on the same `not_found` outcome.
    @Test("retryValidation against not_found terminal is a no-op")
    func retryGuardsAgainstNotFound() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://example.test/functions/v1/cert-lookup")!,
                statusCode: 404, httpVersion: nil, headerFields: nil
            )!
            return (resp, #"{"code":"CERT_NOT_FOUND"}"#.data(using: .utf8)!)
        }
        let (vm, lot, context, _) = try Self.bootstrap()
        try vm.record(candidate: CertCandidate(
            grader: .PSA, certNumber: "90000009",
            confidence: 0.9, rawText: "PSA 90000009"
        ))
        let lotId = lot.id
        let scan = try #require(try context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        ).first)
        try await Self.waitFor {
            Self.fetchScan(context, id: scan.id)?.validationFailureReason == "not_found"
        }
        let requestsBefore = MockURLProtocol.capturedRequests.count

        vm.retryValidation(scan: scan)

        let after = try #require(Self.fetchScan(context, id: scan.id))
        #expect(after.validationFailureReason == "not_found")
        #expect(after.status == .validationFailed)
        #expect(MockURLProtocol.capturedRequests.count == requestsBefore)
    }

    // MARK: - P1.4: real Task.cancel() mid-lookup produces clean copy

    /// Stubs a lookup that sleeps long enough for the test to call
    /// `Task.cancel()` mid-flight. The cancellation must surface as a
    /// transient failure with the canonical "Cancelled before PSA
    /// responded" message — not a junky `URLError -999` localized
    /// description.
    @Test("Task.cancel() mid-lookup → clean transient with cancellation copy")
    func cancellationMidFlight() async throws {
        MockURLProtocol.reset()
        // Hold a continuation that the test resolves AFTER calling
        // `Task.cancel()`. URLSession honours cancellation on its own
        // task; we just need a long-enough window for the cancel to
        // win the race.
        MockURLProtocol.requestHandler = { _ in
            // Sleep on the URLProtocol worker — URLSession will deliver
            // `URLError(.cancelled)` to the awaiter when the parent task
            // is cancelled. 2s is plenty for the test to fire cancel().
            Thread.sleep(forTimeInterval: 2.0)
            let resp = HTTPURLResponse(
                url: URL(string: "https://example.test/functions/v1/cert-lookup")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (resp, Self.successResponseJSON.data(using: .utf8)!)
        }
        // Build a bootstrap exposing the urlSession so we can target it.
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let userId = UUID()
        let storeId = UUID()
        let lot = Lot(
            id: UUID(), storeId: storeId, createdByUserId: userId,
            name: "Test", createdAt: Date(), updatedAt: Date()
        )
        context.insert(lot)
        try context.save()
        let session = MockURLProtocol.session()
        let repo = CertLookupRepository(
            urlSession: session,
            baseURL: URL(string: "https://example.test/functions/v1")!,
            authTokenProvider: { nil }
        )
        let vm = BulkScanViewModel(
            context: context,
            kicker: OutboxKicker { },
            lot: lot,
            currentUserId: userId,
            compRepository: nil,
            certLookupRepository: repo,
            reachabilityStatus: nil
        )
        try vm.record(candidate: CertCandidate(
            grader: .PSA, certNumber: "11111110",
            confidence: 0.9, rawText: "PSA 11111110"
        ))
        let lotId = lot.id
        let scanId = try #require(try context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        ).first?.id)

        // Cancel every URLSession task on the mock — this is the lever
        // that flips the in-flight `await urlSession.data(for:)` into a
        // `URLError(.cancelled)` throw. Wait a tick first so the request
        // is actually in-flight.
        try await Task.sleep(nanoseconds: 50_000_000)
        session.getAllTasks { tasks in
            for task in tasks { task.cancel() }
        }

        try await Self.waitFor {
            Self.fetchScan(context, id: scanId)?.validationFailureReason == "transient"
        }

        let final = try #require(Self.fetchScan(context, id: scanId))
        #expect(final.status == .pendingValidation)
        #expect(final.validationFailureReason == "transient")
        // The whole point of P1.4: this string MUST be the curated one,
        // not the URLError(-999) localized description.
        #expect(final.validationFailureMessage == "Cancelled before PSA responded")
    }
}

// MARK: - Atomic counter helper

/// Cheap thread-safe int for sequencing handler calls. The MockURLProtocol
/// handler runs on a URLSession-owned thread; the test reads from MainActor.
final class AtomicInt: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
