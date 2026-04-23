import SwiftUI

/// Capture mark — scanner brackets cradling a swash-italic S with a thin scan line.
/// Matches the HTML design at `docs/design/logo/Slabbist Logo.html` (mark #4).
///
/// The view draws at any size; internal dimensions are scaled from the mockup's
/// 200×200 canvas so proportions stay true at App-Store-icon size (1024) down
/// to a 14-pt favicon. The background fills the full frame (no corner mask —
/// iOS applies the icon superellipse itself; callers that want a rounded chip
/// in-app should wrap in `.clipShape(RoundedRectangle(...))`).
struct SlabbistLogo: View {
    let size: CGFloat

    init(size: CGFloat) {
        self.size = size
    }

    var body: some View {
        ZStack {
            background
            scanLine
            CaptureBrackets()
                .stroke(goldGradient, style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round, lineJoin: .round))
            centeredS
        }
        .frame(width: size, height: size)
    }

    // MARK: - Layers

    private var background: some View {
        LinearGradient(
            colors: [Color(hex: 0x1A1A1F), AppColor.ink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var scanLine: some View {
        ZStack {
            Capsule()
                .fill(goldGradient.opacity(0.12))
                .frame(width: size * 0.64, height: size * 0.03)
                .offset(y: size * (100.0 / 200.0 - 0.5))
            Capsule()
                .fill(goldGradient.opacity(0.45))
                .frame(width: size * 0.64, height: size * 0.01)
                .offset(y: size * (100.0 / 200.0 - 0.5))
        }
    }

    private var centeredS: some View {
        // Font size 128 on a 200 canvas = 0.64 of the frame. SwiftUI's `.custom`
        // falls back to `.serif` design if the file is missing, so the mark stays
        // readable even before the bundle is registered.
        Text("S")
            .font(.custom("InstrumentSerif-Italic", size: size * 0.64))
            .tracking(-size * 0.015)
            .foregroundStyle(AppColor.text)
    }

    private var goldGradient: LinearGradient {
        LinearGradient(
            colors: [AppColor.gold, AppColor.goldDim],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Four L-shaped corner brackets forming a reticle around the design center.
/// Coordinates taken directly from the mockup's 200×200 viewBox.
private struct CaptureBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 200.0
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x * s + rect.minX, y: y * s + rect.minY)
        }

        var path = Path()
        // Top-left: M 44 72 L 44 44 L 72 44
        path.move(to: pt(44, 72));  path.addLine(to: pt(44, 44));  path.addLine(to: pt(72, 44))
        // Top-right: M 128 44 L 156 44 L 156 72
        path.move(to: pt(128, 44)); path.addLine(to: pt(156, 44)); path.addLine(to: pt(156, 72))
        // Bottom-right: M 156 128 L 156 156 L 128 156
        path.move(to: pt(156, 128)); path.addLine(to: pt(156, 156)); path.addLine(to: pt(128, 156))
        // Bottom-left: M 72 156 L 44 156 L 44 128
        path.move(to: pt(72, 156)); path.addLine(to: pt(44, 156)); path.addLine(to: pt(44, 128))
        return path
    }
}

#Preview("SlabbistLogo — size ladder") {
    VStack(spacing: 24) {
        HStack(spacing: 32) {
            ForEach([24.0, 48.0, 88.0, 168.0], id: \.self) { s in
                SlabbistLogo(size: s)
                    .clipShape(RoundedRectangle(cornerRadius: s * 0.22, style: .continuous))
            }
        }
        SlabbistLogo(size: 240)
            .clipShape(RoundedRectangle(cornerRadius: 240 * 0.22, style: .continuous))
    }
    .padding(40)
    .background(AppColor.surface)
}
