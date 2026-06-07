import SwiftUI

/// One draggable guide handle, drawn in *un-transformed* screen space so it
/// stays a constant, comfortably-tappable size regardless of zoom. It
/// positions itself at the screen projection of its line via the shared
/// `CenteringTransform`, and reports drag translations (measured in the
/// named canvas space) back to the model, which converts them to a guide
/// movement. A 44pt transparent hit area sits behind the visible dot.
struct CenteringHandle: View {
    let edge: GuideEdge
    let transform: CenteringTransform
    /// Current normalized position of this edge (drives the dot's location).
    let value: Double
    /// Where along the cross-axis to sit, so inner/outer dots don't overlap.
    let crossFraction: Double
    let isActive: Bool
    @Bindable var model: CenteringEditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var position: CGPoint {
        edge.isVertical
            ? transform.screenPoint(normX: value, normY: crossFraction)
            : transform.screenPoint(normX: crossFraction, normY: value)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? AppColor.gold : AppColor.elev2)
                .overlay(Circle().stroke(AppColor.gold, lineWidth: isActive ? 2 : 1.5))
                .frame(width: isActive ? 22 : 18, height: isActive ? 22 : 18)
                .shadow(color: AppColor.ink.opacity(0.5), radius: 3, y: 1)
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .position(position)
        .zIndex(isActive ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isActive)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(CenteringImageCanvas.coordinateSpace))
                .onChanged { v in
                    model.dragChanged(edge, translation: v.translation, transform: transform)
                }
                .onEnded { _ in model.endDrag() }
        )
        .accessibilityLabel(Self.label(for: edge))
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = 0.005
            let delta = direction == .increment ? step : -step
            model.guides = CenteringGuideMath.moving(model.guides, edge, to: value + delta)
        }
    }

    static func label(for edge: GuideEdge) -> String {
        switch edge {
        case .outerLeft: "Left card edge"
        case .innerLeft: "Left frame edge"
        case .innerRight: "Right frame edge"
        case .outerRight: "Right card edge"
        case .outerTop: "Top card edge"
        case .innerTop: "Top frame edge"
        case .innerBottom: "Bottom frame edge"
        case .outerBottom: "Bottom card edge"
        }
    }
}
