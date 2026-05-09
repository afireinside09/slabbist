import Foundation
import Testing
@testable import slabbist

@Suite("EbayAffiliateLink")
struct EbayAffiliateLinkTests {
    @Test("Non-eBay host passes through unchanged")
    func nonEbayPassthrough() {
        let raw = "https://example.com/itm/123"
        let result = EbayAffiliateLink.rewrite(raw)
        #expect(result?.absoluteString == raw)
    }

    @Test("eBay URL gains EPN params when campid is configured")
    func ebayGainsParams() throws {
        // This test exercises both branches: when campid is configured the
        // URL must contain the EPN params; when it's not, the URL must be
        // returned untouched. Configuration depends on the test runtime
        // (process env / Info.plist), so branch on what the helper sees.
        let raw = "https://www.ebay.com/itm/123456789"
        let result = try #require(EbayAffiliateLink.rewrite(raw))
        let resultString = result.absoluteString

        if AppEnvironment.epnCampaignID.isEmpty {
            #expect(resultString == raw)
        } else {
            #expect(resultString.contains("campid=\(AppEnvironment.epnCampaignID)"))
            #expect(resultString.contains("mkrid=711-53200-19255-0"))
            #expect(resultString.contains("mkcid=1"))
            #expect(resultString.contains("toolid=10001"))
            #expect(resultString.contains("mkevt=1"))
        }
    }

    @Test("Existing query params are preserved, EPN params merged in")
    func mergesWithExistingQuery() throws {
        guard !AppEnvironment.epnCampaignID.isEmpty else { return }
        let raw = "https://www.ebay.com/itm/123?_trkparms=foo&hash=bar"
        let result = try #require(EbayAffiliateLink.rewrite(raw))
        let resultString = result.absoluteString

        #expect(resultString.contains("_trkparms=foo"))
        #expect(resultString.contains("hash=bar"))
        #expect(resultString.contains("campid=\(AppEnvironment.epnCampaignID)"))
    }

    @Test("Existing campid in raw URL is not overwritten")
    func preservesExistingCampid() throws {
        guard !AppEnvironment.epnCampaignID.isEmpty else { return }
        let raw = "https://www.ebay.com/itm/123?campid=9999"
        let result = try #require(EbayAffiliateLink.rewrite(raw))
        let resultString = result.absoluteString

        // The pre-existing campid wins; we only fill gaps.
        #expect(resultString.contains("campid=9999"))
        #expect(!resultString.contains("campid=\(AppEnvironment.epnCampaignID)"))
    }
}
