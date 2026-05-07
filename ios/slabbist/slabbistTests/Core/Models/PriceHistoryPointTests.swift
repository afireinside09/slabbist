import Testing
import Foundation
@testable import slabbist

@Suite("PriceHistoryPoint")
struct PriceHistoryPointTests {
    @Test("decodes a wire array of {ts, price_cents} into ordered points")
    func decodesWireArray() throws {
        let json = #"""
        [
          { "ts": "2025-11-08T00:00:00Z", "price_cents": 16200 },
          { "ts": "2025-11-15T00:00:00Z", "price_cents": 16850 }
        ]
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let points = try decoder.decode([PriceHistoryPoint].self, from: json)
        #expect(points.count == 2)
        #expect(points[0].priceCents == 16200)
        #expect(points[1].priceCents == 16850)
    }

    @Test("encodes back to the wire shape")
    func encodesToWireShape() throws {
        let p = PriceHistoryPoint(ts: Date(timeIntervalSince1970: 1_700_000_000), priceCents: 12345)
        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"price_cents\":12345"))
    }
}
