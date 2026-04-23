import SwiftUI

struct GradeHistoryRow: View {
    let estimate: GradeEstimateDTO

    var body: some View {
        HStack(spacing: 12) {
            AsyncGradePhoto(path: estimate.frontThumbPath)
                .frame(width: 44, height: 62)
            VStack(alignment: .leading, spacing: 4) {
                Text("PSA \(formatted(estimate.compositeGrade))")
                    .font(.headline)
                Text(verdictLabel(estimate.verdict))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if estimate.isStarred {
                Image(systemName: "star.fill")
                    .foregroundStyle(AppColor.gold)
                    .accessibilityLabel("Starred")
            }
            Text(estimate.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)
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
