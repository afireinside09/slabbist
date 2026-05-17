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

    // Regression: the old parseCents in Manual/BuyPriceSheet replaced ',' with
    // '.', turning "1,500" into 1.5 dollars (150 cents) instead of 150_000.
    // Off-by-1000 on every pasted thousands-separated value. parseUSDToCents
    // treats comma as the thousands separator, the way US locale users expect.
    @Test("comma is a thousands separator, not a decimal mark")
    func parsesThousandsSeparators() {
        #expect(Currency.parseUSDToCents("1,500") == 150_000)
        #expect(Currency.parseUSDToCents("1,500.00") == 150_000)
        #expect(Currency.parseUSDToCents("12,345.67") == 1_234_567)
    }

    @Test("parses plain decimal entries")
    func parsesPlainDecimals() {
        #expect(Currency.parseUSDToCents("0") == 0)
        #expect(Currency.parseUSDToCents("0.00") == 0)
        #expect(Currency.parseUSDToCents("49.99") == 4_999)
        #expect(Currency.parseUSDToCents("99.9") == 9_990)
        #expect(Currency.parseUSDToCents("1500") == 150_000)
    }

    @Test("rounds the third decimal place to the nearest cent")
    func roundsToNearestCent() {
        #expect(Currency.parseUSDToCents("12.345") == 1_235)
        #expect(Currency.parseUSDToCents("12.344") == 1_234)
        #expect(Currency.parseUSDToCents("0.005") == 1)
    }

    @Test("strips dollar sign and surrounding whitespace")
    func stripsAdornments() {
        #expect(Currency.parseUSDToCents("  $1,500  ") == 150_000)
        #expect(Currency.parseUSDToCents("$49.99") == 4_999)
    }

    @Test("rejects empty, non-numeric, and negative input")
    func rejectsInvalidInput() {
        #expect(Currency.parseUSDToCents("") == nil)
        #expect(Currency.parseUSDToCents("   ") == nil)
        #expect(Currency.parseUSDToCents("abc") == nil)
        #expect(Currency.parseUSDToCents("$") == nil)
        #expect(Currency.parseUSDToCents("-5") == nil)
        #expect(Currency.parseUSDToCents("-1,500.00") == nil)
    }
}
