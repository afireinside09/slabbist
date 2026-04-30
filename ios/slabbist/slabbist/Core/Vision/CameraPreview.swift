import SwiftUI
import AVFoundation
import UIKit

/// SwiftUI wrapper around an `AVCaptureVideoPreviewLayer`. Used by any
/// feature that needs a live camera preview (bulk scan, grading capture).
///
/// Optionally calls `onPreviewLayer` once the preview layer is ready so
/// callers can use `layerRectConverted(fromMetadataOutputRect:)` to map
/// Vision detection rects from buffer coords into screen space.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onPreviewLayer: ((AVCaptureVideoPreviewLayer) -> Void)? = nil

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        onPreviewLayer?(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
