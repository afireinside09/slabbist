import Foundation
import Testing
import SwiftUI
import UIKit
@testable import slabbist

@Suite("Movers rendering + formatting")
@MainActor
struct MoversRenderTests {
    @Test("MoversFormat.price renders a USD string with two decimals")
    func priceFormat() {
        // Foundation may emit narrow no-break spaces around the
        // currency symbol depending on SDK version; assert on the
        // value-bearing portion rather than the exact whitespace.
        let twelve = MoversFormat.price(12.345)
        #expect(twelve.contains("12.35"))
        #expect(twelve.contains("$"))

        let large = MoversFormat.price(1234.5)
        #expect(large.contains("1,234.50"))
        #expect(large.contains("$"))

        let zero = MoversFormat.price(0)
        #expect(zero.contains("0.00"))
    }

    @Test("MoversFormat.percent prefixes sign and keeps one decimal")
    func percentFormat() {
        #expect(MoversFormat.percent(3.25) == "+3.2%" || MoversFormat.percent(3.25) == "+3.3%")
        #expect(MoversFormat.percent(-7.0) == "-7.0%")
        #expect(MoversFormat.percent(0) == "+0.0%")
    }

    @Test("MoversListView renders in a hosting controller")
    func moversListViewRenders() {
        let host = UIHostingController(rootView: MoversListView())
        host.view.layoutIfNeeded()
        #expect(host.view != nil)
    }

    @Test("MoverDTO decodes numeric fields from JSON numbers")
    func moverDTODecodesNumbers() throws {
        let json = #"""
        [{
          "product_id": 1234,
          "product_name": "Charizard ex",
          "group_name": "Scarlet & Violet - 151",
          "image_url": "https://example.com/card.jpg",
          "sub_type_name": "Normal",
          "current_price": 412.55,
          "previous_price": 389.10,
          "abs_change": 23.45,
          "pct_change": 6.0265,
          "captured_at": "2026-04-23T17:49:00Z",
          "previous_captured_at": "2026-04-22T17:49:00Z"
        }]
        """#
        let rows = try JSONCoders.decoder.decode([MoverDTO].self, from: Data(json.utf8))
        #expect(rows.count == 1)
        #expect(rows[0].productId == 1234)
        #expect(rows[0].productName == "Charizard ex")
        #expect(rows[0].groupName == "Scarlet & Violet - 151")
        #expect(rows[0].currentPrice == 412.55)
        #expect(rows[0].pctChange > 6 && rows[0].pctChange < 6.1)
    }

    @Test("MoverDTO tolerates PostgREST string-encoded numerics")
    func moverDTODecodesNumericStrings() throws {
        // PostgREST v11+ serializes `numeric` as a JSON string to
        // preserve precision. The DTO must round-trip either shape.
        let json = #"""
        [{
          "product_id": 99,
          "product_name": "Pikachu",
          "group_name": null,
          "image_url": null,
          "sub_type_name": "Normal",
          "current_price": "10.00",
          "previous_price": "12.50",
          "abs_change": "-2.50",
          "pct_change": "-20.0",
          "captured_at": "2026-04-23T17:49:00Z",
          "previous_captured_at": "2026-04-22T17:49:00Z"
        }]
        """#
        let rows = try JSONCoders.decoder.decode([MoverDTO].self, from: Data(json.utf8))
        #expect(rows.count == 1)
        #expect(rows[0].currentPrice == 10.0)
        #expect(rows[0].pctChange == -20.0)
        #expect(rows[0].groupName == nil)
    }
}
