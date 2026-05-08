import SwiftUI

struct SubGradeCard: View {
    let title: String
    let score: Double
    let note: String
    let dataPoint: String?

    var body: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).slabRowTitle()
                    Spacer()
                    Text(formatted(score))
                        .font(SlabFont.serif(size: 28))
                        .tracking(-0.6)
                        .foregroundStyle(AppColor.text)
                }
                Text(note)
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let dataPoint {
                    Text(dataPoint)
                        .font(SlabFont.mono(size: 11))
                        .foregroundStyle(AppColor.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.l)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(formatted(score)) out of 10")
    }

    private func formatted(_ s: Double) -> String {
        s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s)
    }
}
