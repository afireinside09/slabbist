import SwiftUI

struct OtherGradersPanel: View {
    let bundle: OtherGradersBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Other graders")
                .font(.headline)
            row("BGS", report: bundle.bgs)
            row("CGC", report: bundle.cgc)
            row("SGC", report: bundle.sgc)
            Text("These predictions use the same sub-grades with adjusted composite math, not separately calibrated models.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func row(_ name: String, report: PerGraderReport) -> some View {
        HStack {
            Text(name).bold().frame(width: 48, alignment: .leading)
            Text(String(format: "%.1f", report.compositeGrade))
                .font(.title3.bold())
                .foregroundStyle(AppColor.gold)
            Spacer()
            Text(report.verdict).font(.caption).foregroundStyle(.secondary)
        }
    }
}
