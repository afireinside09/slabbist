import Foundation
import Testing
@testable import slabbist

@Suite("CenteringGuideMath.clamped")
struct CenteringGuideClampingTests {
    /// Dragging an inner line past its outer sibling must be stopped at the
    /// outer line — otherwise the border width goes negative and the ratio
    /// inverts, silently flipping which side is "off-center".
    @Test("inner line cannot cross outside its outer line")
    func innerClampedByOuter() {
        var g = CenteringGuides.centeredDefault
        g = CenteringGuideMath.moving(g, .innerLeft, to: 0.02) // past outerLeft (0.08)
        #expect(g.innerLeft >= g.outerLeft)
        #expect(g.innerLeft == g.outerLeft)
    }

    /// Dragging an outer line inward past its inner sibling must push or stop
    /// at the inner line — the ordering outer ≤ inner must hold from either
    /// direction, not just when the inner moves.
    @Test("outer line crossing inward clamps the inner line with it")
    func outerClampsInner() {
        var g = CenteringGuides.centeredDefault // innerLeft 0.16
        g = CenteringGuideMath.moving(g, .outerLeft, to: 0.40) // past innerLeft
        #expect(g.outerLeft <= g.innerRight)
        #expect(g.innerLeft >= g.outerLeft)
        #expect(g.innerLeft <= g.innerRight)
    }

    /// Any drag beyond the image must be pinned to the `0...1` bounds — a
    /// guide off the image edge would compute a border from pixels that
    /// don't exist.
    @Test("out-of-bounds drag clamps into 0...1")
    func boundsClamp() {
        var g = CenteringGuides.centeredDefault
        g = CenteringGuideMath.moving(g, .outerRight, to: 1.8)
        #expect(g.outerRight <= 1.0)
        g = CenteringGuideMath.moving(g, .outerTop, to: -0.5)
        #expect(g.outerTop >= 0.0)
    }

    /// The full ordering invariant must survive an arbitrary sequence of
    /// drags, including ones that try to scramble the order — clamping is
    /// only correct if it's order-restoring after *every* mutation, not just
    /// a single well-behaved one.
    @Test("ordering invariant holds after a scrambling drag sequence")
    func orderingInvariant() {
        var g = CenteringGuides.centeredDefault
        let moves: [(GuideEdge, Double)] = [
            (.innerLeft, 0.95), (.outerRight, 0.05), (.innerRight, 0.01),
            (.outerTop, 0.99), (.innerBottom, 0.02), (.innerTop, 0.97)
        ]
        for (edge, value) in moves {
            g = CenteringGuideMath.moving(g, edge, to: value)
            #expect(g.outerLeft <= g.innerLeft)
            #expect(g.innerLeft <= g.innerRight)
            #expect(g.innerRight <= g.outerRight)
            #expect(g.outerTop <= g.innerTop)
            #expect(g.innerTop <= g.innerBottom)
            #expect(g.innerBottom <= g.outerBottom)
            for edge in GuideEdge.allCases {
                #expect(g[edge] >= 0 && g[edge] <= 1)
            }
        }
    }
}
