import SwiftUI

struct SubGradeCard: View {
    let title: String
    let score: Double
    let note: String
    let dataPoint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(formatted(score))
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(AppColor.gold)
            }
            Text(note)
                .font(.body)
                .foregroundStyle(.primary)
            if let dataPoint {
                Text(dataPoint)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(formatted(score)) out of 10")
    }

    private func formatted(_ s: Double) -> String {
        s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s)
    }
}
