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

    @Test("search link wraps an encoded tcgplayer search URL with subId1")
    func searchWraps() throws {
        let url = try #require(
            TCGPlayerAffiliateLink.searchLink(query: "Pokémon March Neo Genesis", subId: "cameo", baseURL: base)
        )
        #expect(url.absoluteString ==
            "https://partner.tcgplayer.com/c/6098165/1830156/21018?subId1=cameo&u=https%3A%2F%2Fwww.tcgplayer.com%2Fsearch%2Fpokemon%2Fproduct%3FproductLineName%3Dpokemon%26q%3DPok%25C3%25A9mon%2520March%2520Neo%2520Genesis")
    }

    @Test("search link empty base falls back to the raw tcgplayer search URL")
    func searchRawFallback() throws {
        let url = try #require(
            TCGPlayerAffiliateLink.searchLink(query: "Switch Neo Genesis", subId: "cameo", baseURL: "")
        )
        #expect(url.absoluteString ==
            "https://www.tcgplayer.com/search/pokemon/product?productLineName=pokemon&q=Switch%20Neo%20Genesis")
    }

    @Test("search link with blank query returns nil so the button hides")
    func searchGuardsQuery() {
        #expect(TCGPlayerAffiliateLink.searchLink(query: "   ", subId: "cameo", baseURL: base) == nil)
    }
}
