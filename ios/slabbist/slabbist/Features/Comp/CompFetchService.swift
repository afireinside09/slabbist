import Foundation
import SwiftData
import OSLog

/// Single source of truth for fetching an eBay comp for a validated scan.
/// Records `Scan.compFetchState` at every transition so `ScanDetailView`
/// can render the right UI (progress / no-data / failed / resolved).
///
/// Used by both:
///   - `BulkScanViewModel.triggerCompFetch` (auto, after cert-lookup)
///   - `ScanDetailView`'s Retry button
///
/// Concurrent calls for the same `(identityId, gradingService, grade)` key
/// share one in-flight network request — N parallel scans of the same slab
/// produce one upstream call, not N. The shared task flips every Scan whose
/// `(identityId, grader, grade)` matches the key.
@MainActor
final class CompFetchService {
    static let shared = CompFetchService()

    /// In-flight fetches keyed by `(identityId|service|grade)`. New calls for
    /// an in-flight key are absorbed (the requesting scan is flipped to
    /// `.fetching` and will pick up the snapshot via `@Query` when the
    /// shared task lands).
    private var inFlight: [String: Task<Void, Never>] = [:]

    /// Test-friendly context, used by `persist(scan:decoded:)` when the
    /// service is constructed via `init(context:)`. The shared singleton
    /// passes the context per-call through `fetch(...)` instead.
    private let boundContext: ModelContext?

    private init() {
        self.boundContext = nil
    }

    /// Test seam: build a service bound to a specific `ModelContext` so
    /// `persist(scan:decoded:)` can be exercised in isolation without going
    /// through the live fetch pipeline.
    init(context: ModelContext) {
        self.boundContext = context
    }

    /// Test seam: reset all in-flight tracking. Production code never calls.
    func _resetForTests() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    /// Static entry point preserved for source compatibility with prior call
    /// sites; delegates to the shared instance.
    static func fetch(
        scan: Scan,
        repository: CompRepository,
        context: ModelContext
    ) {
        shared.fetch(scan: scan, repository: repository, context: context)
    }

    func fetch(
        scan: Scan,
        repository: CompRepository,
        context: ModelContext
    ) {
        guard let identityId = scan.gradedCardIdentityId,
              let grade = scan.grade else {
            AppLog.scans.info("comp fetch skipped — scan not validated yet")
            return
        }
        let scanId = scan.id
        let service = scan.grader.rawValue
        let key = Self.cacheKey(identityId: identityId, service: service, grade: grade)

        // Mark fetching so the UI flips off the spinner-only state into a
        // clear "fetching" mode. Done unconditionally — both the kicker and
        // the absorber paths set it so a freshly-arriving scan gets the same
        // visible state as the scan that originally triggered the fetch.
        scan.compFetchState = CompFetchState.fetching.rawValue
        scan.compFetchError = nil
        scan.compFetchedAt = Date()
        try? context.save()

        // Already a request in flight for this exact key — absorb. The shared
        // task will flip every matching scan when it lands.
        if inFlight[key] != nil {
            AppLog.scans.info("comp fetch absorbed into in-flight request for key=\(key, privacy: .public)")
            return
        }

        let task = Task { @MainActor [weak self] in
            defer { self?.inFlight[key] = nil }
            do {
                let decoded = try await repository.fetchComp(
                    identityId: identityId,
                    gradingService: service,
                    grade: grade
                )
                Self.persistSnapshots(
                    decoded: decoded,
                    identityId: identityId,
                    service: service,
                    grade: grade,
                    scanId: scanId,
                    context: context
                )
                Self.flipMatching(
                    identityId: identityId,
                    service: service,
                    grade: grade,
                    to: .resolved,
                    error: nil,
                    context: context
                )
                // Belt-and-braces: ensure the originating scan is also flipped
                // even if it slipped out of the fetch above (e.g. deleted then
                // re-inserted with the same id during the network window).
                if let target = Self.fetchScan(scanId, in: context) {
                    target.compFetchState = CompFetchState.resolved.rawValue
                    target.compFetchError = nil
                    target.compFetchedAt = Date()
                    try? context.save()
                }
            } catch {
                let (state, message) = Self.classify(error)
                AppLog.scans.error(
                    "comp fetch failed: \(message, privacy: .public) (state=\(state.rawValue, privacy: .public))"
                )
                Self.flipMatching(
                    identityId: identityId,
                    service: service,
                    grade: grade,
                    to: state,
                    error: message,
                    context: context
                )
                if let target = Self.fetchScan(scanId, in: context) {
                    target.compFetchState = state.rawValue
                    target.compFetchError = message
                    target.compFetchedAt = Date()
                    try? context.save()
                }
            }
        }
        inFlight[key] = task
    }

    private static func cacheKey(identityId: UUID, service: String, grade: String) -> String {
        "\(identityId.uuidString)|\(service)|\(grade)"
    }

    /// Flip every `Scan` whose `(identityId, grader, grade)` matches the
    /// completed fetch — keeps absorbed requests in sync with the original.
    private static func flipMatching(
        identityId: UUID,
        service: String,
        grade: String,
        to state: CompFetchState,
        error: String?,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<Scan>(
            predicate: #Predicate<Scan> { s in
                s.gradedCardIdentityId == identityId &&
                s.grade == grade
            }
        )
        guard let candidates = try? context.fetch(descriptor) else { return }
        let now = Date()
        var changed = false
        for s in candidates where s.grader.rawValue == service {
            s.compFetchState = state.rawValue
            s.compFetchError = error
            s.compFetchedAt = now
            changed = true
        }
        if changed {
            try? context.save()
        }
    }

    /// Test entry point: persist both PPT and (if present) Poketrace
    /// snapshots for `scan` from a fully-decoded envelope, and mirror the
    /// reconciled headline back to the scan. Uses the context bound at
    /// `init(context:)` time.
    func persist(scan: Scan, decoded: CompRepository.Decoded) async throws {
        guard let context = boundContext else {
            preconditionFailure("CompFetchService.persist requires a context-bound init")
        }
        guard let identityId = scan.gradedCardIdentityId else {
            preconditionFailure("CompFetchService.persist requires a validated scan with gradedCardIdentityId")
        }
        Self.persistSnapshots(
            decoded: decoded,
            identityId: identityId,
            service: decoded.gradingService,
            grade: decoded.grade,
            scanId: scan.id,
            context: context
        )
        // `persistSnapshots` writes `reconciledHeadlinePriceCents` onto every
        // matching scan via the predicate; ensure the in-memory `scan` arg
        // (which may not be the same object identity as the fetched row in
        // some test contexts) reflects it too.
        scan.reconciledHeadlinePriceCents = decoded.reconciledHeadlineCents
        try context.save()
    }

    /// Drops any prior snapshots for `(identityId, service, grade)` regardless
    /// of source, then inserts one PPT row and (when `decoded.poketrace` is
    /// present) a second Poketrace row. Mirrors the reconciled headline onto
    /// the originating scan so list views can render without re-decoding the
    /// snapshot rows.
    private static func persistSnapshots(
        decoded: CompRepository.Decoded,
        identityId: UUID,
        service: String,
        grade: String,
        scanId: UUID,
        context: ModelContext
    ) {
        // Drop existing rows for this slab — both sources — so a refetch
        // doesn't pile up duplicates.
        let existingDescriptor = FetchDescriptor<GradedMarketSnapshot>(
            predicate: #Predicate<GradedMarketSnapshot> { s in
                s.identityId == identityId &&
                s.gradingService == service &&
                s.grade == grade
            }
        )
        if let existing = try? context.fetch(existingDescriptor) {
            for s in existing { context.delete(s) }
        }

        let pptHistoryJSON = encodePriceHistory(decoded.priceHistory)
        let ppt = GradedMarketSnapshot(
            identityId: identityId,
            gradingService: service,
            grade: grade,
            source: GradedMarketSnapshot.sourcePPT,
            headlinePriceCents: decoded.headlinePriceCents,
            loosePriceCents: decoded.loosePriceCents,
            psa7PriceCents: decoded.psa7PriceCents,
            psa8PriceCents: decoded.psa8PriceCents,
            psa9PriceCents: decoded.psa9PriceCents,
            psa9_5PriceCents: decoded.psa9_5PriceCents,
            psa10PriceCents: decoded.psa10PriceCents,
            bgs10PriceCents: decoded.bgs10PriceCents,
            cgc10PriceCents: decoded.cgc10PriceCents,
            sgc10PriceCents: decoded.sgc10PriceCents,
            pptTCGPlayerId: decoded.pptTCGPlayerId,
            pptURL: decoded.pptURL,
            priceHistoryJSON: pptHistoryJSON,
            fetchedAt: decoded.fetchedAt,
            cacheHit: decoded.cacheHit,
            isStaleFallback: decoded.isStaleFallback
        )
        context.insert(ppt)

        if let pt = decoded.poketrace {
            let ptHistoryJSON = encodePriceHistory(pt.priceHistory)
            let snapshot = GradedMarketSnapshot(
                identityId: identityId,
                gradingService: service,
                grade: grade,
                source: GradedMarketSnapshot.sourcePoketrace,
                headlinePriceCents: pt.avgCents,
                ptAvgCents: pt.avgCents,
                ptLowCents: pt.lowCents,
                ptHighCents: pt.highCents,
                ptAvg1dCents: pt.avg1dCents,
                ptAvg7dCents: pt.avg7dCents,
                ptAvg30dCents: pt.avg30dCents,
                ptMedian3dCents: pt.median3dCents,
                ptMedian7dCents: pt.median7dCents,
                ptMedian30dCents: pt.median30dCents,
                ptTrend: pt.trend,
                ptConfidence: pt.confidence,
                ptSaleCount: pt.saleCount,
                poketraceCardId: pt.cardId,
                priceHistoryJSON: ptHistoryJSON,
                fetchedAt: pt.fetchedAt,
                cacheHit: decoded.cacheHit,
                isStaleFallback: decoded.isStaleFallback
            )
            context.insert(snapshot)
        }

        // Mirror the reconciled headline onto the originating scan. The
        // `flipMatching` call site below also touches `compFetch*`, but the
        // hero number lives independently so we update it here next to the
        // snapshot writes that produced it.
        if let target = fetchScan(scanId, in: context) {
            target.reconciledHeadlinePriceCents = decoded.reconciledHeadlineCents
        }
    }

    /// Encodes a `[PriceHistoryPoint]` array as the JSON blob persisted on
    /// `GradedMarketSnapshot.priceHistoryJSON`. Returns `nil` for an empty
    /// list so consumers can short-circuit on `priceHistoryJSON == nil`.
    private static func encodePriceHistory(_ points: [PriceHistoryPoint]) -> String? {
        guard !points.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(points) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func fetchScan(_ id: UUID, in context: ModelContext) -> Scan? {
        var descriptor = FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Maps a `CompRepository.Error` to a persisted state + a user-facing
    /// one-liner. The wording prioritizes "what can the user do" over
    /// faithful technical detail (those land in Console.app).
    nonisolated static func classify(_ error: Error) -> (state: CompFetchState, message: String) {
        if let typed = error as? CompRepository.Error {
            switch typed {
            case .noMarketData:
                return (.noData, "Pokemon Price Tracker has no comp for this slab yet.")
            case .productNotResolved:
                return (.noData, "We couldn't find this card on Pokemon Price Tracker.")
            case .upstreamUnavailable:
                return (.failed, "Pokemon Price Tracker lookup unavailable — try again.")
            case .identityNotFound:
                return (.failed, "Card identity not on file — re-scan to refresh the cert.")
            case .authInvalid:
                return (.failed, "Comp lookup misconfigured — contact support.")
            case .httpStatus(let code):
                return (.failed, "Lookup failed (HTTP \(code)).")
            case .decoding(let detail):
                return (.failed, "Couldn't decode comp response: \(detail)")
            }
        }
        return (.failed, error.localizedDescription)
    }
}
