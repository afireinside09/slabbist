import SwiftUI

/// The editor's bottom controls: image filter selector, a fine-rotation
/// slider to square a tilted card, an eyedropper toggle, and reset.
struct CenteringToolbar: View {
    @Bindable var model: CenteringEditorModel

    var body: some View {
        VStack(spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                ForEach(CenteringImageFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
                Spacer()
                Button {
                    model.eyedropperActive.toggle()
                } label: {
                    Image(systemName: "eyedropper")
                        .font(SlabFont.sans(size: 15, weight: .semibold))
                        .foregroundStyle(model.eyedropperActive ? AppColor.ink : AppColor.text)
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.s)
                                .fill(model.eyedropperActive ? AppColor.gold : AppColor.elev2)
                        )
                }
                .accessibilityLabel("Eyedropper")
                .accessibilityValue(model.eyedropperActive ? "On" : "Off")
            }

            HStack(spacing: Spacing.m) {
                Image(systemName: "rotate.left")
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.dim)
                Slider(value: rotationBinding, in: -5...5)
                    .tint(AppColor.gold)
                Image(systemName: "rotate.right")
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.dim)
                Text("\(model.rotation.degrees, specifier: "%.1f")°")
                    .font(SlabFont.mono(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.muted)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    private var rotationBinding: Binding<Double> {
        Binding(
            get: { model.rotation.degrees },
            set: { model.rotation = Angle(degrees: $0) }
        )
    }

    private func filterChip(_ filter: CenteringImageFilter) -> some View {
        let selected = model.filter == filter
        return Button {
            model.filter = filter
        } label: {
            Text(filter.label)
                .font(SlabFont.sans(size: 13, weight: .semibold))
                .foregroundStyle(selected ? AppColor.ink : AppColor.text)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: Radius.s)
                        .fill(selected ? AppColor.gold : AppColor.elev2)
                )
        }
        .accessibilityLabel("\(filter.label) filter")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
