import CoreGraphics

/// Fraction of pixels brighter than 250 within a normalized sub-rect
/// (`nil` = whole buffer). 1.0 means fully blown out. The capture gate's
/// `maxGlareRatio` (default 0.02) is the reject cut. Restricting to the card
/// rect keeps a bright background from tripping the check.
enum GlareMetric {
    static func overexposedRatio(_ buffer: GrayscaleBuffer, in rect: CGRect?) -> Double {
        let w = buffer.width, h = buffer.height
        guard w > 0, h > 0 else { return 0 }
        let r = rect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let x0 = max(0, Int((Double(r.minX) * Double(w)).rounded(.down)))
        let y0 = max(0, Int((Double(r.minY) * Double(h)).rounded(.down)))
        let x1 = min(w, Int((Double(r.maxX) * Double(w)).rounded(.up)))
        let y1 = min(h, Int((Double(r.maxY) * Double(h)).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return 0 }
        let p = buffer.pixels
        var blown = 0, total = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                if p[y * w + x] > 250 { blown += 1 }
                total += 1
            }
        }
        return total == 0 ? 0 : Double(blown) / Double(total)
    }
}
