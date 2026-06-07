import Foundation
import Testing
@testable import slabbist

@Suite("InnerFrameDetector seeding")
struct InnerFrameDetectorTests {
    /// The seed must always produce a physically valid guide set — inner
    /// lines strictly inside their outer siblings, everything in bounds — so
    /// the editor opens on something draggable rather than a degenerate or
    /// inverted layout.
    @Test("bestGuess insets the inner guides and keeps ordering valid")
    func bestGuessOrdered() {
        let outer = CenteringGuides(
            outerLeft: 0.10, innerLeft: 0.10, innerRight: 0.90, outerRight: 0.90,
            outerTop: 0.12, innerTop: 0.12, innerBottom: 0.88, outerBottom: 0.88
        )
        let g = InnerFrameDetector.bestGuess(outer: outer)

        #expect(g.innerLeft > g.outerLeft)
        #expect(g.innerRight < g.outerRight)
        #expect(g.innerTop > g.outerTop)
        #expect(g.innerBottom < g.outerBottom)
        #expect(g.innerLeft <= g.innerRight)
        #expect(g.innerTop <= g.innerBottom)
        for e in GuideEdge.allCases { #expect(g[e] >= 0 && g[e] <= 1) }
    }

    /// The detection-failure fallback must read as dead-centered, so a card
    /// the editor couldn't auto-locate still starts from a neutral 50/50
    /// rather than a biased guess.
    @Test("centeredFallback measures 50/50")
    func fallbackCentered() {
        let r = CenteringGuideMath.ratios(from: InnerFrameDetector.centeredFallback())
        #expect(abs(r.left - 0.5) < 1e-9)
        #expect(abs(r.top - 0.5) < 1e-9)
    }
}
