import Foundation
import Testing
import CoreGraphics
import UIKit
@testable import slabbist

@Suite("GrayscaleBuffer")
struct GrayscaleBufferTests {
    @Test("explicit init stores dimensions and pixels")
    func explicitInit() {
        let buf = GrayscaleBuffer(width: 2, height: 2, pixels: [0, 64, 128, 255])
        #expect(buf.width == 2)
        #expect(buf.height == 2)
        #expect(buf.pixels.count == 4)
        #expect(buf.pixels[3] == 255)
    }

    @Test("downscales a CGImage to fit the max dimension")
    func downscalesCGImage() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format)
            .image { ctx in UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024)) }
        let cg = try #require(image.cgImage)
        let buf = try #require(GrayscaleBuffer(cgImage: cg, maxDimension: 256))
        #expect(max(buf.width, buf.height) == 256)
        #expect(buf.pixels.count == buf.width * buf.height)
    }
}
