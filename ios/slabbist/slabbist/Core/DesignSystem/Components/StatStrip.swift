import SwiftUI

/// Horizontal 3-or-more-cell metric strip divided by vertical hairlines.
struct StatStrip: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var valueTint: Color = AppColor.text
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(AppColor.hairline)
                        .frame(width: 1)
                }
                VStack(spacing: Spacing.xs) {
                    Text(item.value)
                        .font(SlabFont.mono(size: 18, weight: .medium))
                        .tracking(-0.3)
                        .foregroundStyle(item.valueTint)
                    Text(item.label.uppercased())
                        .font(SlabFont.sans(size: 10, weight: .medium))
                        .tracking(1.4)
                        .foregroundStyle(AppColor.dim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
            }
        }
    }
}

#Preview("StatStrip") {
    VStack {
        StatStrip(items: [
            .init(label: "Cards", value: "342"),
            .init(label: "Est. value", value: "$12.4k"),
            .init(label: "30 days", value: "+4.1%", valueTint: AppColor.positive),
        ])
    }
    .padding()
    .background(AppColor.elev)
}
