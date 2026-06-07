import Foundation
import Testing
@testable import slabbist

@Suite("CompSnapshotWire")
struct CompSnapshotWireTests {
    /// A frozen comp must faithfully reproduce the snapshot that justified
    /// the offer — if any priced field (headline, tier ladder, history,
    /// sold listings) is dropped on the round-trip, the audit record lies
    /// about what the operator saw. This test would fail if the encoder
    /// silently omitted a field or used a non-round-tripping date strategy.
    @Test func roundTripsAllPricedFields() throws {
        let identity = UUID()
        let snap = GradedMarketSnapshot(
            identityId: identity,
            gradingService: "PSA",
            grade: "10",
            source: "poketrace",
            headlinePriceCents: 125_00,
            ptAvgCents: 120_00,
            ptLowCents: 100_00,
            ptHighCents: 150_00,
            ptTrend: "up",
            ptConfidence: "high",
            ptSaleCount: 12,
            poketraceCardId: "pt-abc",
            tcgplayerProductId: 4242,
            ptTierPricesJSON: #"{"psa_10":12500,"psa_9":9000}"#,
            priceHistoryJSON: nil,
            marketplaceURL: URL(string: "https://ebay.com/sold"),
            soldListingsJSON: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cacheHit: true
        )

        let json = CompSnapshotWire.encode(from: snap)
        let wire = CompSnapshotWire.decode(json)

        #expect(wire?.headlinePriceCents == 125_00)
        #expect(wire?.source == "poketrace")
        #expect(wire?.ptConfidence == "high")
        #expect(wire?.ptSaleCount == 12)
        #expect(wire?.tcgplayerProductId == 4242)
        #expect(wire?.tierPricesCents["psa_10"] == 12500)
        #expect(wire?.tierPricesCents["psa_9"] == 9000)
        #expect(wire?.marketplaceURL?.absoluteString == "https://ebay.com/sold")
        #expect(wire?.cacheHit == true)
        #expect(wire?.fetchedAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// The nested blobs (price history, sold listings) carry `Date` fields
    /// that must survive the wire round-trip via the ISO8601 strategy. If the
    /// encoder/decoder used a mismatched date strategy, the dates would drift
    /// (or fail to decode), silently corrupting the audit record. The
    /// priced-fields test above leaves both blobs nil, so the nested-array
    /// path and its Dates are never exercised; this test populates them and
    /// asserts the first element's Date + cents survive exactly. The count
    /// assertions guard against a vacuous pass: if the fixture JSON were
    /// malformed, the snapshot accessors return [] and these would fail.
    @Test func roundTripsNestedDatesInHistoryAndSoldListings() throws {
        let historyTS = Date(timeIntervalSince1970: 1_699_000_000)
        let soldAt = Date(timeIntervalSince1970: 1_698_000_000)
        let isoHistoryTS = ISO8601DateFormatter().string(from: historyTS)
        let isoSoldAt = ISO8601DateFormatter().string(from: soldAt)

        let snap = GradedMarketSnapshot(
            identityId: UUID(),
            gradingService: "PSA",
            grade: "10",
            source: "poketrace",
            headlinePriceCents: 125_00,
            priceHistoryJSON: #"[{"ts":"\#(isoHistoryTS)","price_cents":11000}]"#,
            soldListingsJSON: #"[{"sourceListingId":"l1","soldAt":"\#(isoSoldAt)","priceCents":9500}]"#,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cacheHit: false
        )

        // Guard: the snapshot accessors must actually decode the fixtures,
        // otherwise the wire round-trip below would vacuously test [].
        #expect(snap.priceHistory.count == 1)
        #expect(snap.soldListings.count == 1)

        let json = CompSnapshotWire.encode(from: snap)
        let wire = try #require(CompSnapshotWire.decode(json))

        #expect(wire.priceHistory.count == 1)
        #expect(wire.priceHistory.first?.ts == historyTS)
        #expect(wire.priceHistory.first?.priceCents == 11000)

        #expect(wire.soldListings.count == 1)
        #expect(wire.soldListings.first?.soldAt == soldAt)
        #expect(wire.soldListings.first?.priceCents == 9500)
    }

    /// Missing/garbage blobs decode to nil rather than crashing — the
    /// detail view treats nil as "no frozen comp" and degrades gracefully.
    @Test func decodeReturnsNilForMissingOrMalformed() {
        #expect(CompSnapshotWire.decode(nil) == nil)
        #expect(CompSnapshotWire.decode("not json") == nil)
    }
}
