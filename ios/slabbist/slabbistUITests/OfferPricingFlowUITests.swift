import XCTest

/// End-to-end coverage of the offer-pricing workflow Plan 2 introduces.
/// Boots under `--ui-tests-seed-priced-lot` so the harness lands directly
/// on a lot that already has a validated scan + reconciled comp + auto-
/// derived buy price — i.e. the state that gates the "Send to offer" CTA
/// — without driving the cert-lookup + comp-fetch network pipeline.
///
/// The test exercises:
///   1. Adjust the lot's margin via `MarginPickerSheet` (70% snap).
///   2. Open the seeded scan and override its buy price via `BuyPriceSheet`.
///   3. Pop back to the lot and send the offer (state: priced → presented).
///   4. Navigate into `OfferReviewView` via the "Resume offer" link.
///   5. Bounce back to priced; confirm the action bar flips back.
///   6. Re-send, navigate again, decline; confirm "Re-open as new offer"
///      appears on lot detail.
final class OfferPricingFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_price_send_bounce_decline_flow() throws {
        let app = UITestApp.launch([.seedPricedLot])

        // 1. Lots tab is the default tab; the seeded lot is already on it.
        // Tap the static text inside the row to push into LotDetailView —
        // under iOS 26 + XCUI a NavigationLink with a nested chevron + text
        // doesn't always surface its tap on the parent button.
        let lotRow = app.buttons["lot-row-Sample Lot"]
        XCTAssertTrue(
            lotRow.waitForExistence(timeout: 5),
            "Seeded Sample Lot should appear on the Lots list"
        )
        app.staticTexts["Sample Lot"].tap()

        // 2. Adjust margin to 70% — `lot-margin-adjust` renders for all
        // non-drafting lots, so the seeded `.priced` lot exposes it.
        let adjustMargin = app.buttons["lot-margin-adjust"]
        XCTAssertTrue(
            adjustMargin.waitForExistence(timeout: 3),
            "Adjust margin affordance should render on a priced lot"
        )
        adjustMargin.tap()

        let snap70 = app.buttons["margin-snap-70"]
        XCTAssertTrue(snap70.waitForExistence(timeout: 2))
        snap70.tap()
        app.buttons["margin-save"].tap()

        // 3. Open the seeded scan and override its buy price. The seed
        // creates cert `55667788`, so we navigate to it via the row.
        let scanRow = app.buttons["scan-row-55667788"]
        XCTAssertTrue(
            scanRow.waitForExistence(timeout: 3),
            "Seeded scan row should appear on lot detail"
        )
        scanRow.tap()

        // 4. Tap "Edit" on the buy-price card to open `BuyPriceSheet`.
        let editBuy = app.buttons["buy-price-edit"]
        XCTAssertTrue(
            editBuy.waitForExistence(timeout: 3),
            "Buy price edit affordance should render on the scan detail"
        )
        editBuy.tap()

        // 5. Clear out the pre-filled value, type a new override, save.
        let field = app.textFields["buy-price-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        // The field comes pre-filled with the auto-derived value at 70%
        // margin ($70.00). Select-all + type replaces it cleanly.
        field.doubleTap()
        if let value = field.value as? String, !value.isEmpty {
            let backspace = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
            field.typeText(backspace)
        }
        field.typeText("75.00")

        let save = app.buttons["buy-price-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 2))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // 6. Reset-to-auto button should now render — proves the override
        // landed and the card refreshed.
        XCTAssertTrue(
            app.buttons["buy-price-reset"].waitForExistence(timeout: 3),
            "Reset-to-auto affordance should appear after overriding the buy price"
        )

        // 7. Pop back to LotDetailView and send the offer.
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        backButton.tap()

        let sendToOffer = app.buttons["send-to-offer"]
        XCTAssertTrue(
            sendToOffer.waitForExistence(timeout: 3),
            "Send to offer CTA should render on a priced lot"
        )
        sendToOffer.tap()

        // 8. State is now `.presented` — action bar flips to "Resume offer".
        // Navigate into OfferReviewView.
        let resumeOffer = app.buttons["resume-offer"]
        XCTAssertTrue(
            resumeOffer.waitForExistence(timeout: 3),
            "Resume offer link should render once a lot is presented"
        )
        resumeOffer.tap()
        XCTAssertTrue(
            app.staticTexts["Offer total"].waitForExistence(timeout: 3),
            "OfferReviewView should render after navigating in"
        )

        // 9. Bounce back — should return to LotDetailView with the
        // "Send to offer" CTA visible again (state flips back to .priced).
        let bounceBack = app.buttons["bounce-back"]
        XCTAssertTrue(bounceBack.waitForExistence(timeout: 2))
        bounceBack.tap()

        // Bounce back leaves the user on OfferReviewView in current code —
        // pop back manually to verify the lot is back in `.priced`.
        let backFromOffer = app.navigationBars.buttons.element(boundBy: 0)
        if backFromOffer.exists { backFromOffer.tap() }
        XCTAssertTrue(
            app.buttons["send-to-offer"].waitForExistence(timeout: 3),
            "Bouncing back should restore the Send to offer CTA on lot detail"
        )

        // 10. Send again, navigate in, then decline.
        app.buttons["send-to-offer"].tap()
        let resumeAgain = app.buttons["resume-offer"]
        XCTAssertTrue(resumeAgain.waitForExistence(timeout: 3))
        resumeAgain.tap()

        let decline = app.buttons["decline-offer"]
        XCTAssertTrue(decline.waitForExistence(timeout: 2))
        decline.tap()

        // Pop back to lot detail; declined lots show "Re-open as new offer".
        let backAfterDecline = app.navigationBars.buttons.element(boundBy: 0)
        if backAfterDecline.exists { backAfterDecline.tap() }
        XCTAssertTrue(
            app.buttons["reopen-declined"].waitForExistence(timeout: 3),
            "Declined lot should expose the re-open affordance"
        )
    }
}
