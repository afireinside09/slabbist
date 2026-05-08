import Foundation
import SwiftData

enum Grader: String, Codable, CaseIterable {
    case PSA, BGS, CGC, SGC, TAG
}

enum ScanStatus: String, Codable, CaseIterable {
    case pendingValidation = "pending_validation"
    case validated
    case validationFailed = "validation_failed"
    case manualEntry = "manual_entry"
}

/// Lifecycle of the eBay comp fetch for a validated scan. Persisted on
/// `Scan.compFetchState` so `ScanDetailView` can show meaningful UI
/// instead of an infinite "Fetching comps…" spinner when something
/// upstream goes wrong.
enum CompFetchState: String, Codable {
    case fetching                       // a request is in flight
    case resolved                       // snapshot persisted; UI shows comps
    case noData = "no_data"             // upstream returned 404 NO_MARKET_DATA
    case failed                         // 5xx, decoding error, network error
}

@Model
final class Scan {
    @Attribute(.unique) var id: UUID
    var storeId: UUID
    var lotId: UUID
    var userId: UUID
    var grader: Grader
    var certNumber: String
    var grade: String?
    // Populated by /cert-lookup in its own plan; enables /price-comp lookup.
    var gradedCardIdentityId: UUID?
    var status: ScanStatus
    var ocrRawText: String?
    var ocrConfidence: Double?
    var capturedPhotoURL: String?
    var offerCents: Int64?
    /// Lifecycle of the eBay comp fetch — drives `ScanDetailView`'s state
    /// machine (fetching / resolved / no_data / failed). `nil` means the
    /// fetch has never been attempted (cert-lookup hasn't validated this
    /// scan yet).
    var compFetchState: String?
    /// User-visible reason when `compFetchState == "failed"`. Cleared on
    /// every successful fetch.
    var compFetchError: String?
    /// Timestamp of the last fetch attempt. Used both for retry throttling
    /// and to display "Last checked …" on the failure UI.
    var compFetchedAt: Date?
    /// Source of truth for the comp-card hero number. Computed server-side
    /// (average of PPT + Poketrace when both succeed; single-source value
    /// otherwise). Mirrored locally so list views render without re-decoding
    /// the snapshots.
    var reconciledHeadlinePriceCents: Int64?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        storeId: UUID,
        lotId: UUID,
        userId: UUID,
        grader: Grader,
        certNumber: String,
        grade: String? = nil,
        gradedCardIdentityId: UUID? = nil,
        status: ScanStatus = .pendingValidation,
        ocrRawText: String? = nil,
        ocrConfidence: Double? = nil,
        capturedPhotoURL: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.storeId = storeId
        self.lotId = lotId
        self.userId = userId
        self.grader = grader
        self.certNumber = certNumber
        self.grade = grade
        self.gradedCardIdentityId = gradedCardIdentityId
        self.status = status
        self.ocrRawText = ocrRawText
        self.ocrConfidence = ocrConfidence
        self.capturedPhotoURL = capturedPhotoURL
        self.offerCents = nil
        self.compFetchState = nil
        self.compFetchError = nil
        self.compFetchedAt = nil
        self.reconciledHeadlinePriceCents = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
