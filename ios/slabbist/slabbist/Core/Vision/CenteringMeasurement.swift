import Foundation
import CoreGraphics

/// Computes PSA-style centering ratios from a detected card rectangle
/// and the underlying image bounds. Returned values are in 0...1 where
/// `left = leftWhitespace / (leftWhitespace + rightWhitespace)`. A perfectly
/// centered card returns 0.5 on every axis.
enum CenteringMeasurement {
    struct Ratios: Equatable {
        var left: Double
        var right: Double
        var top: Double
        var bottom: Double
    }

    static func measure(cardRect: CGRect, in imageRect: CGRect) -> Ratios {
        let leftWS = max(0, cardRect.minX - imageRect.minX)
        let rightWS = max(0, imageRect.maxX - cardRect.maxX)
        let topWS = max(0, cardRect.minY - imageRect.minY)
        let bottomWS = max(0, imageRect.maxY - cardRect.maxY)

        let h = leftWS + rightWS
        let v = topWS + bottomWS

        let left = h == 0 ? 0.5 : Double(leftWS / h)
        let top = v == 0 ? 0.5 : Double(topWS / v)
        return Ratios(left: left, right: 1 - left, top: top, bottom: 1 - top)
    }
}
