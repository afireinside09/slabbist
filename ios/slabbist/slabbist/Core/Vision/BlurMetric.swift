import Foundation

/// Sharpness via the variance of the 3×3 Laplacian response. Higher = sharper;
/// flat / out-of-focus images approach 0. The capture gate's `minBlurScore`
/// (default 100) is the accept/reject cut.
enum BlurMetric {
    static func laplacianVariance(_ buffer: GrayscaleBuffer) -> Double {
        let w = buffer.width, h = buffer.height
        guard w >= 3, h >= 3 else { return 0 }
        let p = buffer.pixels
        var responses = [Double]()
        responses.reserveCapacity((w - 2) * (h - 2))
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = Double(p[y * w + x])
                let up = Double(p[(y - 1) * w + x])
                let down = Double(p[(y + 1) * w + x])
                let left = Double(p[y * w + (x - 1)])
                let right = Double(p[y * w + (x + 1)])
                responses.append(up + down + left + right - 4 * c)
            }
        }
        guard !responses.isEmpty else { return 0 }
        let mean = responses.reduce(0, +) / Double(responses.count)
        let varSum = responses.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return varSum / Double(responses.count)
    }
}
