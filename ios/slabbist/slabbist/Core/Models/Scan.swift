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
    /// Manual asking price the vendor set for this slab when Pokemon Price
    /// Tracker had no comp (or the user wanted to override it). Renamed from
    /// `offerCents` to disambiguate it from the lot-level offer total: this
    /// is the "vendor ask" — what the seller wants for the card. Mirrors
    /// `scans.vendor_ask_cents` server-side.
    var vendorAskCents: Int64?
    /// Per-slab buy price the store will pay this vendor for the card. Derived
    /// from the headline comp times the store's margin rule, unless
    /// `buyPriceOverridden` is `true` — then the user typed it in directly.
    /// Mirrors `scans.buy_price_cents` server-side.
    var buyPriceCents: Int64?
    /// `true` when the user has manually overridden the derived `buyPriceCents`.
    /// Drives whether the comp recompute path is allowed to recalculate the
    /// value: an overridden buy price sticks until the user clears it.
    var buyPriceOverridden: Bool
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
    /// Which provider (or rule) produced `reconciledHeadlinePriceCents`.
    /// One of: "avg" | "ppt-only" | "poketrace-only" | "poketrace-preferred".
    /// Drives the caption under the comp-card hero. Optional + no default
    /// → SwiftData lightweight migration leaves existing rows nil and the
    /// CompCardView falls back to inferring from snapshot presence.
    var reconciledSource: String?
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
        self.vendorAskCents = nil
        self.buyPriceCents = nil
        self.buyPriceOverridden = false
        self.compFetchState = nil
        self.compFetchError = nil
        self.compFetchedAt = nil
        self.reconciledHeadlinePriceCents = nil
        self.reconciledSource = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
