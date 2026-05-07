import SwiftUI

/// Minimal Path-based sparkline. Hides itself when there are fewer than
/// 2 points (a single point can't draw a line).
struct CompSparklineView: View {
    let points: [PriceHistoryPoint]

    var body: some View {
        GeometryReader { geo in
            if points.count >= 2 {
                let path = sparklinePath(points: points, in: geo.size)
                path.stroke(AppColor.gold, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 32)
    }

    private func sparklinePath(points: [PriceHistoryPoint], in size: CGSize) -> Path {
        guard let minPrice = points.map(\.priceCents).min(),
              let maxPrice = points.map(\.priceCents).max(),
              minPrice < maxPrice,
              let firstTs = points.first?.ts,
              let lastTs = points.last?.ts else {
            return Path()
        }
        let xRange = lastTs.timeIntervalSince(firstTs)
        let yRange = Double(maxPrice - minPrice)
        var path = Path()
        for (index, point) in points.enumerated() {
            let xNorm: CGFloat
            if xRange > 0 {
                xNorm = CGFloat(point.ts.timeIntervalSince(firstTs) / xRange)
            } else {
                xNorm = CGFloat(index) / CGFloat(max(points.count - 1, 1))
            }
            let yNorm = 1.0 - CGFloat(Double(point.priceCents - minPrice) / yRange)
            let x = xNorm * size.width
            let y = yNorm * size.height
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else          { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

#Preview("Sparkline — 6 month series") {
    let calendar = Calendar(identifier: .gregorian)
    let points: [PriceHistoryPoint] = (0..<24).map { i in
        let date = calendar.date(byAdding: .day, value: i * 7, to: Date(timeIntervalSinceNow: -180 * 86_400))!
        let cents = Int64(15_000 + (i * 200) + Int(sin(Double(i) / 3) * 800))
        return PriceHistoryPoint(ts: date, priceCents: cents)
    }
    return CompSparklineView(points: points)
        .padding()
        .background(Color.black)
}

#Preview("Sparkline — empty") {
    CompSparklineView(points: [])
        .padding()
        .background(Color.black)
}
