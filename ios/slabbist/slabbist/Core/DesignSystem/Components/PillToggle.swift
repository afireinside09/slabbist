import SwiftUI

/// Horizontal pill with an inset selected segment.
/// Two visual styles: `.accent` (gold selection, mockup's camera-mode toggle)
/// and `.neutral` (elev2 selection, grid/list view toggle).
struct PillToggle<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var style: Style = .neutral

    enum Style {
        case accent
        case neutral
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(SlabFont.sans(size: 12, weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(foreground(for: option.value))
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.s)
                        .background(background(for: option.value))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                }
            }
        }
        .padding(4)
        .background(AppColor.elev)
        .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .stroke(AppColor.hairline, lineWidth: 1)
        )
    }

    private func foreground(for value: Value) -> Color {
        let selected = selection == value
        switch style {
        case .accent:  return selected ? AppColor.ink  : AppColor.text
        case .neutral: return selected ? AppColor.text : AppColor.dim
        }
    }

    private func background(for value: Value) -> Color {
        let selected = selection == value
        switch style {
        case .accent:  return selected ? AppColor.gold  : .clear
        case .neutral: return selected ? AppColor.elev2 : .clear
        }
    }
}

#Preview("PillToggle") {
    struct Demo: View {
        @State var mode: String = "ar"
        @State var view: String = "grid"
        var body: some View {
            VStack(spacing: Spacing.l) {
                PillToggle(
                    selection: $mode,
                    options: [("ar", "AR"), ("batch", "Batch")],
                    style: .accent
                )
                PillToggle(
                    selection: $view,
                    options: [("grid", "Grid"), ("list", "List")],
                    style: .neutral
                )
            }
            .padding()
            .background(AppColor.ink)
        }
    }
    return Demo()
}
