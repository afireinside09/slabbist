import SwiftUI

/// A one-shot celebratory wash shown the first time the hidden Cameo Dex is
/// opened: a gold light-sweep with a scatter of sparkles and a success haptic,
/// which then fades to reveal the dex underneath. Calls `onComplete` once it has
/// played. Honors Reduce Motion by skipping the sweep/sparkles — the haptic and
/// `onComplete` still fire, so the reveal never stalls.
struct CameoDiscoveryShimmer: View {
    var onComplete: () -> Void

    @State private var fired = false   // drives the success haptic
    @State private var sweep = false   // light band travels across + fades
    @State private var bloom = false   // sparkles grow and fade out
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sparkleCount = 16

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AppColor.ink.opacity(0.94)

                if !reduceMotion {
                    sweepBand(in: geo.size)
                    ForEach(0..<sparkleCount, id: \.self) { i in
                        sparkle(index: i, in: geo.size)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .sensoryFeedback(.success, trigger: fired)
        .accessibilityHidden(true)
        .task { await play() }
    }

    private func sweepBand(in size: CGSize) -> some View {
        LinearGradient(
            colors: [.clear, AppColor.gold.opacity(0.5), .white.opacity(0.7), AppColor.gold.opacity(0.5), .clear],
            startPoint: .top, endPoint: .bottom
        )
        .frame(width: size.width * 0.5)
        .rotationEffect(.degrees(20))
        .blendMode(.screen)
        .offset(x: sweep ? size.width * 0.95 : -size.width * 0.95)
        .opacity(sweep ? 0 : 1)
    }

    private func sparkle(index i: Int, in size: CGSize) -> some View {
        // Deterministic golden-ratio scatter — no RNG, so positions are stable.
        let fx = fract(Double(i) * 0.6180339887 + 0.07)
        let fy = fract(Double(i) * 0.3247179572 + 0.11)
        let glyph = 8.0 + Double(i % 4) * 5.0
        return Image(systemName: "sparkle")
            .font(.system(size: glyph))
            .foregroundStyle(AppColor.gold)
            .position(x: size.width * fx, y: size.height * fy)
            .scaleEffect(bloom ? 1 : 0.1)
            .opacity(bloom ? 0 : 1)
    }

    private func play() async {
        fired = true
        guard !reduceMotion else {
            try? await Task.sleep(for: .milliseconds(250))
            onComplete()
            return
        }
        withAnimation(.easeOut(duration: 0.55)) { sweep = true }
        withAnimation(.easeOut(duration: 0.7)) { bloom = true }
        try? await Task.sleep(for: .milliseconds(750))
        onComplete()
    }

    private func fract(_ x: Double) -> Double { x - x.rounded(.down) }
}
