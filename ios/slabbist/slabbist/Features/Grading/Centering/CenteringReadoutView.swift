import SwiftUI

/// Live centering readout: L/R and T/B as integer percentages plus a single
/// PSA-ceiling hint. A plain-data view (`Equatable` inputs) so it re-renders
/// only when the ratios actually change.
struct CenteringReadoutView: View {
    let ratios: CenteringRatios

    var body: some View {
        let lr = pair(ratios.left, ratios.right)
        let tb = pair(ratios.top, ratios.bottom)
        let ceiling = CenteringGuideMath.psaCenteringCeiling(ratios)

        HStack(spacing: Spacing.l) {
            axisReadout(label: "L | R", value: lr)
            Divider().frame(height: 22).overlay(AppColor.hairline)
            axisReadout(label: "T | B", value: tb)
            Divider().frame(height: 22).overlay(AppColor.hairline)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Allows")
                    .slabKicker()
                Text("PSA \(ceiling.grade)")
                    .font(SlabFont.mono(size: 14, weight: .semibold))
                    .foregroundStyle(ceiling.grade >= 9 ? AppColor.positive : AppColor.gold)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(Capsule().fill(AppColor.ink.opacity(0.82)))
        .overlay(Capsule().stroke(AppColor.hairline, lineWidth: 1))
    }

    private func axisReadout(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label).slabKicker()
            Text(value)
                .font(SlabFont.mono(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.text)
                .contentTransition(.numericText())
        }
    }

    private func pair(_ a: Double, _ b: Double) -> String {
        "\(Int((a * 100).rounded())) / \(Int((b * 100).rounded()))"
    }
}
