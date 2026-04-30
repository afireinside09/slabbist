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
@MainActor
enum CompFetchService {
    /// Kicks off a fetch for the given scan. Fire-and-forget — state is
    /// observed via SwiftData `@Query` on `Scan` and `GradedMarketSnapshot`.
    /// No-ops if the scan hasn't been validated yet (`gradedCardIdentityId`
    /// or `grade` is nil).
    static func fetch(
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

        // Mark fetching synchronously so the UI flips off the spinner-only
        // state and into a clear "fetching" mode (same visible spinner but
        // distinguishable from "never started").
        scan.compFetchState = CompFetchState.fetching.rawValue
        scan.compFetchError = nil
        scan.compFetchedAt = Date()
        try? context.save()

        Task {
            do {
                let decoded = try await repository.fetchComp(
                    identityId: identityId,
                    gradingService: service,
                    grade: grade
                )
                await MainActor.run {
                    persistSnapshot(decoded: decoded, identityId: identityId, service: service, grade: grade, context: context)
                    if let target = fetchScan(scanId, in: context) {
                        target.compFetchState = CompFetchState.resolved.rawValue
                        target.compFetchError = nil
                        target.compFetchedAt = Date()
                        try? context.save()
                    }
                }
            } catch {
                let (state, message) = classify(error)
                AppLog.scans.error(
                    "comp fetch failed: \(message, privacy: .public) (state=\(state.rawValue, privacy: .public))"
                )
                await MainActor.run {
                    if let target = fetchScan(scanId, in: context) {
                        target.compFetchState = state.rawValue
                        target.compFetchError = message
                        target.compFetchedAt = Date()
                        try? context.save()
                    }
                }
            }
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
            case .httpStatus(let code):
                return (.failed, "Lookup failed (HTTP \(code)).")
            case .decoding(let detail):
                return (.failed, "Couldn't decode comp response: \(detail)")
            }
        }
        return (.failed, error.localizedDescription)
    }
}
