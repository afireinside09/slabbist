import CoreGraphics
import SwiftUI
import Testing
@testable import slabbist

@Suite("CenteringTransform")
struct CenteringTransformTests {
    /// A guide stored in normalized space must land back on itself after a
    /// round-trip through screen space at any zoom/pan/rotation — this is the
    /// guarantee that lets us draw handles and convert touches without the
    /// measured ratio drifting as the user zooms or rotates.
    @Test("normalized → screen → normalized round-trips at zoom/pan/rotation")
    func roundTrip() {
        let image = CGSize(width: 1000, height: 1400)
        let view = CGSize(width: 390, height: 700)
        let cases: [(CGFloat, CGSize, Angle)] = [
            (1, .zero, .zero),
            (2, CGSize(width: 40, height: -20), .zero),
            (4, CGSize(width: -80, height: 120), .degrees(5)),
            (3, CGSize(width: 15, height: 15), .degrees(-5))
        ]
        for (zoom, pan, rot) in cases {
            let t = CenteringTransform(imagePixelSize: image, viewSize: view, zoom: zoom, pan: pan, rotation: rot)
            for (nx, ny) in [(0.0, 0.0), (0.25, 0.75), (0.5, 0.5), (1.0, 1.0), (0.16, 0.84)] {
                let screen = t.screenPoint(normX: nx, normY: ny)
                let back = t.normalized(screenPoint: screen)
                #expect(abs(back.x - nx) < 1e-6, "x at zoom \(zoom) rot \(rot.degrees)")
                #expect(abs(back.y - ny) < 1e-6, "y at zoom \(zoom) rot \(rot.degrees)")
            }
        }
    }

    /// A horizontal drag must move a vertical guide by a normalized amount
    /// that depends only on the fitted width and zoom — never on the pan
    /// offset. If pan leaked into the delta, panning the image would change
    /// how far a drag moves a line, which is a precision bug.
    @Test("imageDelta is pan-independent and scales with 1/(fitWidth·zoom)")
    func deltaScaling() {
        let image = CGSize(width: 1000, height: 1400)
        let view = CGSize(width: 400, height: 600)
        let base = CenteringTransform(imagePixelSize: image, viewSize: view, zoom: 2)
        let panned = CenteringTransform(imagePixelSize: image, viewSize: view, zoom: 2, pan: CGSize(width: 99, height: -33))
        let d = base.imageDelta(screenTranslation: CGSize(width: 50, height: 0))
        let dPanned = panned.imageDelta(screenTranslation: CGSize(width: 50, height: 0))
        #expect(abs(d.dx - dPanned.dx) < 1e-12)
        #expect(abs(d.dx - 50 / (base.fitRect.width * 2)) < 1e-9)
    }

    /// The fit rect must letterbox correctly in both orientations: a portrait
    /// card in a landscape view is width-limited at full view height; the
    /// reverse is height-limited. The whole coordinate system is anchored to
    /// this rect, so an off letterbox throws off every guide.
    @Test("fitRect letterboxes portrait-in-landscape and landscape-in-portrait")
    func letterbox() {
        let portrait = CenteringTransform(imagePixelSize: CGSize(width: 1000, height: 1400),
                                          viewSize: CGSize(width: 800, height: 400))
        // height-limited: scale 400/1400, width 285.7, centered horizontally
        #expect(abs(portrait.fitRect.height - 400) < 1e-6)
        #expect(portrait.fitRect.width < 800)
        #expect(abs(portrait.fitRect.midX - 400) < 1e-6)

        let landscape = CenteringTransform(imagePixelSize: CGSize(width: 1400, height: 1000),
                                           viewSize: CGSize(width: 300, height: 800))
        // width-limited: scale 300/1400, height 214.3, centered vertically
        #expect(abs(landscape.fitRect.width - 300) < 1e-6)
        #expect(landscape.fitRect.height < 800)
        #expect(abs(landscape.fitRect.midY - 400) < 1e-6)
    }
}
