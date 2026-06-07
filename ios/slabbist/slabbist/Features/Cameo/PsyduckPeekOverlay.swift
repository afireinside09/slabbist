import SwiftUI

/// The easter egg: a Psyduck that periodically peeks in from a random edge
/// (leading or trailing) at a random height, lingers a few seconds, then slips
/// back out the way it came — repeating on a loose timer. It starts hidden, so
/// it only appears a few seconds after a screen is shown. Only the duck is
/// hit-testable, and only while it's peeking; everything else passes touches
/// through. Tapping fires `onTap`.
struct PsyduckPeekOverlay: View {
    var onTap: () -> Void
    private let size: CGFloat = 64

    @State private var edge: HorizontalEdge = .trailing
    @State private var verticalFraction: CGFloat = 0.66
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            Image("Psyduck")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(x: edge == .leading ? -1 : 1, y: 1)   // face inward from either side
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .accessibilityLabel("A curious Psyduck")
                .accessibilityHint("Opens a hidden screen")
                .position(
                    x: xPosition(in: geo.size.width),
                    y: geo.size.height * verticalFraction
                )
        }
        .allowsHitTesting(revealed)
        .ignoresSafeArea()
        .task { await runPeekLoop() }
    }

    /// Half-peeking when revealed; fully off-screen past the same edge when hidden.
    private func xPosition(in width: CGFloat) -> CGFloat {
        switch (edge, revealed) {
        case (.trailing, true):  return width - size / 2 + 14
        case (.trailing, false): return width + size / 2 + 4
        case (.leading, true):   return size / 2 - 14
        case (.leading, false):  return -size / 2 - 4
        }
    }

    private func runPeekLoop() async {
        while !Task.isCancelled {
            // Stay hidden for a few seconds between appearances.
            try? await Task.sleep(for: .seconds(Double.random(in: 4...9)))
            if Task.isCancelled { return }

            // Pick a fresh random spot while still off-screen.
            edge = Bool.random() ? .leading : .trailing
            verticalFraction = CGFloat.random(in: 0.22...0.78)

            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.72)) {
                revealed = true
            }

            // Linger in view for a few seconds.
            try? await Task.sleep(for: .seconds(Double.random(in: 3...5)))
            if Task.isCancelled { return }

            // Slip back out the way it came in.
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.4)) {
                revealed = false
            }
        }
    }
}
