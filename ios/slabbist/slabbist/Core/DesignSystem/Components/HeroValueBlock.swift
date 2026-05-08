import SwiftUI

/// The Slabbist hero numeral pattern from the design brief.
///
/// Renders `$ 4,120 .00` in Instrument Serif: a smaller superscript-ish `$`
/// at half opacity, the whole-dollar amount at hero size with tight tracking,
/// and the cents in a reduced-opacity trailing block. An optional kicker,
/// delta, and caption line keep the block self-contained.
///
///     HeroValueBlock(
///         kicker: "Estimated",
///         cents: 412_000,
///         caption: "across 14 slabs"
///     )
///
/// Sizes follow the brief: 68 (portfolio), 54 (chart), 40 (card detail),
/// 36 (screen title equivalent). Default is 68; pass `size:` to downshift.
struct HeroValueBlock: View {
    enum Tint {
        case neutral
        case positive
        case negative

        var color: Color {
            switch self {
            case .neutral: return AppColor.muted
            case .positive: return AppColor.positive
            case .negative: return AppColor.negative
            }
        }

        var glyph: String? {
            switch self {
            case .neutral: return nil
            case .positive: return "arrow.up"
            case .negative: return "arrow.down"
            }
        }
    }

    let kicker: String?
    let cents: Int64
    let caption: String?
    let delta: String?
    let deltaTint: Tint
    let size: CGFloat

    init(
        kicker: String? = nil,
        cents: Int64,
        caption: String? = nil,
        delta: String? = nil,
        deltaTint: Tint = .neutral,
        size: CGFloat = 68
    ) {
        self.kicker = kicker
        self.cents = cents
        self.caption = caption
        self.delta = delta
        self.deltaTint = deltaTint
        self.size = size
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let kicker { KickerLabel(kicker) }
            valueRow
            if delta != nil || caption != nil {
                metaRow
            }
        }
    }

    private var valueRow: some View {
        let parts = Self.split(cents: cents)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("$")
                .font(SlabFont.serif(size: size * 0.52))
                .foregroundStyle(AppColor.text.opacity(0.5))
                .baselineOffset(size * 0.10)
                .padding(.trailing, size * 0.06)
            Text(parts.whole)
                .font(SlabFont.serif(size: size))
                .tracking(-size * 0.029)
                .foregroundStyle(AppColor.text)
            Text(parts.cents)
                .font(SlabFont.serif(size: size * 0.52))
                .foregroundStyle(AppColor.text.opacity(0.5))
                .baselineOffset(size * 0.04)
                .padding(.leading, size * 0.04)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(cents: cents, kicker: kicker))
    }

    private var metaRow: some View {
        HStack(spacing: Spacing.s) {
            if let delta {
                HStack(spacing: 4) {
                    if let glyph = deltaTint.glyph {
                        Image(systemName: glyph)
                            .font(SlabFont.sans(size: 11, weight: .semibold))
                    }
                    Text(delta)
                        .font(SlabFont.mono(size: 12, weight: .medium))
                }
                .foregroundStyle(deltaTint.color)
            }
            if let caption {
                Text(caption)
                    .font(SlabFont.mono(size: 12))
                    .foregroundStyle(AppColor.dim)
            }
        }
    }

    // MARK: - Formatting

    private static func split(cents: Int64) -> (whole: String, cents: String) {
        let dollars = Double(cents) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        let whole = formatter.string(from: NSNumber(value: Int64(dollars))) ?? "\(Int64(dollars))"
        let trailingCents = abs(cents) % 100
        let centsString = String(format: ".%02d", trailingCents)
        return (whole, centsString)
    }

    private static func spokenLabel(cents: Int64, kicker: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let amount = formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$\(Double(cents) / 100)"
        if let kicker { return "\(kicker), \(amount)" }
        return amount
    }
}

#Preview("Lot total") {
    HeroValueBlock(
        kicker: "Estimated",
        cents: 412_000,
        caption: "across 14 slabs"
    )
    .padding()
    .background(AppColor.ink)
}

#Preview("Mover now") {
    HeroValueBlock(
        kicker: "Now",
        cents: 8_499,
        delta: "+2.8%",
        deltaTint: .positive,
        size: 54
    )
    .padding()
    .background(AppColor.ink)
}

#Preview("Card detail") {
    HeroValueBlock(
        cents: 6_800,
        delta: "−4.1%",
        deltaTint: .negative,
        size: 40
    )
    .padding()
    .background(AppColor.ink)
}
