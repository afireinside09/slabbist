import Testing
import Foundation
@testable import slabbist

@Suite("CompFetchService.classify")
struct CompFetchServiceClassifyTests {
    @Test("noMarketData maps to no_data with a friendly message")
    func mapsNoMarketData() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.noMarketData)
        #expect(state == .noData)
        #expect(message.contains("No eBay sales"))
    }

    @Test("upstreamUnavailable maps to failed and points the user at logs")
    func mapsUpstream() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.upstreamUnavailable)
        #expect(state == .failed)
        #expect(message.localizedCaseInsensitiveContains("ebay"))
    }

    @Test("httpStatus surfaces the status code in the message")
    func mapsHttpStatus() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.httpStatus(502))
        #expect(state == .failed)
        #expect(message.contains("502"))
    }

    @Test("decoding error includes the underlying detail")
    func mapsDecoding() {
        let (state, message) = CompFetchService.classify(CompRepository.Error.decoding("missing key 'sample_count'"))
        #expect(state == .failed)
        #expect(message.contains("sample_count"))
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
