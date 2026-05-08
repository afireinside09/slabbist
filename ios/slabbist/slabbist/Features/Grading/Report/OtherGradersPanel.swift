import SwiftUI

struct OtherGradersPanel: View {
    let bundle: OtherGradersBundle

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Other graders")
            SlabCard {
                VStack(spacing: 0) {
                    row("BGS", report: bundle.bgs)
                    SlabCardDivider()
                    row("CGC", report: bundle.cgc)
                    SlabCardDivider()
                    row("SGC", report: bundle.sgc)
                }
            }
            Text("Predictions reuse the same sub-grades with adjusted composite math, not separately calibrated models.")
                .font(SlabFont.sans(size: 12))
                .foregroundStyle(AppColor.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func row(_ name: String, report: PerGraderReport) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Text(name)
                .font(SlabFont.sans(size: 13, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(AppColor.text)
                .frame(width: 44, alignment: .leading)
            Text(String(format: "%.1f", report.compositeGrade))
                .font(SlabFont.mono(size: 18, weight: .medium))
                .foregroundStyle(AppColor.text)
            Spacer()
            Text(verdictLabel(report.verdict))
                .font(SlabFont.sans(size: 11, weight: .medium))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.dim)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
    }

    private func verdictLabel(_ v: String) -> String {
        v.replacingOccurrences(of: "_", with: " ")
    }
}
