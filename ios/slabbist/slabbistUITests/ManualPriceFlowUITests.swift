import XCTest

/// End-to-end coverage of the QoL flows. Each test boots the app under
/// `--ui-tests`, which:
///   * Skips Supabase auth (no network round-trip).
///   * Switches to an in-memory SwiftData container so each launch
///     starts empty.
///   * Pre-creates a synthetic Store + signed-in user.
///
/// Tests assert on accessibility identifiers (set in the app views) so
/// a future visual redesign that keeps the same semantic surface area
/// still passes. `auditA11y(named:)` catches the visual class of
/// regressions (contrast, hit targets, missing labels) automatically.
final class ManualPriceFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Lot creation → inline lot delete. We exercise the create flow
    /// from the Lots tab (which auto-navigates into LotDetailView for
    /// the new lot) and then the inline-delete strip on the Lots list.
    /// We do not exercise scanning here — the camera path needs a real
    /// device, and the manual-price half is covered by the seeded
    /// `testSetManualPriceOnNoCompScan` flow.
    @MainActor
    func testCreateLotAndDeleteLotInline() throws {
        let app = UITestApp.launch()

        // 1. Lots tab loads with an empty list.
        let newLotButton = app.buttons["new-lot-button"]
        XCTAssertTrue(
            newLotButton.waitForExistence(timeout: 5),
            "Lots tab should expose the New lot CTA"
        )
        try app.auditA11y(named: "lots tab (empty)")

        // 2. Create a lot via NewLotSheet. The sheet pre-fills a
        // `Bulk – <date>` name; we accept the default so the test
        // doesn't have to fight the keyboard for a deterministic name
        // — we navigate by row prefix below instead.
        newLotButton.tap()

        let nameField = app.textFields["new-lot-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        try app.auditA11y(named: "new lot sheet")

        app.buttons["new-lot-create-button"].tap()

        // 3. Creating a lot from this entry point auto-navigates into
        // LotDetailView for the new lot. Confirm we're there by
        // looking for the empty-state hint that LotDetailView renders
        // for a lot with zero scans.
        let emptyTitle = app.staticTexts["No slabs in this lot yet"]
        XCTAssertTrue(
            emptyTitle.waitForExistence(timeout: 5),
            "Lot detail should render the empty hint for a fresh lot"
        )
        try app.auditA11y(named: "lot detail (empty)")

        // 4. Pop back to the Lots tab.
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        backButton.tap()

        // 5. The new lot row is visible with prefix `lot-row-`. Match
        // by predicate so we don't have to know the auto-generated
        // date string.
        let lotRow = app.descendants(matching: .button)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'lot-row-'"))
            .firstMatch
        XCTAssertTrue(
            lotRow.waitForExistence(timeout: 5),
            "Lot row should appear on the Lots list after creation"
        )
        try app.auditA11y(named: "lots tab (one lot)")

        // 6. Open the row's overflow menu, then "Delete lot".
        let lotMenu = app.descendants(matching: .button)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'lot-menu-'"))
            .firstMatch
        XCTAssertTrue(lotMenu.waitForExistence(timeout: 2))
        lotMenu.tap()

        let deleteMenuItem = app.buttons["Delete lot"]
        XCTAssertTrue(deleteMenuItem.waitForExistence(timeout: 2))
        deleteMenuItem.tap()

        // 7. Inline confirmation strip appears anchored under the row.
        let confirm = app.buttons["inline-delete-confirm"]
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 2),
            "Inline delete confirmation should appear under the lot row"
        )
        try app.auditA11y(named: "lots tab (inline delete pending)")
        confirm.tap()

        // 8. The lot is gone and the empty state returns.
        XCTAssertTrue(
            app.staticTexts["No open lots"].waitForExistence(timeout: 3),
            "Empty-state header should return after deleting the only lot"
        )
    }

    /// Manual-price entry on a scan that has been validated upstream
    /// but has no comp from Pokemon Price Tracker. Driven by the
    /// `--ui-tests-seed-no-comp-scan` flag, which seeds:
    ///   * A `Sample Lot` open lot
    ///   * A `Test Card` graded identity
    ///   * A `validated` PSA scan with `compFetchState == .noData`
    /// Together those make the "Set manual price" CTA the screen's
    /// primary call to action without needing the cert-lookup +
    /// comp-fetch network pipeline.
    @MainActor
    func testSetManualPriceOnNoCompScan() throws {
        let app = UITestApp.launch([.seedNoCompScan])

        // 1. Open the seeded lot.
        let lotRow = app.buttons["lot-row-Sample Lot"]
        XCTAssertTrue(
            lotRow.waitForExistence(timeout: 5),
            "Seeded Sample Lot should appear on the Lots list"
        )
        try app.auditA11y(named: "lots tab (seeded)")
        XCTAssertTrue(
            lotRow.isHittable,
            "Lot row should be hittable before tapping"
        )
        // Tap the static text inside the row rather than the row button
        // itself. NavigationLinks with `.buttonStyle(.plain)` don't always
        // surface their tap recognizer cleanly to XCUI under iOS 26 when
        // the row contains nested text + chevron — tapping the leading
        // title text is the path that consistently dispatches the
        // NavigationLink's destination-push.
        let lotTitleHit = app.staticTexts["Sample Lot"]
        XCTAssertTrue(lotTitleHit.waitForExistence(timeout: 2))
        lotTitleHit.tap()

        // 2. Open the seeded scan.
        let scanRow = app.buttons["scan-row-11223344"]
        XCTAssertTrue(
            scanRow.waitForExistence(timeout: 8),
            "Seeded scan row should appear in the lot detail"
        )
        try app.auditA11y(named: "lot detail (seeded scan)")
        scanRow.tap()

        // 3. The scan is `validated` + `noData`, so the manual-price
        // CTA renders inside the no-comp empty state.
        let cta = app.buttons["manual-price-cta"]
        XCTAssertTrue(
            cta.waitForExistence(timeout: 5),
            "Set manual price CTA should appear on a no-comp scan"
        )
        try app.auditA11y(named: "scan detail (no comp)")
        cta.tap()

        // 4. ManualPriceSheet — type a price + save.
        let priceField = app.textFields["manual-price-field"]
        XCTAssertTrue(priceField.waitForExistence(timeout: 3))
        try app.auditA11y(named: "manual price sheet (entry)")
        priceField.tap()
        priceField.typeText("49.99")

        let save = app.buttons["manual-price-save"]
        XCTAssertTrue(save.isEnabled, "Save should enable once a non-empty price is typed")
        save.tap()

        // 5. The detail view should now render the manual-price card with
        // an Edit affordance — that's the contract for "the manual price
        // is persisted and reachable from this screen".
        let editManualPrice = app.buttons["manual-price-edit"]
        XCTAssertTrue(
            editManualPrice.waitForExistence(timeout: 3),
            "Manual price card should render after saving"
        )
        try app.auditA11y(named: "scan detail (with manual price)")

        // 6. Tap edit → Clear the price → CTA returns. This proves the
        // round-trip works (set, edit, clear) which is what users do
        // when they mis-enter a price and want to back out.
        editManualPrice.tap()
        XCTAssertTrue(priceField.waitForExistence(timeout: 3))
        let clear = app.buttons["manual-price-clear"]
        XCTAssertTrue(
            clear.waitForExistence(timeout: 2),
            "Clear button should be available when an existing price is loaded"
        )
        try app.auditA11y(named: "manual price sheet (edit)")
        clear.tap()

        XCTAssertTrue(
            app.buttons["manual-price-cta"].waitForExistence(timeout: 3),
            "Clearing the manual price should restore the Set manual price CTA"
        )
        try app.auditA11y(named: "scan detail (after clear)")
    }

    /// Inline slab-delete via the lot detail row menu. Exercises the
    /// other inline-confirmation surface (slabs, not lots) on a seeded
    /// scan so the test isn't coupled to live scanning.
    @MainActor
    func testInlineDeleteSlabFromLotDetail() throws {
        let app = UITestApp.launch([.seedNoCompScan])

        let lotRow = app.buttons["lot-row-Sample Lot"]
        XCTAssertTrue(lotRow.waitForExistence(timeout: 5))
        lotRow.tap()

        let scanRow = app.buttons["scan-row-11223344"]
        XCTAssertTrue(scanRow.waitForExistence(timeout: 5))

        let scanMenu = app.buttons["scan-menu-11223344"]
        XCTAssertTrue(scanMenu.waitForExistence(timeout: 3))
        scanMenu.tap()

        let deleteMenuItem = app.buttons["Delete slab"]
        XCTAssertTrue(deleteMenuItem.waitForExistence(timeout: 2))
        deleteMenuItem.tap()

        let confirm = app.buttons["inline-delete-confirm"]
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 2),
            "Inline delete confirmation should appear under the slab row"
        )
        try app.auditA11y(named: "lot detail (inline delete pending)")
        confirm.tap()

        XCTAssertFalse(
            app.buttons["scan-row-11223344"].waitForExistence(timeout: 2),
            "Slab row should disappear after inline delete confirms"
        )
    }
}
