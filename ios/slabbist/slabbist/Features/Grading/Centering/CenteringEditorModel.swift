import SwiftUI
import Observation
import UIKit

/// Single source of truth for the centering editor. Owns the eight guide
/// lines (the measurement), the view transform (zoom/pan/rotation — display
/// only), and the current filter. The measured `ratios` is a *computed*
/// value derived from the guides, so it stays in sync for free and is never
/// affected by how the image is displayed.
@MainActor
@Observable
final class CenteringEditorModel {
    var guides: CenteringGuides
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    var rotation: Angle = .zero
    var filter: CenteringImageFilter = .raw
    /// The handle currently being dragged — drives the loupe and the
    /// active-handle highlight. `nil` when idle.
    var activeHandle: GuideEdge?
    var eyedropperActive = false

    /// The seed the user started from, so Reset can restore it.
    @ObservationIgnored private let seedGuides: CenteringGuides
    @ObservationIgnored let baseImage: UIImage
    @ObservationIgnored private var filteredCache: [CenteringImageFilter: UIImage] = [:]
    @ObservationIgnored private var dragStartValue: Double = 0

    init(image: UIImage, guides: CenteringGuides) {
        let clamped = CenteringGuideMath.clamped(guides)
        self.baseImage = image
        self.guides = clamped
        self.seedGuides = clamped
    }

    /// Upright pixel dimensions of the image — the space the guides and the
    /// `CenteringTransform` are anchored to.
    var imagePixelSize: CGSize {
        CGSize(width: baseImage.size.width * baseImage.scale,
               height: baseImage.size.height * baseImage.scale)
    }

    /// The measured centering, ready to hand to the grade estimate.
    var ratios: CenteringRatios { CenteringGuideMath.ratios(from: guides) }

    /// The image to render, with the active filter applied and cached. Pure
    /// `.raw` returns the original untouched.
    func displayImage() -> UIImage {
        guard filter != .raw else { return baseImage }
        if let cached = filteredCache[filter] { return cached }
        let rendered = CenteringImageRenderer.shared.render(baseImage, filter)
        filteredCache[filter] = rendered
        return rendered
    }

    // MARK: - Drag

    /// Apply a drag translation (in canvas screen space) to one guide. The
    /// first change of a drag snapshots the start value so the translation —
    /// which is cumulative from the drag's origin — maps to an absolute
    /// position rather than accumulating.
    func dragChanged(_ edge: GuideEdge, translation: CGSize, transform: CenteringTransform) {
        if activeHandle != edge {
            dragStartValue = guides[edge]
            activeHandle = edge
        }
        let delta = transform.imageDelta(screenTranslation: translation)
        let d = edge.isVertical ? delta.dx : delta.dy
        guides = CenteringGuideMath.moving(guides, edge, to: dragStartValue + Double(d))
    }

    func endDrag() { activeHandle = nil }

    /// The normalized point of the active handle, for positioning the loupe.
    var activeHandlePoint: CGPoint? {
        guard let edge = activeHandle else { return nil }
        let v = guides[edge]
        return edge.isVertical ? CGPoint(x: v, y: 0.5) : CGPoint(x: 0.5, y: v)
    }

    // MARK: - Eyedropper

    /// Sample the frame color at a tapped point and snap the nearest inner
    /// guide to it. Reads pixels once — never on a gesture path.
    func applyEyedropper(at normPoint: CGPoint) {
        guides = InnerFrameDetector.snapInner(toColorAt: normPoint, in: baseImage, guides: guides)
        eyedropperActive = false
    }

    // MARK: - Transform gestures

    func clampZoom(_ proposed: CGFloat) -> CGFloat { min(max(proposed, 1), 6) }
    func clampRotation(_ proposed: Angle) -> Angle {
        Angle(degrees: min(max(proposed.degrees, -5), 5))
    }

    func reset() {
        guides = seedGuides
        zoom = 1
        pan = .zero
        rotation = .zero
        filter = .raw
        eyedropperActive = false
    }
}
