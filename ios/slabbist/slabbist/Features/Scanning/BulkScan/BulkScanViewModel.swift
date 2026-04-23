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

    private(set) var recentScans: [Scan] = []

    init(context: ModelContext, lot: Lot, currentUserId: UUID) {
        self.context = context
        self.lot = lot
        self.currentUserId = currentUserId
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
        recentScans = (try? context.fetch(descriptor)) ?? []
    }
}
