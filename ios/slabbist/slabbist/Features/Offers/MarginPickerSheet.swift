import SwiftUI

struct MarginPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pct: Double
    let onSelect: (Double) -> Void

    init(currentPct: Double, onSelect: @escaping (Double) -> Void) {
        _pct = State(initialValue: currentPct)
        self.onSelect = onSelect
    }

    private static let snaps: [Double] = [0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00]

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                KickerLabel("Lot margin")
                Text("\(Int((pct * 100).rounded()))% of comp").slabTitle()
                // 7 snaps don't fit in a single HStack on smaller screens, so
                // use an adaptive grid that wraps. The accessibility id format
                // is preserved so existing UI tests targeting "margin-snap-70"
                // still hit the right button.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 56), spacing: Spacing.s)],
                    alignment: .leading,
                    spacing: Spacing.s
                ) {
                    ForEach(Self.snaps, id: \.self) { snap in
                        Button("\(Int(snap * 100))%") { pct = snap }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.s)
                            .background(snap == pct ? AppColor.gold.opacity(0.2) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColor.gold, lineWidth: snap == pct ? 1.5 : 0.5)
                            )
                            .accessibilityIdentifier("margin-snap-\(Int(snap * 100))")
                    }
                }
                Slider(value: $pct, in: 0.70...1.00, step: 0.01)
                    .accessibilityIdentifier("margin-slider")
                Spacer()
                PrimaryGoldButton(title: "Save margin") {
                    onSelect(pct)
                    dismiss()
                }
                .accessibilityIdentifier("margin-save")
            }
            .padding(.horizontal, Spacing.xxl).padding(.vertical, Spacing.l)
        }
    }
}
