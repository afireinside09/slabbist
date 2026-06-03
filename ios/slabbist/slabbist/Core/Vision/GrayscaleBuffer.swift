import CoreGraphics

/// A downscaled, single-channel (8-bit) grayscale view of an image. Every
/// capture-quality metric consumes one of these so the metrics stay pure and
/// fully unit-testable (tests build buffers from raw pixel arrays).
struct GrayscaleBuffer: Equatable {
    let width: Int
    let height: Int
    let pixels: [UInt8]   // row-major, one byte per pixel

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Draws `cgImage` into a device-gray context no larger than
    /// `maxDimension` on its longest side. Returns nil if the context can't
    /// be created.
    init?(cgImage: CGImage, maxDimension: Int) {
        let srcW = cgImage.width, srcH = cgImage.height
        guard srcW > 0, srcH > 0, maxDimension > 0 else { return nil }
        let scale = min(1.0, Double(maxDimension) / Double(max(srcW, srcH)))
        let w = max(1, Int((Double(srcW) * scale).rounded()))
        let h = max(1, Int((Double(srcH) * scale).rounded()))
        var data = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &data,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        self.init(width: w, height: h, pixels: data)
    }
}
