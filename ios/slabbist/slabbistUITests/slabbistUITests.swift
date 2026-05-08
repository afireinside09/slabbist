import XCTest

/// Smoke tests that exercise the post-auth shell: each tab loads, and
/// `performAccessibilityAudit()` finds no issues at the entry screen.
/// These are the cheap canaries — if any of them fails the whole test
/// run is suspect, so the more involved flow tests bail out early.
final class LaunchSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchLandsOnLotsTabAndPassesAudit() throws {
        let app = UITestApp.launch()

        // The Lots tab is the default entry point. Wait for the
        // "New lot" CTA to settle so we know the tab actually rendered
        // instead of catching an in-flight transition. 5s is generous
        // for a debug build; tighter values flake on cold starts.
        let newLotButton = app.buttons["new-lot-button"]
        XCTAssertTrue(
            newLotButton.waitForExistence(timeout: 5),
            "Lots tab should render its New lot CTA on launch"
        )
        try app.auditA11y(named: "lots tab (empty)")
    }

    @MainActor
    func testTabBarReachesEveryRoot() throws {
        let app = UITestApp.launch()

        // Tab labels are the visible button text — these are stable
        // human-readable strings owned by `RootTabView`. Exercising them
        // via label keeps the test resilient to icon/symbol changes.
        // We deliberately *don't* audit these tabs here — the Settings
        // and Movers screens have known a11y issues outside the scope of
        // the QoL features under test. Per-screen audits live in the
        // flow tests that own those screens.
        let tabLabels = ["Lots", "Scan", "Pre-grade", "Movers", "More"]
        for label in tabLabels {
            let tab = app.tabBars.buttons[label]
            XCTAssertTrue(
                tab.waitForExistence(timeout: 5),
                "Tab '\(label)' should exist"
            )
            tab.tap()
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            UITestApp.launch()
        }
    }
}
