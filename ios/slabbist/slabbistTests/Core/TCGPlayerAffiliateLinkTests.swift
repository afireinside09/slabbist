import Foundation
import Testing
@testable import slabbist

@Suite("TCGPlayerAffiliateLink")
struct TCGPlayerAffiliateLinkTests {
    let base = "https://partner.tcgplayer.com/c/6098165/1830156/21018"

    @Test("wraps product id as percent-encoded u= with subId1 surface tag")
    func wraps() throws {
        let url = try #require(
            TCGPlayerAffiliateLink.link(productId: 517812, subId: "graded", baseURL: base)
        )
        #expect(url.absoluteString ==
            "https://partner.tcgplayer.com/c/6098165/1830156/21018?subId1=graded&u=https%3A%2F%2Fwww.tcgplayer.com%2Fproduct%2F517812")
    }

    @Test("empty base URL falls back to the raw tcgplayer.com product URL")
    func rawFallback() throws {
        let url = try #require(
            TCGPlayerAffiliateLink.link(productId: 517812, subId: "mover", baseURL: "")
        )
        #expect(url.absoluteString == "https://www.tcgplayer.com/product/517812")
    }

    @Test("non-positive product id returns nil so the button hides")
    func guardsProductId() {
        #expect(TCGPlayerAffiliateLink.link(productId: 0, subId: "graded", baseURL: base) == nil)
        #expect(TCGPlayerAffiliateLink.link(productId: -5, subId: "graded", baseURL: base) == nil)
    }
}
