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
    /// Timestamp of the last fetch attempt that produced a real answer
    /// (success, `noData`, or `failed`). Used to display "Last checked …"
    /// on the failure UI; **not** updated when a fetch starts so the UI
    /// doesn't lie about freshness while a request is still in flight.
    /// See `compFetchStartedAt` for the in-flight stamp.
    var compFetchedAt: Date?
    /// Timestamp of the most recent `CompFetchService.fetch` invocation.
    /// Separate from `compFetchedAt` so the user-visible "last refreshed"
    /// caption can't be set by a fetch that's still spinning. Anchors the
    /// stale-fetching detection (a `.fetching` state older than ~90s likely
    /// means the originating task was killed with the app and the UI is
    /// stuck on a ghost spinner — surface a Retry pill). Optional + no
    /// default so SwiftData lightweight migration leaves existing rows nil.
    var compFetchStartedAt: Date?
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
    /// Why the most recent `cert-lookup` attempt didn't yield a validated
    /// identity. One of: `"not_found"` (PSA has no record of the cert),
    /// `"not_pokemon"` (cert resolved to a non-Pokemon product), or
    /// `"transient"` (network / rate-limit / upstream 5xx — retry is the
    /// remedy). `nil` means lookup hasn't completed yet, or it succeeded.
    /// Optional with no init default keeps SwiftData lightweight migration
    /// happy for users on a prior schema.
    var validationFailureReason: String?
    /// Short human string captured at failure time — surfaced on the detail
    /// screen so the operator can see *what* PSA / the network said.
    /// e.g. "Offline — will retry when connected", or the raw
    /// `error.localizedDescription`. Cleared on retry kickoff.
    var validationFailureMessage: String?
    /// Timestamp of the last `cert-lookup` attempt. Drives the
    /// "Last attempt …" caption on the detail screen and the 10s "stale"
    /// gate that flips the queue row from "validating" into the retry pill.
    var validationLastAttemptAt: Date?
    /// Count of attempts the user has made to validate this scan. Increments
    /// on every transient failure (including the first one). Drives the
    /// "Retry (3)" copy after >=2 attempts and the "check your connection"
    /// detail-screen hint after >=3. Default 0 so SwiftData lightweight
    /// migration backfills existing rows.
    var validationAttemptCount: Int = 0
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
        self.compFetchStartedAt = nil
        self.reconciledHeadlinePriceCents = nil
        self.reconciledSource = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
