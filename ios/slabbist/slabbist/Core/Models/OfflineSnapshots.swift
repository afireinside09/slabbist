import Foundation
import SwiftData

/// Last-known-good cache for the Movers (movers-mode) screen.
///
/// Movers and Grade Gains are network-read "browse trends" screens. Unlike
/// the offline-first scan/comp/offer flow they have no SwiftData of their
/// own, so a dropped connection used to leave them blank. We persist ONLY
/// the most recent successful result per screen (not every set/tier combo):
/// when the live fetch fails or the device is offline, the screen falls back
/// to this row and labels it "as of <time>" so the operator on a flaky
/// shop-floor connection still sees the last data they pulled.
///
/// Single row, keyed on a fixed `id`. `payload` is JSON-encoded rows; the
/// view models own the encode/decode so this model stays a dumb container.
@Model
final class MoverSnapshot {
    @Attribute(.unique) var id: String
    var payload: Data
    /// Human-readable description of the filter the rows belong to
    /// ("English · Base Set · Under $5"), shown in the stale banner since
    /// the cached rows may not match the picker's current selection offline.
    var contextLabel: String
    var fetchedAt: Date

    /// Fixed key — only the latest movers-mode result is kept.
    static let singletonID = "movers"

    init(id: String = MoverSnapshot.singletonID, payload: Data, contextLabel: String, fetchedAt: Date) {
        self.id = id
        self.payload = payload
        self.contextLabel = contextLabel
        self.fetchedAt = fetchedAt
    }
}

/// Last-known-good cache for the Grade Gains screen. See `MoverSnapshot`.
@Model
final class GradeGainSnapshot {
    @Attribute(.unique) var id: String
    var payload: Data
    var contextLabel: String
    var fetchedAt: Date

    static let singletonID = "gradeGains"

    init(id: String = GradeGainSnapshot.singletonID, payload: Data, contextLabel: String, fetchedAt: Date) {
        self.id = id
        self.payload = payload
        self.contextLabel = contextLabel
        self.fetchedAt = fetchedAt
    }
}
