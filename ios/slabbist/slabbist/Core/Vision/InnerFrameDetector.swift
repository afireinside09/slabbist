import UIKit
import CoreGraphics

/// Seeds and refines the four *inner* frame guides. The outer guides come
/// from `CardRectangleDetector` (the card edge Vision finds reliably); the
/// inner frame edge is harder, so we start from a default border inset and
/// let the user refine by drag or by the eyedropper, which scans for the
/// sampled frame color.
enum InnerFrameDetector {
    /// Inner guides at a default border fraction of the card span inside the
    /// outer guides. Always valid — the guaranteed fallback when nothing
    /// smarter is available.
    static func bestGuess(outer: CenteringGuides, borderFraction: Double = 0.065) -> CenteringGuides {
        var g = outer
        let wSpan = max(0, outer.outerRight - outer.outerLeft)
        let hSpan = max(0, outer.outerBottom - outer.outerTop)
        g.innerLeft = outer.outerLeft + wSpan * borderFraction
        g.innerRight = outer.outerRight - wSpan * borderFraction
        g.innerTop = outer.outerTop + hSpan * borderFraction
        g.innerBottom = outer.outerBottom - hSpan * borderFraction
        return CenteringGuideMath.clamped(g)
    }

    /// A centered card-aspect outer rect for when detection fails entirely —
    /// the manual-first fallback so the editor always opens on something.
    static func centeredFallback() -> CenteringGuides { .centeredDefault }

    /// Eyedropper: sample the color at `normPoint`, pick the inner guide
    /// nearest the tap, and snap it to the first pixel along that axis (scanning
    /// inward from the outer edge) whose color matches the sample. Returns the
    /// guides unchanged if no confident match is found.
    static func snapInner(toColorAt normPoint: CGPoint, in image: UIImage, guides: CenteringGuides) -> CenteringGuides {
        guard let grid = PixelGrid(image: image) else { return guides }
        let target = grid.color(normX: normPoint.x, normY: normPoint.y)

        let candidates: [(GuideEdge, Double)] = [
            (.innerLeft, abs(normPoint.x - guides.innerLeft)),
            (.innerRight, abs(normPoint.x - guides.innerRight)),
            (.innerTop, abs(normPoint.y - guides.innerTop)),
            (.innerBottom, abs(normPoint.y - guides.innerBottom))
        ]
        guard let edge = candidates.min(by: { $0.1 < $1.1 })?.0 else { return guides }

        guard let snapped = scan(edge: edge, target: target, grid: grid, guides: guides) else {
            return guides
        }
        return CenteringGuideMath.moving(guides, edge, to: snapped)
    }

    /// Scan ~64 samples from the outer edge toward the card center along the
    /// guide's axis (at the cross-center), returning the first normalized
    /// position whose color matches `target`.
    private static func scan(edge: GuideEdge, target: PixelGrid.RGB, grid: PixelGrid, guides: CenteringGuides) -> Double? {
        let steps = 64
        let crossY = (guides.outerTop + guides.outerBottom) / 2
        let crossX = (guides.outerLeft + guides.outerRight) / 2

        let (from, to): (Double, Double)
        switch edge {
        case .innerLeft: (from, to) = (guides.outerLeft, crossX)
        case .innerRight: (from, to) = (guides.outerRight, crossX)
        case .innerTop: (from, to) = (guides.outerTop, crossY)
        case .innerBottom: (from, to) = (guides.outerBottom, crossY)
        default: return nil
        }

        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let pos = from + (to - from) * t
            let color: PixelGrid.RGB = edge.isVertical
                ? grid.color(normX: pos, normY: crossY)
                : grid.color(normX: crossX, normY: pos)
            if color.distance(to: target) < 0.12 { return pos }
        }
        return nil
    }
}

/// Minimal RGBA8 pixel reader over a `UIImage`'s `CGImage`. Built once per
/// eyedropper tap, never on a gesture hot path.
struct PixelGrid {
    struct RGB { var r, g, b: Double
        func distance(to o: RGB) -> Double {
            let dr = r - o.r, dg = g - o.g, db = b - o.b
            return (dr * dr + dg * dg + db * db).squareRoot()
        }
    }

    private let width: Int
    private let height: Int
    private let bytes: [UInt8]
    private let bytesPerRow: Int

    init?(image: UIImage) {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        let bpr = w * 4
        var data = [UInt8](repeating: 0, count: bpr * h)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bpr, space: space, bitmapInfo: info) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        self.width = w; self.height = h; self.bytes = data; self.bytesPerRow = bpr
    }

    func color(normX: Double, normY: Double) -> RGB {
        let x = min(max(Int(normX * Double(width)), 0), width - 1)
        let y = min(max(Int(normY * Double(height)), 0), height - 1)
        let i = y * bytesPerRow + x * 4
        return RGB(r: Double(bytes[i]) / 255, g: Double(bytes[i + 1]) / 255, b: Double(bytes[i + 2]) / 255)
    }
}
