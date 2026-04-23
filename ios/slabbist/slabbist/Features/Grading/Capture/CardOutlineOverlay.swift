import SwiftUI

struct CardOutlineOverlay: View {
    let aligned: Bool

    var body: some View {
        GeometryReader { proxy in
            let cardSize = trumpCardSize(in: proxy.size)
            let rect = CGRect(
                x: (proxy.size.width - cardSize.width) / 2,
                y: (proxy.size.height - cardSize.height) / 2,
                width: cardSize.width,
                height: cardSize.height
            )
            ZStack {
                Color.black.opacity(0.45)
                    .mask {
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .frame(width: rect.width, height: rect.height)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    }
                RoundedRectangle(cornerRadius: 14)
                    .stroke(aligned ? AppColor.gold : Color.white.opacity(0.6), lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func trumpCardSize(in container: CGSize) -> CGSize {
        let aspect: CGFloat = 0.71428  // standard trading card aspect (2.5x3.5)
        let maxW = container.width * 0.78
        let maxH = container.height * 0.72
        if maxW / aspect <= maxH {
            return CGSize(width: maxW, height: maxW / aspect)
        }
        return CGSize(width: maxH * aspect, height: maxH)
    }
}
