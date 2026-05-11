import XCTest

/// End-to-end coverage of the Vendors flow:
/// More tab → Vendors → create → archive → confirm archived bucket.
///
/// Boots under `--ui-tests` (no Supabase, in-memory SwiftData) so the
/// list starts empty and we can assert on freshly created rows by name.
final class VendorsFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_create_edit_archive_vendor_flow() throws {
        let app = UITestApp.launch()

        // 1. Navigate More → Vendors.
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5))
        moreTab.tap()

        let vendorsRow = app.buttons["settings-vendors-row"]
        XCTAssertTrue(
            vendorsRow.waitForExistence(timeout: 3),
            "Vendors row should appear in More tab"
        )
        vendorsRow.tap()

        // 2. Create a vendor.
        let newVendor = app.buttons["vendor-list-new"]
        XCTAssertTrue(
            newVendor.waitForExistence(timeout: 3),
            "New vendor CTA should appear on the empty Vendors list"
        )
        newVendor.tap()

        let nameField = app.textFields["vendor-edit-name"]
        XCTAssertTrue(
            nameField.waitForExistence(timeout: 3),
            "Vendor edit sheet should expose the name field"
        )
        nameField.tap()
        nameField.typeText("Acme Cards")

        let saveButton = app.buttons["vendor-edit-save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        saveButton.tap()

        // 3. Tap into the new row's detail view. NavigationLinks with
        // `.buttonStyle(.plain)` under iOS 26 sometimes don't surface
        // their tap recognizer cleanly to XCUI when the row contains
        // nested text + chevron — tapping the leading title text is the
        // path that consistently dispatches the destination-push (see
        // ManualPriceFlowUITests for the same workaround on lot rows).
        let row = app.buttons["vendor-row-Acme Cards"]
        XCTAssertTrue(
            row.waitForExistence(timeout: 3),
            "New vendor row should appear under Active"
        )
        let rowTitle = app.staticTexts["Acme Cards"]
        XCTAssertTrue(rowTitle.waitForExistence(timeout: 2))
        rowTitle.tap()

        // 4. Archive the vendor.
        let archive = app.buttons["vendor-detail-archive"]
        XCTAssertTrue(
            archive.waitForExistence(timeout: 3),
            "Archive button should be present on detail view for an active vendor"
        )
        archive.tap()

        // 5. Pop back to the Vendors list. The first toolbar button on
        // the navigation bar is the system back button under iOS 26.
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        backButton.tap()

        // 6. Row reappears under Archived. The list also no longer
        // surfaces the Reactivate button on the detail view, but to
        // assert the row's archived state from the list we look for the
        // Archived section's kicker. SwiftUI's `.textCase(.uppercase)`
        // only affects rendering; XCUI sees the source string.
        let archivedKicker = app.staticTexts["Archived"]
        XCTAssertTrue(
            archivedKicker.waitForExistence(timeout: 3),
            "Archived section should appear once a vendor is archived"
        )

        // The vendor row stays visible — it just lives under Archived.
        XCTAssertTrue(
            app.buttons["vendor-row-Acme Cards"].waitForExistence(timeout: 2),
            "Archived vendor row should still render in the Archived section"
        )
    }
}
