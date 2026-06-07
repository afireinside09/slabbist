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

    /// Missing/garbage blobs decode to nil rather than crashing — the
    /// detail view treats nil as "no frozen comp" and degrades gracefully.
    @Test func decodeReturnsNilForMissingOrMalformed() {
        #expect(CompSnapshotWire.decode(nil) == nil)
        #expect(CompSnapshotWire.decode("not json") == nil)
    }
}
