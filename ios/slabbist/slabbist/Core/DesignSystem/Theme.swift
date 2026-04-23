import SwiftUI

/// Dark-ink root background for full-screen feature views. Edge-to-edge.
struct SlabbedRoot<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            AppColor.ink.ignoresSafeArea()
            content()
        }
    }
}

enum AmbientBlobPlacement {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

private struct AmbientGoldBlob: ViewModifier {
    let placement: AmbientBlobPlacement

    func body(content: Content) -> some View {
        ZStack {
            GeometryReader { proxy in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppColor.gold.opacity(0.24), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: proxy.size.width * 0.45
                        )
                    )
                    .frame(width: proxy.size.width * 0.9, height: proxy.size.width * 0.9)
                    .blur(radius: 40)
                    .position(center(in: proxy.size))
                    .allowsHitTesting(false)
            }
            content
        }
    }

    private func center(in size: CGSize) -> CGPoint {
        switch placement {
        case .topLeading:     return CGPoint(x: -size.width * 0.1, y: -size.width * 0.1)
        case .topTrailing:    return CGPoint(x: size.width * 1.1,  y: -size.width * 0.1)
        case .bottomLeading:  return CGPoint(x: -size.width * 0.1, y: size.height + size.width * 0.1)
        case .bottomTrailing: return CGPoint(x: size.width * 1.1,  y: size.height + size.width * 0.1)
        }
    }
}

extension View {
    /// Adds a soft, blurred gold radial highlight at a corner.
    /// Used on hero screens (AuthView, future onboarding).
    func ambientGoldBlob(_ placement: AmbientBlobPlacement) -> some View {
        modifier(AmbientGoldBlob(placement: placement))
    }
}
