import Testing
import Foundation
@testable import slabbist

@Suite("CompFetchService.classify")
struct CompFetchServiceClassifyTests {
    @Test("noMarketData maps to no_data with a Pokemon Price Tracker-flavored message")
    func mapsNoMarketData() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.noMarketData)
        #expect(state == .noData)
        #expect(message.localizedCaseInsensitiveContains("pokemon price tracker"))
    }

    @Test("productNotResolved also maps to no_data, with distinct copy")
    func mapsProductNotResolved() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.productNotResolved)
        #expect(state == .noData)
        #expect(message.localizedCaseInsensitiveContains("couldn't find"))
    }

    @Test("upstreamUnavailable maps to failed with Pokemon Price Tracker wording")
    func mapsUpstream() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.upstreamUnavailable)
        #expect(state == .failed)
        #expect(message.localizedCaseInsensitiveContains("pokemon price tracker"))
    }

    @Test("authInvalid maps to failed with operator-actionable copy")
    func mapsAuthInvalid() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.authInvalid)
        #expect(state == .failed)
        #expect(message.localizedCaseInsensitiveContains("misconfigured"))
    }

    @Test("identityNotFound suggests re-scanning the cert")
    func mapsIdentityNotFound() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.identityNotFound)
        #expect(state == .failed)
        #expect(message.localizedCaseInsensitiveContains("re-scan"))
    }

    @Test("httpStatus surfaces the status code in the message")
    func mapsHttpStatus() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.httpStatus(502))
        #expect(state == .failed)
        #expect(message.contains("502"))
    }

    @Test("decoding error includes the underlying detail")
    func mapsDecoding() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.decoding("missing key 'headline_price_cents'"))
        #expect(state == .failed)
        #expect(message.contains("headline_price_cents"))
    }

    @Test("unknown errors fall through to localizedDescription")
    func fallsThroughToLocalized() {
        struct Bogus: Error, LocalizedError {
            var errorDescription: String? { "something exploded" }
        }
        let (state, message) = CompFetchService.classify(Bogus())
        #expect(state == .failed)
        #expect(message == "something exploded")
    }
}
