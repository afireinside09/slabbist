import CoreGraphics
import SwiftUI

/// Pure mapping between the three coordinate spaces the centering editor
/// uses: normalized image space (`0...1`), the aspect-fit letterbox inside
/// the view, and screen points after the zoom / pan / rotation the canvas
/// applies. It exists so hit-testing, drag→delta conversion, and loupe
/// sampling can be reasoned about (and unit-tested) without any SwiftUI.
///
/// The canvas applies the equivalent SwiftUI render transform
/// (`.rotationEffect(_, anchor: .center).scaleEffect(zoom).offset(pan)`) to
/// the image and the guide overlay together, so guides are not transformed
/// per-handle in code — this type only converts points and deltas.
nonisolated struct CenteringTransform: Equatable {
    var imagePixelSize: CGSize
    var viewSize: CGSize
    var zoom: CGFloat
    var pan: CGSize
    var rotation: Angle

    init(imagePixelSize: CGSize, viewSize: CGSize, zoom: CGFloat = 1, pan: CGSize = .zero, rotation: Angle = .zero) {
        self.imagePixelSize = imagePixelSize
        self.viewSize = viewSize
        self.zoom = zoom
        self.pan = pan
        self.rotation = rotation
    }

    /// The image aspect-fit into the view, before zoom/pan/rotation.
    var fitRect: CGRect {
        let iw = imagePixelSize.width, ih = imagePixelSize.height
        guard iw > 0, ih > 0, viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let scale = min(viewSize.width / iw, viewSize.height / ih)
        let w = iw * scale, h = ih * scale
        return CGRect(x: (viewSize.width - w) / 2, y: (viewSize.height - h) / 2, width: w, height: h)
    }

    private var center: CGPoint { CGPoint(x: fitRect.midX, y: fitRect.midY) }

    /// Normalized image point (`0...1`) → screen point.
    func screenPoint(normX: Double, normY: Double) -> CGPoint {
        let r = fitRect
        let p0 = CGPoint(x: r.minX + CGFloat(normX) * r.width,
                         y: r.minY + CGFloat(normY) * r.height)
        let c = center
        var v = CGVector(dx: p0.x - c.x, dy: p0.y - c.y)
        v = rotate(v, by: rotation.radians)
        v.dx *= zoom; v.dy *= zoom
        return CGPoint(x: c.x + v.dx + pan.width, y: c.y + v.dy + pan.height)
    }

    /// Screen point → normalized image point (`0...1`). Exact inverse of
    /// `screenPoint(normX:normY:)`.
    func normalized(screenPoint p: CGPoint) -> CGPoint {
        let r = fitRect
        guard r.width > 0, r.height > 0 else { return .zero }
        let c = center
        var v = CGVector(dx: p.x - pan.width - c.x, dy: p.y - pan.height - c.y)
        v.dx /= zoom; v.dy /= zoom
        v = rotate(v, by: -rotation.radians)
        let p0 = CGPoint(x: c.x + v.dx, y: c.y + v.dy)
        return CGPoint(x: (p0.x - r.minX) / r.width, y: (p0.y - r.minY) / r.height)
    }

    /// A screen-space drag translation → normalized image-space delta on
    /// each axis (un-scaled and un-rotated). A vertical guide line uses
    /// `.dx`; a horizontal guide line uses `.dy`.
    func imageDelta(screenTranslation t: CGSize) -> CGVector {
        let r = fitRect
        guard r.width > 0, r.height > 0, zoom > 0 else { return .zero }
        var v = CGVector(dx: t.width / zoom, dy: t.height / zoom)
        v = rotate(v, by: -rotation.radians)
        return CGVector(dx: v.dx / r.width, dy: v.dy / r.height)
    }

    private func rotate(_ v: CGVector, by radians: Double) -> CGVector {
        let c = CGFloat(cos(radians)), s = CGFloat(sin(radians))
        return CGVector(dx: v.dx * c - v.dy * s, dy: v.dx * s + v.dy * c)
    }
}
