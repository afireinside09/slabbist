import Foundation
import Testing
@testable import slabbist

/// Round-trip tests for the pure pricing math. `OfferRepository`'s tests
/// (Task 8) cover the SwiftData + outbox side of the world; this suite
/// pins down the formula itself so the auto-derive can never drift away
/// from the server-side recompute without a failing test.
struct OfferPricingServiceTests {
    @Test func defaultBuyPriceProductRoundsHalfUp() {
        let r = OfferPricingService.defaultBuyPrice(reconciledCents: 1000, marginPct: 0.6)
        #expect(r == 600)
    }

    @Test func defaultBuyPriceHandlesOddMargins() {
        let r = OfferPricingService.defaultBuyPrice(reconciledCents: 999, marginPct: 0.65)
        #expect(r == 649)   // 999 * 0.65 = 649.35 → 649
    }

    @Test func defaultBuyPriceReturnsNilWhenInputsNil() {
        #expect(OfferPricingService.defaultBuyPrice(reconciledCents: nil, marginPct: 0.6) == nil)
        #expect(OfferPricingService.defaultBuyPrice(reconciledCents: 1000, marginPct: nil) == nil)
    }

    @Test func defaultBuyPriceReturnsZeroWhenZero() {
        #expect(OfferPricingService.defaultBuyPrice(reconciledCents: 0, marginPct: 0.6) == 0)
        #expect(OfferPricingService.defaultBuyPrice(reconciledCents: 1000, marginPct: 0) == 0)
    }

    @Test func defaultBuyPriceClampsMarginAtBounds() {
        #expect(OfferPricingService.defaultBuyPrice(reconciledCents: 1000, marginPct: 1.5) == nil)
        #expect(OfferPricingService.defaultBuyPrice(reconciledCents: 1000, marginPct: -0.1) == nil)
    }
}
