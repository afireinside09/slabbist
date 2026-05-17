import SwiftUI

/// Inline trailing-edge pill that lets the operator set or edit a per-scan
/// manual price without drilling into `ScanDetailView`. Two variants:
///   * `priceCents == nil` → uppercase mono "Set price" in muted text.
///     Surfaces on rows where the comp returned `.noData` and no manual
///     price has been entered.
///   * `priceCents != nil` → mono dollar amount plus a pencil glyph for
///     the edit case. Surfaces on rows where the user already typed in a
///     manual price and the comp still hasn't reconciled.
///
/// Intentionally **no gold**. The pill is hairline-bordered with muted text
/// so the lot-level "Create Offer" CTA remains the only gold-anchored
/// affordance on the surface (one-gold-per-screen rule from `.impeccable.md`).
/// `frame(minHeight: 44)` keeps the HIG-mandated 44pt touch target without
/// inflating the visible chrome.
struct SetPricePill: View {
    let priceCents: Int64?
    let accessibilityLabel: String?
    let action: () -> Void

    init(priceCents: Int64?, accessibilityLabel: String? = nil, action: @escaping () -> Void) {
        self.priceCents = priceCents
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let cents = priceCents {
                    Text(Self.formattedCompact(cents))
                        .font(SlabFont.mono(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.text)
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColor.dim)
                        .accessibilityHidden(true)
                } else {
                    Text("Set price")
                        .font(SlabFont.mono(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColor.muted)
                }
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: 44)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .stroke(AppColor.hairlineStrong, lineWidth: 1)
            )
            // P2.6 — clip taps to the rounded pill so the 44pt minHeight
            // slug doesn't shadow the row's NavigationLink in adjacent
            // column space. The visible chrome is ~24pt tall;
            // RoundedRectangle preserves a softer hit on the corners but
            // doesn't leak into the row body.
            .contentShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        }
        .buttonStyle(.plain)
        .applyAccessibilityLabel(accessibilityLabel)
    }

    /// Compact USD: "$25" / "$1,250" — rounded to whole dollars so the pill
    /// fits in a queue-row trailing slot without truncation. The detail-row
    /// surfaces (`ScanDetailView`'s manual-price card) still show full
    /// cents; this is the trailing-edge summary only.
    static func formattedCompact(_ cents: Int64) -> String {
        let dollars = Int((Double(cents) / 100).rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
}

private extension View {
    @ViewBuilder
    func applyAccessibilityLabel(_ label: String?) -> some View {
        if let label {
            self.accessibilityLabel(label)
        } else {
            self
        }
    }
}

#Preview("SetPricePill") {
    VStack(spacing: Spacing.m) {
        SetPricePill(priceCents: nil, action: {})
        SetPricePill(priceCents: 25_00, action: {})
        SetPricePill(priceCents: 1_250_00, action: {})
    }
    .padding()
    .background(AppColor.ink)
}
