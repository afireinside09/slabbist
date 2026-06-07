import SwiftUI

/// The interactive image surface: the card photo and guide overlay (drawn in
/// one transformed layer so they move together under zoom/pan/rotation), an
/// un-transformed layer of constant-size draggable handles, a loupe while
/// dragging, and the eyedropper tap target. Transform gestures commit live to
/// the model so the displayed transform and the handles stay in lockstep.
struct CenteringImageCanvas: View {
    @Bindable var model: CenteringEditorModel
    static let coordinateSpace = "centeringCanvas"

    @State private var zoomAnchor: CGFloat?
    @State private var rotationAnchor: Angle?
    @State private var panAnchor: CGSize?

    var body: some View {
        GeometryReader { proxy in
            let t = CenteringTransform(
                imagePixelSize: model.imagePixelSize, viewSize: proxy.size,
                zoom: model.zoom, pan: model.pan, rotation: model.rotation
            )
            let fit = t.fitRect

            ZStack {
                // Transformed content: image + guide overlay, moving as one.
                ZStack {
                    Image(uiImage: model.displayImage())
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                    CenteringGuideOverlay(guides: model.guides, size: fit.size)
                }
                .frame(width: fit.width, height: fit.height)
                .rotationEffect(model.rotation, anchor: .center)
                .scaleEffect(model.zoom, anchor: .center)
                .offset(model.pan)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .allowsHitTesting(false)

                // Constant-size draggable handles in screen space.
                ForEach(GuideEdge.allCases, id: \.self) { edge in
                    CenteringHandle(
                        edge: edge, transform: t, value: model.guides[edge],
                        crossFraction: edge.isInner ? 0.62 : 0.38,
                        isActive: model.activeHandle == edge, model: model
                    )
                }

                // Eyedropper tap target sits on top so a sample tap doesn't
                // grab a handle. Only present while the tool is armed.
                if model.eyedropperActive {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .named(Self.coordinateSpace)) { loc in
                            let n = t.normalized(screenPoint: loc)
                            model.applyEyedropper(at: CGPoint(x: clamp01(n.x), y: clamp01(n.y)))
                        }
                }

                if let p = model.activeHandlePoint {
                    CenteringLoupeView(image: model.displayImage(), normPoint: p, fitSize: fit.size)
                        .position(x: proxy.size.width / 2, y: 74)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .coordinateSpace(.named(Self.coordinateSpace))
            .gesture(panGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(rotateGesture)
            .clipped()
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if zoomAnchor == nil { zoomAnchor = model.zoom }
                model.zoom = model.clampZoom((zoomAnchor ?? 1) * v.magnification)
            }
            .onEnded { _ in zoomAnchor = nil }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { v in
                if rotationAnchor == nil { rotationAnchor = model.rotation }
                model.rotation = model.clampRotation((rotationAnchor ?? .zero) + v.rotation)
            }
            .onEnded { _ in rotationAnchor = nil }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                if panAnchor == nil { panAnchor = model.pan }
                let base = panAnchor ?? .zero
                model.pan = CGSize(width: base.width + v.translation.width,
                                   height: base.height + v.translation.height)
            }
            .onEnded { _ in panAnchor = nil }
    }

    private func clamp01(_ x: CGFloat) -> CGFloat { min(max(x, 0), 1) }
}
