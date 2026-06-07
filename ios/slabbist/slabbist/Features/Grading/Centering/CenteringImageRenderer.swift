import UIKit
import CoreImage

/// Image-enhancement filters that help the eye (and the user's finger) find
/// the inner frame edge against busy or holo artwork. Applied to the
/// *displayed* image only — never to the measurement, which is pure geometry.
nonisolated enum CenteringImageFilter: CaseIterable, Hashable, Sendable {
    case raw
    case invert
    case bw

    var label: String {
        switch self {
        case .raw: "Raw"
        case .invert: "Inv"
        case .bw: "B&W"
        }
    }
}

/// Renders a `CenteringImageFilter` over a `UIImage`. Holds one shared
/// `CIContext` (expensive to build) and is only ever invoked when the filter
/// selection changes — results are cached by the editor model, so gestures
/// never trigger Core Image work.
struct CenteringImageRenderer {
    static let shared = CenteringImageRenderer()
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func render(_ image: UIImage, _ filter: CenteringImageFilter) -> UIImage {
        guard filter != .raw, let input = CIImage(image: image) else { return image }

        let output: CIImage?
        switch filter {
        case .raw:
            output = input
        case .invert:
            output = input.applyingFilter("CIColorInvert")
        case .bw:
            output = input.applyingFilter("CIPhotoEffectMono")
        }

        guard let output, let cg = context.createCGImage(output, from: output.extent) else {
            return image
        }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}
