import SwiftUI
import UIKit

/// The reusable manual centering editor. Used both as a correction step in
/// the pre-grade capture flow and as the standalone tool. It owns its
/// `CenteringEditorModel` and hands the measured `CenteringRatios` back via
/// `onConfirm` — it does not persist anything itself.
struct CenteringEditorView: View {
    @State private var model: CenteringEditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let confirmLabel: String
    let onConfirm: (CenteringRatios) -> Void
    let onCancel: (() -> Void)?

    init(
        image: UIImage,
        guides: CenteringGuides,
        title: String = "Adjust centering",
        confirmLabel: String = "Use this centering",
        onConfirm: @escaping (CenteringRatios) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        _model = State(initialValue: CenteringEditorModel(image: image, guides: guides))
        self.title = title
        self.confirmLabel = confirmLabel
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: Spacing.m) {
            header
            CenteringImageCanvas(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                .overlay(alignment: .top) {
                    if model.eyedropperActive { eyedropperHint }
                }
            CenteringReadoutView(ratios: model.ratios)
            CenteringToolbar(model: model)
            actions
        }
        .padding(Spacing.l)
        .background(AppColor.ink.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: model.activeHandle)
        .sensoryFeedback(.levelChange, trigger: model.filter)
    }

    private var header: some View {
        HStack {
            Text(title).slabTitle()
            Spacer()
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { model.reset() }
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(SlabFont.sans(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.muted)
            }
            .accessibilityLabel("Reset guides")
        }
    }

    private var eyedropperHint: some View {
        Text("Tap the inner frame edge to snap the nearest guide")
            .font(SlabFont.sans(size: 12, weight: .medium))
            .foregroundStyle(AppColor.text)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(Capsule().fill(AppColor.ink.opacity(0.85)))
            .padding(.top, Spacing.s)
    }

    private var actions: some View {
        HStack(spacing: Spacing.m) {
            if let onCancel {
                SecondaryButton(title: "Retake", action: onCancel)
            }
            PrimaryGoldButton(title: confirmLabel) { onConfirm(model.ratios) }
        }
    }
}
