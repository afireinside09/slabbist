import SwiftUI

struct GradeHistoryRow: View {
    let estimate: GradeEstimateDTO

    var body: some View {
        HStack(spacing: Spacing.m) {
            AsyncGradePhoto(path: estimate.frontThumbPath)
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text("PSA")
                        .font(SlabFont.sans(size: 11, weight: .medium))
                        .tracking(1.6)
                        .foregroundStyle(AppColor.dim)
                    Text(formatted(estimate.compositeGrade))
                        .font(SlabFont.serif(size: 24))
                        .tracking(-0.4)
                        .foregroundStyle(AppColor.text)
                }
                Text(verdictLabel(estimate.verdict))
                    .font(SlabFont.sans(size: 12))
                    .foregroundStyle(AppColor.muted)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                if estimate.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.gold)
                        .accessibilityLabel("Starred")
                }
                Text(estimate.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(SlabFont.mono(size: 11))
                    .foregroundStyle(AppColor.dim)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "PSA \(formatted(estimate.compositeGrade)), \(verdictLabel(estimate.verdict)), \(estimate.createdAt.formatted(date: .abbreviated, time: .omitted))"
        )
    }

    private func formatted(_ s: Double) -> String {
        s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s)
    }

    private func verdictLabel(_ v: String) -> String {
        v.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
