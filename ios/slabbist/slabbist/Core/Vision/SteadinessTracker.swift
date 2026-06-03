import CoreGraphics

/// Rolling window of recent card-rectangle centroids (normalized 0...1).
/// `isSteady` is true once the window is full and the positional variance is
/// below `maxVariance`. Confined to the camera sample queue — not thread-safe.
struct SteadinessTracker {
    let capacity: Int
    let maxVariance: Double
    private var samples: [CGPoint] = []

    init(capacity: Int = 5, maxVariance: Double = 0.0004) {
        self.capacity = capacity
        self.maxVariance = maxVariance
    }

    mutating func push(_ centroid: CGPoint) {
        samples.append(centroid)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    mutating func reset() { samples.removeAll() }

    var isSteady: Bool {
        guard samples.count >= capacity else { return false }
        let n = Double(samples.count)
        let mx = samples.reduce(0.0) { $0 + Double($1.x) } / n
        let my = samples.reduce(0.0) { $0 + Double($1.y) } / n
        let v = samples.reduce(0.0) {
            let dx = Double($1.x) - mx, dy = Double($1.y) - my
            return $0 + dx * dx + dy * dy
        } / n
        return v <= maxVariance
    }
}
