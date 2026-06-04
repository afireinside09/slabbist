import Foundation
import SwiftData
import Observation
import OSLog

@MainActor
@Observable
final class BulkScanViewModel {
    private let context: ModelContext
    private let kicker: OutboxKicker
    let lot: Lot
    let currentUserId: UUID
    var compRepository: CompRepository?
    var certLookupRepository: CertLookupRepository?

    /// Reachability probe. The VM only needs the current status at the
    /// instant we're about to fire a cert-lookup — injected as a closure
    /// so tests can simulate `.offline` without spinning up `NWPathMonitor`.
    /// `nil` (the default) means "no check" and the network call proceeds
    /// normally, matching pre-C1 behavior.
    @ObservationIgnored
    private let reachabilityStatus: (@MainActor () -> ReachabilityStatus)?

    /// One-shot UI hook for the cert-lookup pipeline. Set by the bulk-scan
    /// view so the camera overlay can surface "looking up…" / "found" /
    /// "failed" feedback. The default no-op keeps tests insulated from the
    /// view layer.
    @ObservationIgnored
    var onLookupEvent: (LookupEvent) -> Void = { _ in }

    private(set) var recentScans: [Scan] = []

    init(
        context: ModelContext,
        kicker: OutboxKicker,
        lot: Lot,
        currentUserId: UUID,
        compRepository: CompRepository? = nil,
        certLookupRepository: CertLookupRepository? = nil,
        reachabilityStatus: (@MainActor () -> ReachabilityStatus)? = nil
    ) {
        self.context = context
        self.kicker = kicker
        self.lot = lot
        self.currentUserId = currentUserId
        self.compRepository = compRepository
        self.certLookupRepository = certLookupRepository
        self.reachabilityStatus = reachabilityStatus
        refreshRecent()
    }

    func record(candidate: CertCandidate) throws {
        if try isDuplicateLocally(grader: candidate.grader, certNumber: candidate.certNumber) {
            AppLog.scans.info("duplicate cert in lot — ignoring capture")
            return
        }

        let now = Date()
        let scan = Scan(
            id: UUID(),
            storeId: lot.storeId,
            lotId: lot.id,
            userId: currentUserId,
            grader: candidate.grader,
            certNumber: candidate.certNumber,
            status: .pendingValidation,
            ocrRawText: candidate.rawText,
            ocrConfidence: candidate.confidence,
            createdAt: now,
            updatedAt: now
        )
        context.insert(scan)

        let dto = OutboxPayloads.InsertScan(
            id: scan.id.uuidString,
            store_id: scan.storeId.uuidString,
            lot_id: scan.lotId.uuidString,
            user_id: scan.userId.uuidString,
            grader: scan.grader.rawValue,
            cert_number: scan.certNumber,
            status: scan.status.rawValue,
            ocr_raw_text: scan.ocrRawText,
            ocr_confidence: scan.ocrConfidence,
            created_at: ISO8601DateFormatter.shared.string(from: scan.createdAt),
            updated_at: ISO8601DateFormatter.shared.string(from: scan.updatedAt)
        )
        context.insert(try OutboxItem.pending(.insertScan, dto, now: now))

        try context.save()
        kicker.kick()
        refreshRecent()

        triggerCertLookup(for: scan)
    }

    /// Resolves a freshly-recorded scan's `(grader, cert_number)` to a graded
    /// card identity + grade by calling the `cert-lookup` Edge Function.
    /// On success, mutates the scan in place (status, identity, grade),
    /// enqueues a server-side patch, and chains into `triggerCompFetch`.
    /// No-ops without a `certLookupRepository` (e.g. unit tests not exercising
    /// the network path) so existing tests remain side-effect free.
    func triggerCertLookup(for scan: Scan) {
        performCertLookup(scanId: scan.id, grader: scan.grader, certNumber: scan.certNumber)
    }

    /// Retries the cert lookup for a scan stuck on a transient failure. The
    /// pre-C1 path stranded the scan in `.pendingValidation` with no UI
    /// recourse; this is the user-facing escape hatch. Clears the failure
    /// reason / message (so the queue row flips back to "validating…"),
    /// stamps a fresh attempt timestamp, and re-enters the same code path
    /// `triggerCertLookup` uses. `validationAttemptCount` is intentionally
    /// preserved across retries so the queue pill and detail copy can
    /// surface the cumulative count.
    ///
    /// Guarded to `(.pendingValidation, "transient")` only (P1.3): retrying
    /// a `.validated` scan would wipe identity metadata and re-fire PSA;
    /// retrying a `not_found` / `not_pokemon` terminal would cost a round-
    /// trip to land on the same terminal result. Either is a bug — both
    /// paths are caller mistakes that we want to surface, not absorb.
    func retryValidation(scan: Scan) {
        guard scan.status == .pendingValidation,
              scan.validationFailureReason == "transient" else {
            AppLog.scans.warning(
                "retryValidation called against non-transient scan (status=\(scan.status.rawValue, privacy: .public) reason=\(scan.validationFailureReason ?? "nil", privacy: .public)) — ignoring"
            )
            return
        }
        let scanId = scan.id
        let grader = scan.grader
        let certNumber = scan.certNumber

        var descriptor = FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let target = try? context.fetch(descriptor).first else { return }
        target.validationFailureReason = nil
        target.validationFailureMessage = nil
        target.validationLastAttemptAt = Date()
        target.updatedAt = Date()
        try? context.save()
        refreshRecent()

        performCertLookup(scanId: scanId, grader: grader, certNumber: certNumber)
    }

    /// Inner driver shared by `triggerCertLookup` (initial scan) and
    /// `retryValidation` (user-tapped retry). Captures the scan identity
    /// via primitives so the `Task` doesn't retain a SwiftData model
    /// across the actor hop.
    private func performCertLookup(scanId: UUID, grader: Grader, certNumber: String) {
        guard let lookup = self.certLookupRepository else { return }
        let ctx = self.context

        // Emit `.started` synchronously so the UI flips to "Looking up…"
        // before the network request lands.
        self.onLookupEvent(.started(grader: grader, certNumber: certNumber))

        // Offline edge case: skip the network call entirely, mark the scan
        // as a transient failure with a clear "offline" message. The pill
        // stays tappable; the next retry from the queue re-enters this
        // path and produces the same result until the radio is back.
        if let reach = self.reachabilityStatus?(), reach == .offline {
            self.recordTransientFailure(
                scanId: scanId,
                message: "Offline — will retry when connected"
            )
            self.onLookupEvent(.failed(reason: "Offline"))
            return
        }

        let kicker = self.kicker
        Task { [weak self] in
            do {
                let result = try await lookup.lookup(grader: grader, certNumber: certNumber)
                // Surface task cancellation as a transient failure rather
                // than a silent skip — the user otherwise sees the scan
                // hang in `.pendingValidation` after backgrounding mid-flight.
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self else { return }
                    var descriptor = FetchDescriptor<Scan>(
                        predicate: #Predicate<Scan> { $0.id == scanId }
                    )
                    descriptor.fetchLimit = 1
                    guard let target = try? ctx.fetch(descriptor).first else { return }

                    let now = Date()
                    Self.upsertIdentity(result: result, in: ctx)
                    target.gradedCardIdentityId = result.identityId
                    target.grade = result.grade
                    target.status = .validated
                    target.validationFailureReason = nil
                    target.validationFailureMessage = nil
                    target.validationLastAttemptAt = now
                    // Reset the attempt counter on success — if this scan ever
                    // re-enters validation (e.g. a future refresh / re-scan path),
                    // the "we've tried N times" hint and queue pill copy must
                    // start from a clean slate. Carrying old history into a new
                    // fault produces wrong counts (P0.1).
                    target.validationAttemptCount = 0
                    target.updatedAt = now

                    let patch = OutboxPayloads.UpdateScan(
                        id: target.id.uuidString,
                        graded_card_identity_id: result.identityId.uuidString,
                        grade: result.grade,
                        status: ScanStatus.validated.rawValue,
                        updated_at: ISO8601DateFormatter.shared.string(from: now)
                    )
                    // Encode + enqueue + save as one unit. Previously the
                    // enqueue was gated on a swallowed `try?` while the save
                    // ran unconditionally, so an encode failure persisted the
                    // validated grade locally but never queued the server
                    // patch — silent local/server divergence with no retry.
                    // Fail loud instead: if we can't queue the sync, don't
                    // half-persist a grade that will never reach the server.
                    do {
                        ctx.insert(try OutboxItem.pending(.updateScan, patch, now: now))
                        try ctx.save()
                    } catch {
                        AppLog.scans.error("cert-lookup: failed to persist validated-scan patch for \(target.id, privacy: .public): \(String(describing: error), privacy: .public) — grade not synced")
                    }
                    kicker.kick()
                    self.refreshRecent()
                    self.triggerCompFetch(for: target)
                    self.onLookupEvent(.resolved(productLabel: Self.productLabel(from: result)))
                }
            } catch CertLookupRepository.Error.certNotFound {
                AppLog.scans.info("cert-lookup: cert not found upstream — leaving scan pending")
                await MainActor.run {
                    self?.markValidationFailed(scanId: scanId, reason: "not_found")
                    self?.onLookupEvent(.failed(reason: "Cert not found"))
                }
            } catch CertLookupRepository.Error.notPokemon {
                AppLog.scans.info("cert-lookup: cert resolved to non-pokemon product — skipping comp")
                await MainActor.run {
                    self?.markValidationFailed(scanId: scanId, reason: "not_pokemon")
                    self?.onLookupEvent(.failed(reason: "Not a Pokémon slab"))
                }
            } catch is CancellationError {
                // Task was cancelled AFTER the network call returned — caught
                // by the explicit `try Task.checkCancellation()` above.
                AppLog.scans.info("cert-lookup: cancelled post-response — recording as transient")
                await MainActor.run {
                    self?.recordTransientFailure(
                        scanId: scanId,
                        message: "Cancelled before PSA responded"
                    )
                    self?.onLookupEvent(.failed(reason: "Lookup cancelled"))
                }
            } catch let urlError as URLError where urlError.code == .cancelled {
                // The much more common cancellation surface: `URLSession`
                // throws `URLError(.cancelled)` from the await itself when
                // the parent `Task` is cancelled mid-flight. Without this
                // specific catch, the user sees junk copy like "The operation
                // couldn't be completed. NSURLErrorDomain error -999."
                AppLog.scans.info("cert-lookup: URLSession cancelled mid-flight — recording as transient")
                await MainActor.run {
                    self?.recordTransientFailure(
                        scanId: scanId,
                        message: "Cancelled before PSA responded"
                    )
                    self?.onLookupEvent(.failed(reason: "Lookup cancelled"))
                }
            } catch {
                // Transient errors (network, upstream unavailable, rate limit)
                // leave the scan in `pendingValidation` so the retry pill in
                // the queue row + detail screen can re-enter this path.
                AppLog.scans.error("cert-lookup failed: \(error.localizedDescription, privacy: .public)")
                let message = error.localizedDescription
                await MainActor.run {
                    self?.recordTransientFailure(scanId: scanId, message: message)
                    self?.onLookupEvent(.failed(reason: "Lookup failed — check connection"))
                }
            }
        }
    }

    /// Persists the `cert-lookup` response's card metadata as a local
    /// `GradedCardIdentity` row so the lot detail screen and scan
    /// detail header can show the card name / set / variant
    /// immediately — without waiting for the eBay comp fetch (or
    /// silently losing the data when the green resolve banner
    /// auto-dismisses). Idempotent: a re-scan of the same identity
    /// finds the existing row and skips the insert.
    static func upsertIdentity(
        result: CertLookupRepository.Decoded,
        in ctx: ModelContext
    ) {
        let identityId = result.identityId
        var descriptor = FetchDescriptor<GradedCardIdentity>(
            predicate: #Predicate<GradedCardIdentity> { $0.id == identityId }
        )
        descriptor.fetchLimit = 1
        if (try? ctx.fetch(descriptor).first) != nil { return }
        ctx.insert(GradedCardIdentity(
            id: result.identityId,
            game: "pokemon",
            language: result.language,
            setName: result.setName,
            cardNumber: result.cardNumber,
            cardName: result.cardName,
            variant: result.variant,
            year: result.year
        ))
    }

    /// Builds a human-friendly one-liner for the status pill from a
    /// `cert-lookup` response. Examples:
    ///   "CHARIZARD-HOLO #4 — PSA 10"
    ///   "MEWTWO V — PSA 9"
    /// Card-name only (no set) so the line fits a single capsule. Year and
    /// set are still in the queue row + detail screen.
    static func productLabel(from result: CertLookupRepository.Decoded) -> String {
        var pieces: [String] = [result.cardName]
        if let n = result.cardNumber, !n.isEmpty {
            pieces.append("#\(n)")
        }
        let head = pieces.joined(separator: " ")
        return "\(head) — \(result.gradingService) \(result.grade)"
    }

    /// Records a terminal validation failure (`not_found` or `not_pokemon`) —
    /// the cert genuinely can't be validated, so we flip `.status` to
    /// `.validationFailed` and stamp the reason for `ScanDetailView` to fork
    /// its empty state on. Unlike transient failures, these don't show a
    /// retry pill; the recourse is delete-and-rescan or set-manual-price.
    ///
    /// Queues an `updateScan` outbox patch so the dashboard sees the same
    /// status transition. The `validationFailureReason` field is local-only
    /// — the server doesn't carry a column for it yet, so we don't widen
    /// the wire shape (would be a no-op patch server-side).
    private func markValidationFailed(scanId: UUID, reason: String) {
        var descriptor = FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let target = try? context.fetch(descriptor).first else { return }
        let now = Date()
        target.status = .validationFailed
        target.validationFailureReason = reason
        target.validationLastAttemptAt = now
        target.updatedAt = now

        let patch = OutboxPayloads.UpdateScan(
            id: target.id.uuidString,
            graded_card_identity_id: nil,
            grade: nil,
            status: ScanStatus.validationFailed.rawValue,
            updated_at: ISO8601DateFormatter.shared.string(from: now)
        )
        // Fail loud rather than silently skipping the enqueue on an encode
        // failure (the old `if let try?` + unconditional save) — see the
        // matching note on the validated-scan path.
        do {
            context.insert(try OutboxItem.pending(.updateScan, patch, now: now))
            try context.save()
        } catch {
            AppLog.scans.error("markValidationFailed: failed to persist scan patch for \(target.id, privacy: .public): \(String(describing: error), privacy: .public) — status not synced")
        }
        kicker.kick()
        refreshRecent()
    }

    /// Records a transient cert-lookup failure (network / 5xx / rate limit /
    /// cancellation / offline). Critically: `.status` stays at
    /// `.pendingValidation` so the scan reads as "retryable" rather than
    /// "failed", and the queue row's retry pill is enabled by the
    /// presence of `validationFailureReason == "transient"`. The attempt
    /// counter increments on every transient pass so the pill copy can
    /// surface the cumulative count.
    ///
    /// **No outbox patch.** Unlike `markValidationFailed`, this function
    /// does NOT enqueue an `updateScan` payload. The server-side `status`
    /// hasn't changed (still `pending_validation`), and the
    /// `validationFailureReason` / `validationFailureMessage` /
    /// `validationAttemptCount` fields are local-only — there are no
    /// matching columns in `scans` yet. Adding an outbox patch here would
    /// spam the server with no-op `status: "pending_validation"` writes.
    /// If/when those columns land server-side, widen
    /// `OutboxPayloads.UpdateScan` first, then enqueue from here.
    private func recordTransientFailure(scanId: UUID, message: String) {
        var descriptor = FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let target = try? context.fetch(descriptor).first else { return }
        let now = Date()
        target.validationFailureReason = "transient"
        target.validationFailureMessage = message
        target.validationLastAttemptAt = now
        target.validationAttemptCount += 1
        target.updatedAt = now
        try? context.save()
        refreshRecent()
    }

    /// Kicks off the eBay comp fetch for a validated scan. State transitions
    /// (fetching / resolved / no_data / failed) are recorded on the scan by
    /// `CompFetchService` so the detail view can show meaningful UI.
    func triggerCompFetch(for scan: Scan) {
        guard let compRepo = self.compRepository else {
            AppLog.scans.info("comp fetch skipped — no compRepository injected")
            return
        }
        CompFetchService.fetch(scan: scan, repository: compRepo, context: self.context, kicker: self.kicker)
    }

    /// SwiftData's `#Predicate` macro can't capture enum values (same quirk as
    /// T23's `status == .open`). Fetch by `lotId` + `certNumber` (both non-enum),
    /// then filter the grader in memory. Bounded by certNumber uniqueness within
    /// a lot so the result set stays tiny.
    private func isDuplicateLocally(grader: Grader, certNumber: String) throws -> Bool {
        let lotId = lot.id
        let cert = certNumber
        var descriptor = FetchDescriptor<Scan>(
            predicate: #Predicate<Scan> {
                $0.lotId == lotId && $0.certNumber == cert
            }
        )
        descriptor.fetchLimit = 5
        let rows = try context.fetch(descriptor)
        return rows.contains { $0.grader == grader }
    }

    private func refreshRecent() {
        let lotId = lot.id
        var descriptor = FetchDescriptor<Scan>(
            predicate: #Predicate<Scan> { $0.lotId == lotId },
            sortBy: [SortDescriptor(\Scan.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        do {
            recentScans = try context.fetch(descriptor)
        } catch {
            AppLog.scans.error("refreshRecent fetch failed: \(error.localizedDescription, privacy: .public)")
            recentScans = []
        }
    }
}
