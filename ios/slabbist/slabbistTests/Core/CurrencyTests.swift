import Testing
@testable import slabbist

@Suite("Currency")
struct CurrencyTests {
    @Test("formats USD cents as dollar amount")
    func formatsUSD() {
        #expect(Currency.displayUSD(cents: 12_050) == "$120.50")
        #expect(Currency.displayUSD(cents: 0) == "$0.00")
        #expect(Currency.displayUSD(cents: 31_000_00) == "$31,000.00")
    }

    @Test("handles nil with em-dash placeholder")
    func formatsNil() {
        #expect(Currency.displayUSD(cents: nil) == "—")
    }
}
