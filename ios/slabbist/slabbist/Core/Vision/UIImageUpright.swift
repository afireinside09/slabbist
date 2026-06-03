import UIKit

extension UIImage {
    /// Returns a CGImage in upright (`.up`) orientation. `AVCapturePhotoOutput`
    /// stills are sensor-landscape tagged `.right`, whose raw `cgImage` is
    /// landscape while `size` is the orientation-corrected portrait. Vision and
    /// the on-device metrics need a single upright pixel space, so redraw when
    /// the orientation isn't already `.up`. No-op (returns `cgImage`) when it is.
    func uprightCGImage() -> CGImage? {
        if imageOrientation == .up { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return normalized.cgImage
    }
}
