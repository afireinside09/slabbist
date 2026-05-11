import XCTest

/// Convenience launchers for XCUITests. All UI tests should go through
/// `UITestApp.launch(...)` rather than constructing `XCUIApplication`
/// directly so the `--ui-tests` argument is consistently applied — the
/// app uses that flag to skip Supabase auth and use an in-memory
/// SwiftData store. Without it, the harness lands on the auth screen
/// and every assertion downstream times out.
enum UITestApp {
    /// Optional knobs for layering on top of the base UI test mode.
    /// Mirrors `UITestEnvironment.Flag` on the app side. Keep these
    /// raw values in sync with the app's enum — the app is the source
    /// of truth for what each flag means at runtime.
    enum Flag: String {
        case seedSampleLot = "--ui-tests-seed-sample-lot"
        case seedNoCompScan = "--ui-tests-seed-no-comp-scan"
        case seedPricedLot = "--ui-tests-seed-priced-lot"
    }

    /// Launch the app under test with `--ui-tests` plus any extra
    /// flags supplied by the caller. Returns the launched app for
    /// chaining queries.
    @discardableResult
    static func launch(_ flags: [Flag] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-tests")
        for flag in flags {
            app.launchArguments.append(flag.rawValue)
        }
        app.launch()
        return app
    }
}
