import Foundation
import Observation

/// Cross-tab navigation state for the root shell. The `TabView` in
/// `RootTabView` had no selection binding, so nothing outside it could
/// switch tabs. This router holds the selected tab and the Lots stack's
/// navigation path together so a surface in one tab (e.g. the bulk-scan
/// "Done" button) can deep-link into another tab.
///
/// `@Observable` so `SlabbistApp` injects it via `.environment(tabRouter)`
/// and views read it without a wrapper — same pattern as `OutboxKicker`.
@MainActor
@Observable
final class TabRouter {
    /// One case per top-level `Tab` in `RootTabView`. Used as the `TabView`
    /// selection value, so every `Tab` carries a matching `value:`.
    enum Tab: Hashable {
        case lots, scan, preGrade, movers, gradeGains
    }

    /// Currently selected tab. Bound to `RootTabView`'s `TabView`.
    var selectedTab: Tab = .lots

    /// Navigation path for the Lots tab's stack. Owned here rather than as
    /// `LotsListView`-local `@State` so a cross-tab deep-link can pre-load
    /// the destination before the Lots tab is even on screen.
    var lotsPath: [LotsRoute] = []

    /// Finish scanning → land on the lot the user just built. Sets the Lots
    /// stack to the lot detail, then switches to the Lots tab so the user
    /// doesn't have to navigate there by hand.
    func openLot(_ lotId: UUID) {
        lotsPath = [.lot(lotId)]
        selectedTab = .lots
    }
}
