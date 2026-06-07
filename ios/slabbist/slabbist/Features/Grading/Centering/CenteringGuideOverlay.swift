import SwiftUI

/// Draws the eight guide lines and the four shaded border bands in the
/// image's own (fit-rect) coordinate space. This view is placed *inside* the
/// canvas's transformed content so it tracks the image under zoom/pan/
/// rotation; it never handles touches (the handle layer above does).
struct CenteringGuideOverlay: View {
    let guides: CenteringGuides
    let size: CGSize

    private let outerColor = AppColor.muted
    private let innerColor = AppColor.gold

    var body: some View {
        ZStack {
            // Border bands — the measured strip between outer and inner.
            band(from: guides.outerLeft, to: guides.innerLeft, axis: .vertical)
            band(from: guides.innerRight, to: guides.outerRight, axis: .vertical)
            band(from: guides.outerTop, to: guides.innerTop, axis: .horizontal)
            band(from: guides.innerBottom, to: guides.outerBottom, axis: .horizontal)

            // Outer card-edge lines.
            line(at: guides.outerLeft, axis: .vertical, color: outerColor)
            line(at: guides.outerRight, axis: .vertical, color: outerColor)
            line(at: guides.outerTop, axis: .horizontal, color: outerColor)
            line(at: guides.outerBottom, axis: .horizontal, color: outerColor)

            // Inner frame-edge lines.
            line(at: guides.innerLeft, axis: .vertical, color: innerColor)
            line(at: guides.innerRight, axis: .vertical, color: innerColor)
            line(at: guides.innerTop, axis: .horizontal, color: innerColor)
            line(at: guides.innerBottom, axis: .horizontal, color: innerColor)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private enum Axis { case vertical, horizontal }

    @ViewBuilder
    private func line(at norm: Double, axis: Axis, color: Color) -> some View {
        let w: CGFloat = 1.5
        switch axis {
        case .vertical:
            Rectangle().fill(color)
                .frame(width: w, height: size.height)
                .position(x: CGFloat(norm) * size.width, y: size.height / 2)
        case .horizontal:
            Rectangle().fill(color)
                .frame(width: size.width, height: w)
                .position(x: size.width / 2, y: CGFloat(norm) * size.height)
        }
    }

    @ViewBuilder
    private func band(from a: Double, to b: Double, axis: Axis) -> some View {
        let lo = CGFloat(min(a, b)), hi = CGFloat(max(a, b))
        switch axis {
        case .vertical:
            let width = (hi - lo) * size.width
            Rectangle().fill(AppColor.gold.opacity(0.14))
                .frame(width: width, height: size.height)
                .position(x: (lo + hi) / 2 * size.width, y: size.height / 2)
        case .horizontal:
            let height = (hi - lo) * size.height
            Rectangle().fill(AppColor.gold.opacity(0.14))
                .frame(width: size.width, height: height)
                .position(x: size.width / 2, y: (lo + hi) / 2 * size.height)
        }
    }
}
