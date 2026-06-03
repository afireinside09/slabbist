import Foundation
import Testing
import UIKit
@testable import slabbist

@Suite("UIImage+Upright")
struct UIImageUprightTests {
    @Test("already-upright image returns its cgImage unchanged")
    func uprightNoOp() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 50), format: format)
            .image { ctx in UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 30, height: 50)) }
        #expect(img.imageOrientation == .up)
        let cg = try #require(img.uprightCGImage())
        #expect(cg.width == 30)
        #expect(cg.height == 50)
    }

    @Test("a .right-tagged landscape buffer normalizes to portrait pixel dims")
    func normalizesRightOrientation() throws {
        // Simulate an AVCapture still: raw buffer is landscape (60x40),
        // tagged .right so it displays portrait (40 wide x 60 tall).
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let landscape = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40), format: format)
            .image { ctx in UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 40)) }
        let raw = try #require(landscape.cgImage)
        let tagged = UIImage(cgImage: raw, scale: 1, orientation: .right)
        // Displayed size is portrait:
        #expect(tagged.size == CGSize(width: 40, height: 60))
        // Uprighted cgImage must have portrait PIXEL dims matching display:
        let up = try #require(tagged.uprightCGImage())
        #expect(up.width == 40)
        #expect(up.height == 60)
    }
}
