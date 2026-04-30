import Foundation
import SwiftData
import Observation
import OSLog

@MainActor
@Observable
final class BulkScanViewModel {
    private let context: ModelContext
    let lot: Lot
    let currentUserId: UUID
    var compRepository: CompRepository?
    var certLookupRepository: CertLookupRepository?

    private(set) var recentScans: [Scan] = []

    init(
        context: ModelContext,
        lot: Lot,
        currentUserId: UUID,
        compRepository: CompRepository? = nil,
        certLookupRepository: CertLookupRepository? = nil
    ) {
        self.context = context
        self.lot = lot
        self.currentUserId = currentUserId
        self.compRepository = compRepository
        self.certLookupRepository = certLookupRepository
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
        let encoded = try JSONEncoder().encode(dto)

        let outboxItem = OutboxItem(
            id: UUID(),
            kind: .insertScan,
            payload: encoded,
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        )
        context.insert(outboxItem)

        try context.save()
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
        guard let lookup = self.certLookupRepository else { return }
        let scanId = scan.id
        let grader = scan.grader
        let certNumber = scan.certNumber
        let ctx = self.context

        Task { [weak self] in
            do {
                let result = try await lookup.lookup(grader: grader, certNumber: certNumber)
                await MainActor.run {
                    guard let self else { return }
                    var descriptor = FetchDescriptor<Scan>(
                        predicate: #Predicate<Scan> { $0.id == scanId }
                    )
                    descriptor.fetchLimit = 1
                    guard let target = try? ctx.fetch(descriptor).first else { return }

                    let now = Date()
                    target.gradedCardIdentityId = result.identityId
                    target.grade = result.grade
                    target.status = .validated
                    target.updatedAt = now

                    let patch = OutboxPayloads.UpdateScan(
                        id: target.id.uuidString,
                        graded_card_identity_id: result.identityId.uuidString,
                        grade: result.grade,
                        status: ScanStatus.validated.rawValue,
                        updated_at: ISO8601DateFormatter.shared.string(from: now)
                    )
                    if let payload = try? JSONEncoder().encode(patch) {
                        let outboxItem = OutboxItem(
                            id: UUID(),
                            kind: .updateScan,
                            payload: payload,
                            status: .pending,
                            attempts: 0,
                            createdAt: now,
                            nextAttemptAt: now
                        )
                        ctx.insert(outboxItem)
                    }
                    try? ctx.save()
                    self.refreshRecent()
                    self.triggerCompFetch(for: target)
                }
            } catch CertLookupRepository.Error.certNotFound {
                AppLog.scans.info("cert-lookup: cert not found upstream — leaving scan pending")
                await MainActor.run { self?.markValidationFailed(scanId: scanId) }
            } catch CertLookupRepository.Error.notPokemon {
                AppLog.scans.info("cert-lookup: cert resolved to non-pokemon product — skipping comp")
                await MainActor.run { self?.markValidationFailed(scanId: scanId) }
            } catch {
                // Transient errors (network, upstream unavailable, rate limit)
                // leave the scan in `pendingValidation` so a retry path remains
                // open. The outbox worker will eventually pick up retries when
                // a `certLookupJob` outbox kind is wired (see OutboxKind).
                AppLog.scans.error("cert-lookup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func markValidationFailed(scanId: UUID) {
        var descriptor = FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let target = try? context.fetch(descriptor).first else { return }
        target.status = .validationFailed
        target.updatedAt = Date()
        try? context.save()
        refreshRecent()
    }

    /// Fetches a live price-comp for a validated scan and persists a
    /// `GradedMarketSnapshot` (with listings) into the local SwiftData store
    /// so `ScanDetailView`'s `@Query` picks it up. No-ops unless the scan has
    /// been resolved to a `GradedCardIdentity` and a grade (wired by the
    /// separate /cert-lookup plan).
    func triggerCompFetch(for scan: Scan) {
        guard let identityId = scan.gradedCardIdentityId,
              let grade = scan.grade,
              let compRepo = self.compRepository else { return }
        let service = scan.grader.rawValue
        let ctx = self.context
        Task { [weak self] in
            guard self != nil else { return }
            do {
                let decoded = try await compRepo.fetchComp(
                    identityId: identityId,
                    gradingService: service,
                    grade: grade
                )
                await MainActor.run {
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
                    ctx.insert(snapshot)
                    try? ctx.save()
                }
            } catch {
                AppLog.scans.error("triggerCompFetch failed: \(error.localizedDescription, privacy: .public)")
                // UI stays on "Fetching…" state until a retry or outbox worker lands.
            }
        }
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
