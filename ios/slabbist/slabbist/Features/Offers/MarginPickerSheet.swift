import SwiftUI

struct MarginPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pct: Double
    let onSelect: (Double) -> Void

    init(currentPct: Double, onSelect: @escaping (Double) -> Void) {
        _pct = State(initialValue: currentPct)
        self.onSelect = onSelect
    }

    private static let snaps: [Double] = [0.50, 0.55, 0.60, 0.65, 0.70]

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                KickerLabel("Lot margin")
                Text("\(Int((pct * 100).rounded()))% of comp").slabTitle()
                HStack(spacing: Spacing.s) {
                    ForEach(Self.snaps, id: \.self) { snap in
                        Button("\(Int(snap * 100))%") { pct = snap }
                            .buttonStyle(.plain)
                            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
                            .background(snap == pct ? AppColor.gold.opacity(0.2) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColor.gold, lineWidth: snap == pct ? 1.5 : 0.5)
                            )
                            .accessibilityIdentifier("margin-snap-\(Int(snap * 100))")
                    }
                }
                Slider(value: $pct, in: 0...1, step: 0.01)
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
