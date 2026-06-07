import SwiftUI
import UIKit

/// Circular magnifier that shows the image region under the active handle so
/// the user can place a guide on the exact border pixel. Pure presentation —
/// it takes the normalized point to magnify and renders a zoomed crop.
struct CenteringLoupeView: View {
    let image: UIImage
    /// The normalized image point (`0...1`) to center under the crosshair.
    let normPoint: CGPoint
    /// On-screen fitted size of the image, so magnification is relative to
    /// what the user currently sees.
    let fitSize: CGSize
    var diameter: CGFloat = 116
    var magnification: CGFloat = 2.5

    var body: some View {
        let contentW = fitSize.width * magnification
        let contentH = fitSize.height * magnification
        let px = normPoint.x * contentW
        let py = normPoint.y * contentH

        ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: contentW, height: contentH)
                .offset(x: contentW / 2 - px, y: contentH / 2 - py)
            Rectangle().fill(AppColor.gold.opacity(0.9)).frame(width: 1, height: diameter)
            Rectangle().fill(AppColor.gold.opacity(0.9)).frame(width: diameter, height: 1)
        }
        .frame(width: diameter, height: diameter)
        .background(AppColor.ink)
        .clipShape(Circle())
        .overlay(Circle().stroke(AppColor.gold, lineWidth: 2))
        .shadow(color: AppColor.ink.opacity(0.6), radius: 8, y: 3)
        .allowsHitTesting(false)
    }
}
