import Foundation
import Testing
@testable import slabbist

@Suite("CenteringGuideMath.ratios")
struct CenteringGuideMathTests {
    /// Equal borders on both axes must read as dead-center. This is the
    /// contract the grade estimate trusts as ground truth — if a symmetric
    /// card didn't read 50/50, every downstream grade would be biased.
    @Test("equal borders → 50/50 on both axes")
    func perfectlyCentered() {
        let g = CenteringGuides(
            outerLeft: 0.10, innerLeft: 0.18, innerRight: 0.82, outerRight: 0.90,
            outerTop: 0.10, innerTop: 0.18, innerBottom: 0.82, outerBottom: 0.90
        )
        let r = CenteringGuideMath.ratios(from: g)
        #expect(abs(r.left - 0.5) < 1e-9)
        #expect(abs(r.right - 0.5) < 1e-9)
        #expect(abs(r.top - 0.5) < 1e-9)
        #expect(abs(r.bottom - 0.5) < 1e-9)
    }

    /// A left border of 0.12 against a right border of 0.08 is the canonical
    /// 60/40 off-center — the threshold between a PSA 9 and a PSA 10 front.
    /// Getting this number wrong moves a card across a grade boundary.
    @Test("left border 0.12 vs right 0.08 → 60/40")
    func horizontalSkew() {
        // leftBorder = 0.20 - 0.08 = 0.12 ; rightBorder = 0.92 - 0.84 = 0.08
        let g = CenteringGuides(
            outerLeft: 0.08, innerLeft: 0.20, innerRight: 0.84, outerRight: 0.92,
            outerTop: 0.10, innerTop: 0.18, innerBottom: 0.82, outerBottom: 0.90
        )
        let r = CenteringGuideMath.ratios(from: g)
        #expect(abs(r.left - 0.6) < 1e-9)
        #expect(abs(r.right - 0.4) < 1e-9)
    }

    /// A degenerate side (inner line sitting on its outer line → zero total
    /// border) must not divide by zero; it falls back to 50/50, so a
    /// half-placed guide reads neutral rather than NaN.
    @Test("zero total border on an axis → 0.5 fallback")
    func zeroBorderFallback() {
        let g = CenteringGuides(
            outerLeft: 0.20, innerLeft: 0.20, innerRight: 0.80, outerRight: 0.80,
            outerTop: 0.10, innerTop: 0.18, innerBottom: 0.82, outerBottom: 0.90
        )
        let r = CenteringGuideMath.ratios(from: g)
        #expect(r.left == 0.5)
        #expect(r.right == 0.5)
    }

    /// The ratio pair must always sum to 1 — a structural invariant the
    /// readout and grade thresholds both rely on. Checked across a spread of
    /// valid guide sets so a future change to the formula can't silently
    /// break symmetry.
    @Test("right == 1 - left and bottom == 1 - top for valid guides")
    func symmetry() {
        for offset in stride(from: 0.0, through: 0.06, by: 0.01) {
            let g = CenteringGuides(
                outerLeft: 0.08, innerLeft: 0.16 + offset, innerRight: 0.84, outerRight: 0.92,
                outerTop: 0.08, innerTop: 0.16, innerBottom: 0.84 - offset, outerBottom: 0.92
            )
            let r = CenteringGuideMath.ratios(from: g)
            #expect(abs((r.left + r.right) - 1) < 1e-12)
            #expect(abs((r.top + r.bottom) - 1) < 1e-12)
        }
    }
}
