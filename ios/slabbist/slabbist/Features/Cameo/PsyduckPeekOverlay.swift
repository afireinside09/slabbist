import SwiftUI

/// The easter egg: a Psyduck that peeks in from the trailing edge (lower third)
/// of every screen. Only the duck is hit-testable; everything else passes touches
/// through. Tapping fires `onTap`. Half its width sits off-screen.
struct PsyduckPeekOverlay: View {
    var onTap: () -> Void
    private let size: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            Image("Psyduck")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .accessibilityLabel("A curious Psyduck")
                .accessibilityHint("Opens a hidden screen")
                .position(
                    x: geo.size.width - size / 2 + 14,           // ~half off the trailing edge
                    y: geo.size.height * 0.66                     // lower third
                )
        }
        .allowsHitTesting(true)
        .ignoresSafeArea()
    }
}
