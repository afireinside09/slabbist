import SwiftUI
import Foundation

extension Color {
    /// Build a `Color` from an OKLCH triple, mapping into Display P3.
    ///
    /// Use for saturated brand colors (gold, pos, neg) whose chroma clips in
    /// the sRGB gamut. Display P3 is wide-gamut on every iPhone since 7+.
    ///
    /// Pipeline: OKLCH → Oklab → linear sRGB → linear Display P3 → encoded P3.
    /// Reference: Björn Ottosson's Oklab + W3C CSS Color 4 sRGB↔P3 matrices.
    static func oklchP3(_ L: Double, _ C: Double, _ H: Double, alpha: Double = 1.0) -> Color {
        let hRad = H * .pi / 180.0
        let a = C * cos(hRad)
        let b = C * sin(hRad)

        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let lCubed = l_ * l_ * l_
        let mCubed = m_ * m_ * m_
        let sCubed = s_ * s_ * s_

        let lr =  4.0767416621 * lCubed - 3.3077115913 * mCubed + 0.2309699292 * sCubed
        let lg = -1.2684380046 * lCubed + 2.6097574011 * mCubed - 0.3413193965 * sCubed
        let lb = -0.0041960863 * lCubed - 0.7034186147 * mCubed + 1.7076147010 * sCubed

        let pr = 0.82246197 * lr + 0.17753803 * lg
        let pg = 0.03319420 * lr + 0.96680580 * lg
        let pb = 0.01708225 * lr + 0.07239550 * lg + 0.91052225 * lb

        func encode(_ x: Double) -> Double {
            let clamped = max(0.0, min(1.0, x))
            return clamped <= 0.0031308
                ? 12.92 * clamped
                : 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
        }

        return Color(
            .displayP3,
            red: encode(pr),
            green: encode(pg),
            blue: encode(pb),
            opacity: alpha
        )
    }
}
