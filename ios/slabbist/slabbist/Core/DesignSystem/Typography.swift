import SwiftUI

/// Font constructors tuned for the Slabbist design language.
/// Serif falls back to `.serif` design if the custom font is missing —
/// SwiftUI's `Font.custom(_:size:)` handles that automatically.
enum SlabFont {
    static func serif(size: CGFloat) -> Font {
        .custom("InstrumentSerif-Regular", size: size)
    }

    static func serifItalic(size: CGFloat) -> Font {
        .custom("InstrumentSerif-Italic", size: size)
    }

    static func sans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - View modifiers

extension View {
    /// 68pt Instrument Serif, tracking -2. For portfolio-value-sized numerals.
    func slabHero() -> some View {
        self.font(SlabFont.serif(size: 68))
            .tracking(-2)
            .foregroundStyle(AppColor.text)
    }

    /// 36pt Instrument Serif, tracking -1. For screen titles.
    func slabTitle() -> some View {
        self.font(SlabFont.serif(size: 36))
            .tracking(-1)
            .foregroundStyle(AppColor.text)
    }

    /// 11pt uppercase sans medium, tracking 2.0, .dim foreground.
    /// Precedes every section.
    func slabKicker() -> some View {
        self.font(SlabFont.sans(size: 11, weight: .medium))
            .tracking(2.0)
            .textCase(.uppercase)
            .foregroundStyle(AppColor.dim)
    }

    /// 14pt sans medium, tracking -0.15. Default row title.
    func slabRowTitle() -> some View {
        self.font(SlabFont.sans(size: 14, weight: .medium))
            .tracking(-0.15)
            .foregroundStyle(AppColor.text)
    }

    /// 14pt mono medium. For prices, counts, metric readouts.
    func slabMetric() -> some View {
        self.font(SlabFont.mono(size: 14, weight: .medium))
            .foregroundStyle(AppColor.text)
    }
}
