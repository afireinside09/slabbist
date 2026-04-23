import SwiftUI

/// Grouped container used for almost every row-list in the app.
/// Dark elev fill, hairline border, rounded corners. Callers handle
/// their own inner dividers (use `SlabCardDivider`).
struct SlabCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.elev)
            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .stroke(AppColor.hairline, lineWidth: 1)
            )
    }
}

/// Hairline divider for use between rows inside a `SlabCard`.
struct SlabCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColor.hairline)
            .frame(height: 1)
    }
}

#Preview("SlabCard") {
    VStack(spacing: Spacing.l) {
        SlabCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("First row").slabRowTitle()
                    Spacer()
                    Text("$1,284").slabMetric()
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
                SlabCardDivider()
                HStack {
                    Text("Second row").slabRowTitle()
                    Spacer()
                    Text("$342").slabMetric()
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
            }
        }
    }
    .padding()
    .background(AppColor.ink)
}
