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

    private init() {}

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
                Self.persistSnapshot(decoded: decoded, identityId: identityId, service: service, grade: grade, context: context)
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

    private static func persistSnapshot(
        decoded: CompRepository.Decoded,
        identityId: UUID,
        service: String,
        grade: String,
        context: ModelContext
    ) {
        let snapshot = GradedMarketSnapshot(
            identityId: identityId,
            gradingService: service,
            grade: grade,
            blendedPriceCents: decoded.blendedPriceCents,
            meanPriceCents: decoded.meanPriceCents,
            trimmedMeanPriceCents: decoded.trimmedMeanPriceCents,
            medianPriceCents: decoded.medianPriceCents,
            lowPriceCents: decoded.lowPriceCents,
            highPriceCents: decoded.highPriceCents,
            confidence: decoded.confidence,
            sampleCount: decoded.sampleCount,
            sampleWindowDays: decoded.sampleWindowDays,
            velocity7d: decoded.velocity7d,
            velocity30d: decoded.velocity30d,
            velocity90d: decoded.velocity90d,
            fetchedAt: decoded.fetchedAt,
            cacheHit: decoded.cacheHit,
            isStaleFallback: decoded.isStaleFallback,
            soldListings: decoded.soldListings
        )
        context.insert(snapshot)
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
                return (.noData, "No eBay sales found for this slab yet.")
            case .upstreamUnavailable:
                return (.failed, "eBay lookup unavailable — check function logs and try again.")
            case .identityNotFound:
                return (.failed, "Card identity not on file — re-scan to refresh the cert.")
            case .notDeployed:
                return (.failed, "price-comp edge function isn't deployed. Run `supabase functions deploy price-comp`.")
            case .httpStatus(let code):
                return (.failed, "Lookup failed (HTTP \(code)).")
            case .decoding(let detail):
                return (.failed, "Couldn't decode comp response: \(detail)")
            }
        }
        return (.failed, error.localizedDescription)
    }
}
