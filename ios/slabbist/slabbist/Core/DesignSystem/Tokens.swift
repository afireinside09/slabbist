import SwiftUI

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs:  CGFloat = 4
    static let s:   CGFloat = 8
    static let m:   CGFloat = 12
    static let md:  CGFloat = 14
    static let l:   CGFloat = 16
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

enum Radius {
    static let xs: CGFloat = 6
    static let s:  CGFloat = 10
    static let m:  CGFloat = 14
    static let l:  CGFloat = 18
    static let xl: CGFloat = 22
}

enum AppColor {
    // Surfaces
    static let ink             = Color(hex: 0x08080A)
    static let surface         = Color(hex: 0x101013)
    static let elev            = Color(hex: 0x17171B)
    static let elev2           = Color(hex: 0x1E1E23)

    // Dividers
    static let hairline        = Color.white.opacity(0.08)
    static let hairlineStrong  = Color.white.opacity(0.14)

    // Content
    static let text            = Color(hex: 0xF4F2ED)
    static let muted           = Color(hex: 0xF4F2ED, alpha: 0.58)
    static let dim             = Color(hex: 0xF4F2ED, alpha: 0.36)

    // Accent — Display P3 from OKLCH so saturated chroma doesn't clip in sRGB.
    static let gold            = Color.oklchP3(0.82, 0.13, 78)
    static let goldDim         = Color.oklchP3(0.58, 0.09, 75)
    /// Text-on-gold for the rare cases gold sits on a darker tile; usually `ink` is preferred.
    static let goldInk         = Color.oklchP3(0.32, 0.07, 72)

    // Semantic
    static let positive        = Color.oklchP3(0.78, 0.14, 155)
    static let negative        = Color.oklchP3(0.68, 0.18, 25)
}
