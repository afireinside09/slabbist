import SwiftUI

enum Spacing {
    static let xs: CGFloat = 4
    static let s:  CGFloat = 8
    static let m:  CGFloat = 16
    static let l:  CGFloat = 24
    static let xl: CGFloat = 32
}

enum Radius {
    static let s: CGFloat = 6
    static let m: CGFloat = 12
    static let l: CGFloat = 20
}

enum AppColor {
    static let surface    = Color(.systemBackground)
    static let surfaceAlt = Color(.secondarySystemBackground)
    static let accent     = Color.accentColor
    static let success    = Color.green
    static let warning    = Color.orange
    static let danger     = Color.red
}
