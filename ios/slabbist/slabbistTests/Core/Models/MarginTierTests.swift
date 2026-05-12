import Testing
import Foundation
@testable import slabbist

@Suite("MarginTier ladder lookup")
struct MarginTierTests {
    @Test("canonicalize sorts descending and drops out-of-range tiers")
    func canonicalize() {
        let mixed: [MarginTier] = [
            MarginTier(minCompCents: 10_000, marginPct: 0.75),
            MarginTier(minCompCents: 100_000, marginPct: 0.90),
            MarginTier(minCompCents: 0, marginPct: 0.70),
            // Should be dropped: negative threshold, >1.0 pct.
            MarginTier(minCompCents: -1, marginPct: 0.80),
            MarginTier(minCompCents: 50_000, marginPct: 1.5),
        ]
        let canonical = mixed.canonicalized()
        #expect(canonical.count == 3)
        #expect(canonical.map(\.minCompCents) == [100_000, 10_000, 0])
    }

    @Test("ladder picks the highest threshold the comp clears")
    func picksHighestMatch() {
        let ladder: [MarginTier] = .defaultMarginLadder
        // $1,200 clears the $1,000 tier → 90%.
        #expect(ladder.margin(forCompCents: 120_000) == 0.90)
        // $750 clears the $500 tier but not the $1,000 tier → 85%.
        #expect(ladder.margin(forCompCents: 75_000) == 0.85)
        // $50 clears only the $0 floor → 70%.
        #expect(ladder.margin(forCompCents: 5_000) == 0.70)
    }

    @Test("ladder lookup returns nil when no tier covers the value")
    func returnsNilOnNoMatch() {
        let ladder: [MarginTier] = [
            MarginTier(minCompCents: 50_000, marginPct: 0.85)
        ]
        // Below the only tier's floor → no match.
        #expect(ladder.margin(forCompCents: 10_000) == nil)
        // At/above the floor → matches.
        #expect(ladder.margin(forCompCents: 50_000) == 0.85)
    }

    @Test("decodes the wire shape with snake_case keys")
    func decodesWireShape() throws {
        let json = #"""
        [
          { "min_comp_cents": 100000, "margin_pct": 0.90 },
          { "min_comp_cents": 0, "margin_pct": 0.70 }
        ]
        """#.data(using: .utf8)!
        let tiers = try JSONDecoder().decode([MarginTier].self, from: json)
        #expect(tiers.count == 2)
        #expect(tiers[0].minCompCents == 100_000)
        #expect(tiers[0].marginPct == 0.90)
        #expect(tiers[1].minCompCents == 0)
    }

    @Test("encodes back to the wire shape with snake_case keys")
    func encodesWireShape() throws {
        let tier = MarginTier(minCompCents: 50_000, marginPct: 0.85)
        let data = try JSONEncoder().encode(tier)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"min_comp_cents\":50000"))
        #expect(json.contains("\"margin_pct\":0.85"))
    }
}
