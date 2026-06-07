import Foundation

/// Pure geometry: turns the eight-line `CenteringGuides` into the
/// `CenteringRatios` the rest of the system already consumes, and keeps the
/// guides physically valid as they are dragged.
///
/// We measure the border width between the *outer card edge* and the *inner
/// frame* on each side — the quantity graders actually use — and emit the
/// standard `CenteringRatios` shape so nothing downstream changes.
enum CenteringGuideMath {
    /// Border widths → PSA-style centering ratios. `left = L / (L + R)` where
    /// `L = innerLeft − outerLeft` and `R = outerRight − innerRight`. A
    /// perfectly centered card returns `0.5` on every axis. A zero-total-border
    /// axis guards to `0.5`, and `right = 1 − left` symmetry holds — the
    /// `CenteringRatios` shape the rest of the system consumes.
    static func ratios(from g: CenteringGuides) -> CenteringRatios {
        let leftBorder = max(0, g.innerLeft - g.outerLeft)
        let rightBorder = max(0, g.outerRight - g.innerRight)
        let topBorder = max(0, g.innerTop - g.outerTop)
        let bottomBorder = max(0, g.outerBottom - g.innerBottom)

        let h = leftBorder + rightBorder
        let v = topBorder + bottomBorder

        let left = h == 0 ? 0.5 : leftBorder / h
        let top = v == 0 ? 0.5 : topBorder / v
        return CenteringRatios(left: left, right: 1 - left, top: top, bottom: 1 - top)
    }

    /// Enforce the physical invariants after a drag:
    /// `outerLeft ≤ innerLeft ≤ innerRight ≤ outerRight` (and the vertical
    /// analogue), with every line inside `0...1`. Outer lines may touch the
    /// image edge; inner lines stay between their two outer siblings.
    static func clamped(_ g: CenteringGuides) -> CenteringGuides {
        var out = g
        // Horizontal axis: outerLeft ≤ innerLeft ≤ innerRight ≤ outerRight.
        out.outerLeft = unit(out.outerLeft)
        out.outerRight = unit(out.outerRight)
        if out.outerRight < out.outerLeft { swap(&out.outerLeft, &out.outerRight) }
        out.innerLeft = clamp(out.innerLeft, out.outerLeft, out.outerRight)
        out.innerRight = clamp(out.innerRight, out.outerLeft, out.outerRight)
        if out.innerRight < out.innerLeft { out.innerRight = out.innerLeft }

        // Vertical axis: outerTop ≤ innerTop ≤ innerBottom ≤ outerBottom.
        out.outerTop = unit(out.outerTop)
        out.outerBottom = unit(out.outerBottom)
        if out.outerBottom < out.outerTop { swap(&out.outerTop, &out.outerBottom) }
        out.innerTop = clamp(out.innerTop, out.outerTop, out.outerBottom)
        out.innerBottom = clamp(out.innerBottom, out.outerTop, out.outerBottom)
        if out.innerBottom < out.innerTop { out.innerBottom = out.innerTop }

        return out
    }

    /// Set one edge to a new normalized value, then re-clamp the whole set.
    static func moving(_ g: CenteringGuides, _ edge: GuideEdge, to value: Double) -> CenteringGuides {
        var out = g
        out[edge] = value
        return clamped(out)
    }

    /// The highest PSA grade this centering *alone* would allow on the front,
    /// using PSA's current front tolerances (10 ≤ 55/45, 9 ≤ 60/40, 8 ≤ 65/35,
    /// 7 ≤ 70/30, 6 ≤ 80/20, 5 ≤ 85/15). Centering caps the grade — it can't
    /// lift corners/edges/surface — so this is a ceiling, not a prediction.
    /// Returned as the larger-side percentage's worst axis and a grade.
    static func psaCenteringCeiling(_ r: CenteringRatios) -> (worstPercent: Int, grade: Int) {
        let worst = max(r.left, r.right, r.top, r.bottom)
        let pct = Int((worst * 100).rounded())
        let grade: Int
        switch worst * 100 {
        case ...55: grade = 10
        case ...60: grade = 9
        case ...65: grade = 8
        case ...70: grade = 7
        case ...80: grade = 6
        case ...85: grade = 5
        default: grade = 4
        }
        return (pct, grade)
    }

    private static func unit(_ x: Double) -> Double { clamp(x, 0, 1) }
    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(x, lo), hi)
    }
}
