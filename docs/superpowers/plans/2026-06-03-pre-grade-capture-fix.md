# Pre-Grade Trustworthy Capture (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **SwiftUI/AVFoundation tasks (8) REQUIRE invoking `swiftui-expert-skill` first** and passing its rules into the work — per project CLAUDE.md.

**Goal:** Make the Pre-Grade capture trustworthy — real blur/glare metrics that actually reject bad photos, a live readiness chip, and a shutter that cannot fire until the live frame is genuinely good.

**Architecture:** Three pure, unit-testable metric primitives operate on a downscaled `GrayscaleBuffer` (no image files in tests). The still capture path re-gates with real metrics instead of the hardcoded `blurScore: 200, glareRatio: 0`. A background `LiveReadinessAnalyzer` taps the existing `CameraSession.setOnSampleBuffer` hook, runs the same metrics at ~4 Hz, and publishes a `CaptureReadiness` to the view model that gates the shutter button.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Vision, CoreGraphics/CoreImage, Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`).

**Scope note:** This is Phase 1 of the `2026-06-03-pre-grade-robust-defects-design.md` spec (trustworthy capture). Phase 2–3 (on-device defect analysis + Card Vision report + backend `defects` column) get a separate plan after Phase 1 is verified.

**Decision (locked):** Manual shutter gated by live readiness — **no auto-capture**. The button is disabled until readiness passes; the user always presses it.

**Project note:** The `slabbist` target uses Xcode file-system-synchronized groups, so new `.swift` files under `slabbist/` and `slabbistTests/` are picked up automatically. If a new file does not compile into the target, add it to the `slabbist` (or `slabbistTests`) target membership manually.

**Test command (template):**
```bash
xcodebuild test \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:slabbistTests/<SuiteTypeName>
```

---

### Task 1: GrayscaleBuffer

A downscaled 8-bit grayscale representation that every metric consumes. Built from a `CGImage` in production, or directly from a pixel array in tests.

**Files:**
- Create: `ios/slabbist/slabbist/Core/Vision/GrayscaleBuffer.swift`
- Test: `ios/slabbist/slabbistTests/Core/Vision/GrayscaleBufferTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command with `-only-testing:slabbistTests/GrayscaleBufferTests`.
Expected: FAIL — `cannot find 'GrayscaleBuffer' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import CoreGraphics

/// A downscaled, single-channel (8-bit) grayscale view of an image. Every
/// capture-quality metric consumes one of these so the metrics stay pure and
/// fully unit-testable (tests build buffers from raw pixel arrays).
struct GrayscaleBuffer: Equatable {
    let width: Int
    let height: Int
    let pixels: [UInt8]   // row-major, one byte per pixel

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Draws `cgImage` into a device-gray context no larger than
    /// `maxDimension` on its longest side. Returns nil if the context can't
    /// be created.
    init?(cgImage: CGImage, maxDimension: Int) {
        let srcW = cgImage.width, srcH = cgImage.height
        guard srcW > 0, srcH > 0, maxDimension > 0 else { return nil }
        let scale = min(1.0, Double(maxDimension) / Double(max(srcW, srcH)))
        let w = max(1, Int((Double(srcW) * scale).rounded()))
        let h = max(1, Int((Double(srcH) * scale).rounded()))
        var data = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &data,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        self.init(width: w, height: h, pixels: data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same test command. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Vision/GrayscaleBuffer.swift ios/slabbist/slabbistTests/Core/Vision/GrayscaleBufferTests.swift
git commit -m "feat(ios): add GrayscaleBuffer for capture-quality metrics"
```

---

### Task 2: BlurMetric (Laplacian variance)

**Files:**
- Create: `ios/slabbist/slabbist/Core/Vision/BlurMetric.swift`
- Test: `ios/slabbist/slabbistTests/Core/Vision/BlurMetricTests.swift`

- [ ] **Step 1: Write the failing test**

A flat buffer has zero high-frequency content (blurry); a checkerboard is maximally high-frequency (sharp). The default gate threshold is 100.

```swift
import Foundation
import Testing
@testable import slabbist

@Suite("BlurMetric")
struct BlurMetricTests {
    @Test("flat buffer scores ~0 (below sharp threshold)")
    func flatIsBlurry() {
        let buf = GrayscaleBuffer(width: 8, height: 8, pixels: [UInt8](repeating: 128, count: 64))
        #expect(BlurMetric.laplacianVariance(buf) < 100)
    }

    @Test("checkerboard scores high (above sharp threshold)")
    func checkerboardIsSharp() {
        var pixels = [UInt8](); pixels.reserveCapacity(64)
        for y in 0..<8 { for x in 0..<8 { pixels.append((x + y) % 2 == 0 ? 0 : 255) } }
        let buf = GrayscaleBuffer(width: 8, height: 8, pixels: pixels)
        #expect(BlurMetric.laplacianVariance(buf) > 100)
    }

    @Test("buffers smaller than the kernel score 0")
    func tooSmall() {
        let buf = GrayscaleBuffer(width: 2, height: 2, pixels: [0, 255, 255, 0])
        #expect(BlurMetric.laplacianVariance(buf) == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-only-testing:slabbistTests/BlurMetricTests`.
Expected: FAIL — `cannot find 'BlurMetric' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Sharpness via the variance of the 3×3 Laplacian response. Higher = sharper;
/// flat / out-of-focus images approach 0. The capture gate's `minBlurScore`
/// (default 100) is the accept/reject cut.
enum BlurMetric {
    static func laplacianVariance(_ buffer: GrayscaleBuffer) -> Double {
        let w = buffer.width, h = buffer.height
        guard w >= 3, h >= 3 else { return 0 }
        let p = buffer.pixels
        var responses = [Double]()
        responses.reserveCapacity((w - 2) * (h - 2))
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = Double(p[y * w + x])
                let up = Double(p[(y - 1) * w + x])
                let down = Double(p[(y + 1) * w + x])
                let left = Double(p[y * w + (x - 1)])
                let right = Double(p[y * w + (x + 1)])
                responses.append(up + down + left + right - 4 * c)
            }
        }
        guard !responses.isEmpty else { return 0 }
        let mean = responses.reduce(0, +) / Double(responses.count)
        let varSum = responses.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return varSum / Double(responses.count)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same test command. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Vision/BlurMetric.swift ios/slabbist/slabbistTests/Core/Vision/BlurMetricTests.swift
git commit -m "feat(ios): add Laplacian-variance blur metric"
```

---

### Task 3: GlareMetric (over-exposed pixel ratio within a rect)

**Files:**
- Create: `ios/slabbist/slabbist/Core/Vision/GlareMetric.swift`
- Test: `ios/slabbist/slabbistTests/Core/Vision/GlareMetricTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
import CoreGraphics
@testable import slabbist

@Suite("GlareMetric")
struct GlareMetricTests {
    @Test("fully blown buffer is ratio 1.0")
    func allBlown() {
        let buf = GrayscaleBuffer(width: 4, height: 4, pixels: [UInt8](repeating: 255, count: 16))
        #expect(GlareMetric.overexposedRatio(buf, in: nil) == 1.0)
    }

    @Test("pixels at 250 are not counted (threshold is > 250)")
    func boundaryNotBlown() {
        let buf = GrayscaleBuffer(width: 4, height: 4, pixels: [UInt8](repeating: 250, count: 16))
        #expect(GlareMetric.overexposedRatio(buf, in: nil) == 0.0)
    }

    @Test("only counts pixels inside the normalized rect")
    func respectsRect() {
        // Left half blown (255), right half dark (10).
        var pixels = [UInt8]()
        for _ in 0..<4 { pixels += [255, 255, 10, 10] } // 4x4
        let buf = GrayscaleBuffer(width: 4, height: 4, pixels: pixels)
        let leftHalf = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        let rightHalf = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        #expect(GlareMetric.overexposedRatio(buf, in: leftHalf) == 1.0)
        #expect(GlareMetric.overexposedRatio(buf, in: rightHalf) == 0.0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-only-testing:slabbistTests/GlareMetricTests`.
Expected: FAIL — `cannot find 'GlareMetric' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import CoreGraphics

/// Fraction of pixels brighter than 250 within a normalized sub-rect
/// (`nil` = whole buffer). 1.0 means fully blown out. The capture gate's
/// `maxGlareRatio` (default 0.02) is the reject cut. Restricting to the card
/// rect keeps a bright background from tripping the check.
enum GlareMetric {
    static func overexposedRatio(_ buffer: GrayscaleBuffer, in rect: CGRect?) -> Double {
        let w = buffer.width, h = buffer.height
        guard w > 0, h > 0 else { return 0 }
        let r = rect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let x0 = max(0, Int((Double(r.minX) * Double(w)).rounded(.down)))
        let y0 = max(0, Int((Double(r.minY) * Double(h)).rounded(.down)))
        let x1 = min(w, Int((Double(r.maxX) * Double(w)).rounded(.up)))
        let y1 = min(h, Int((Double(r.maxY) * Double(h)).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return 0 }
        let p = buffer.pixels
        var blown = 0, total = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                if p[y * w + x] > 250 { blown += 1 }
                total += 1
            }
        }
        return total == 0 ? 0 : Double(blown) / Double(total)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same test command. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Vision/GlareMetric.swift ios/slabbist/slabbistTests/Core/Vision/GlareMetricTests.swift
git commit -m "feat(ios): add glare (over-exposure) metric"
```

---

### Task 4: SteadinessTracker

Prevents the shutter from enabling on a momentarily-good but shaking frame.

**Files:**
- Create: `ios/slabbist/slabbist/Core/Vision/SteadinessTracker.swift`
- Test: `ios/slabbist/slabbistTests/Core/Vision/SteadinessTrackerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
import CoreGraphics
@testable import slabbist

@Suite("SteadinessTracker")
struct SteadinessTrackerTests {
    @Test("not steady before reaching capacity")
    func needsFullWindow() {
        var t = SteadinessTracker(capacity: 5, maxVariance: 0.0004)
        for _ in 0..<3 { t.push(CGPoint(x: 0.5, y: 0.5)) }
        #expect(t.isSteady == false)
    }

    @Test("steady when the framing barely moves")
    func steadyWhenStill() {
        var t = SteadinessTracker(capacity: 5, maxVariance: 0.0004)
        for _ in 0..<5 { t.push(CGPoint(x: 0.5, y: 0.5)) }
        #expect(t.isSteady == true)
    }

    @Test("not steady when the framing jumps around")
    func unsteadyWhenJittery() {
        var t = SteadinessTracker(capacity: 5, maxVariance: 0.0004)
        let pts = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9),
                   CGPoint(x: 0.1, y: 0.9), CGPoint(x: 0.9, y: 0.1),
                   CGPoint(x: 0.5, y: 0.5)]
        pts.forEach { t.push($0) }
        #expect(t.isSteady == false)
    }

    @Test("reset clears the window")
    func resetClears() {
        var t = SteadinessTracker(capacity: 5, maxVariance: 0.0004)
        for _ in 0..<5 { t.push(CGPoint(x: 0.5, y: 0.5)) }
        t.reset()
        #expect(t.isSteady == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-only-testing:slabbistTests/SteadinessTrackerTests`.
Expected: FAIL — `cannot find 'SteadinessTracker' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run the same test command. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Vision/SteadinessTracker.swift ios/slabbist/slabbistTests/Core/Vision/SteadinessTrackerTests.swift
git commit -m "feat(ios): add SteadinessTracker for capture lock"
```

---

### Task 5: CaptureReadiness

The Sendable value the live analyzer publishes; owns the chip-message priority.

**Files:**
- Create: `ios/slabbist/slabbist/Core/Vision/CaptureReadiness.swift`
- Test: `ios/slabbist/slabbistTests/Core/Vision/CaptureReadinessTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import slabbist

@Suite("CaptureReadiness")
struct CaptureReadinessTests {
    @Test("ready only when all flags pass")
    func readyAllTrue() {
        let r = CaptureReadiness(cardDetected: true, sharp: true, glareOK: true, steady: true)
        #expect(r.isReady == true)
        #expect(r.message == nil)
    }

    @Test("message prioritizes card detection over everything else")
    func messagePriority() {
        let r = CaptureReadiness(cardDetected: false, sharp: false, glareOK: false, steady: false)
        #expect(r.isReady == false)
        #expect(r.message?.lowercased().contains("card") == true)
    }

    @Test("blur message wins once a card is detected")
    func blurMessage() {
        let r = CaptureReadiness(cardDetected: true, sharp: false, glareOK: true, steady: true)
        #expect(r.message?.lowercased().contains("blur") == true)
    }

    @Test("steady is the lowest-priority message")
    func steadyMessage() {
        let r = CaptureReadiness(cardDetected: true, sharp: true, glareOK: true, steady: false)
        #expect(r.message?.lowercased().contains("still") == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-only-testing:slabbistTests/CaptureReadinessTests`.
Expected: FAIL — `cannot find 'CaptureReadiness' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
/// Snapshot of live capture quality, published from the camera sample queue to
/// the view model. Drives both the shutter-enabled state (`isReady`) and the
/// QualityChip copy (`message`).
struct CaptureReadiness: Equatable, Sendable {
    var cardDetected: Bool
    var sharp: Bool
    var glareOK: Bool
    var steady: Bool

    var isReady: Bool { cardDetected && sharp && glareOK && steady }

    /// First failing reason in priority order, or nil when ready.
    var message: String? {
        if !cardDetected { return "Card not detected — frame the whole card." }
        if !sharp { return "Too blurry — hold steady and let it focus." }
        if !glareOK { return "Too much glare — angle away from direct light." }
        if !steady { return "Hold still…" }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same test command. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Vision/CaptureReadiness.swift ios/slabbist/slabbistTests/Core/Vision/CaptureReadinessTests.swift
git commit -m "feat(ios): add CaptureReadiness state + chip messaging"
```

---

### Task 6: Synchronous CardRectangleDetector core

The live analyzer runs on a serial background queue and must detect synchronously (no async hop) to keep its state confined to that queue. Extract a sync core; keep the existing async API and its tests green.

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Vision/CardRectangleDetector.swift`
- Test: `ios/slabbist/slabbistTests/Core/Vision/CardRectangleDetectorTests.swift` (add one case)

- [ ] **Step 1: Write the failing test**

Add this case to the existing `CardRectangleDetectorTests` suite (do not remove existing tests):

```swift
    @Test("sync detect returns nil for an image with no card-like rectangle")
    func syncDetectNoCard() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600), format: format)
            .image { ctx in UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 600)) }
        let cg = try #require(image.cgImage)
        #expect(CardRectangleDetector.detect(in: cg) == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-only-testing:slabbistTests/CardRectangleDetectorTests`.
Expected: FAIL — `type 'CardRectangleDetector' has no member 'detect'` (static).

- [ ] **Step 3: Write minimal implementation**

Replace the body of `detect(in image:)` and add the static core. The file becomes:

```swift
import Foundation
import UIKit
import Vision

/// Wraps `VNDetectRectanglesRequest` with thresholds tuned for trading cards.
/// Returns the highest-confidence rectangle whose aspect ratio falls in the
/// trading-card range (0.6–0.85). Coordinates are in the image's pixel space,
/// origin top-left.
struct CardRectangleDetector {
    struct Result: Equatable {
        var boundingBox: CGRect    // pixel-space, origin top-left
        var confidence: Float
    }

    func detect(in image: UIImage) async throws -> Result? {
        guard let cgImage = image.cgImage else { return nil }
        return Self.detect(in: cgImage)
    }

    /// Synchronous core — safe to call from a background queue. Used by the
    /// live readiness analyzer; the async method above wraps it.
    static func detect(in cgImage: CGImage) -> Result? {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.6
        request.maximumAspectRatio = 0.85
        request.minimumConfidence = 0.85
        request.minimumSize = 0.4   // at least 40% of the frame
        request.maximumObservations = 4

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let best = (request.results ?? []).max(by: { $0.confidence < $1.confidence }) else {
            return nil
        }

        // Vision returns normalized coords with origin bottom-left; flip to top-left pixel space.
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let bb = best.boundingBox
        let pixelRect = CGRect(
            x: bb.minX * w,
            y: (1 - bb.maxY) * h,
            width: bb.width * w,
            height: bb.height * h
        )
        return Result(boundingBox: pixelRect, confidence: best.confidence)
    }
}
```

> Note: the prior `detect(in image:)` threw only from `handler.perform`; the sync core swallows that into `nil` (a failed Vision pass means "no card", which the gate already handles). The async signature stays `throws` for source compatibility with existing callers.

- [ ] **Step 4: Run test to verify it passes**

Run the same test command. Expected: PASS (existing cases + the new one).

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Vision/CardRectangleDetector.swift ios/slabbist/slabbistTests/Core/Vision/CardRectangleDetectorTests.swift
git commit -m "refactor(ios): extract synchronous CardRectangleDetector core"
```

---

### Task 7: CaptureMetrics helper + real still re-gate

This is the immediate fix for "blurry/glary stills get accepted." `CaptureMetrics.measure` produces real `blurScore`/`glareRatio` from a captured `UIImage`; the capture path passes them to the gate instead of `200`/`0`.

**Files:**
- Create: `ios/slabbist/slabbist/Core/Vision/CaptureMetrics.swift`
- Test: `ios/slabbist/slabbistTests/Core/Vision/CaptureMetricsTests.swift`
- Modify: `ios/slabbist/slabbist/Features/Grading/Capture/GradingCaptureView.swift:211-219`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
import CoreGraphics
import UIKit
@testable import slabbist

@Suite("CaptureMetrics")
struct CaptureMetricsTests {
    @Test("a solid white image reads as fully blown glare")
    func whiteIsGlare() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100), color: .white)
        let m = CaptureMetrics.measure(image: image, cardRect: nil)
        #expect(m.glareRatio > 0.9)
    }

    @Test("a mid-gray image reads as no glare")
    func grayNoGlare() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100),
                               color: UIColor(white: 0.5, alpha: 1))
        let m = CaptureMetrics.measure(image: image, cardRect: nil)
        #expect(m.glareRatio < 0.01)
    }

    @Test("a featureless image reads as blurry (low blur score)")
    func flatIsBlurry() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100),
                               color: UIColor(white: 0.5, alpha: 1))
        let m = CaptureMetrics.measure(image: image, cardRect: nil)
        #expect(m.blurScore < 100)
    }

    private func solidImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-only-testing:slabbistTests/CaptureMetricsTests`.
Expected: FAIL — `cannot find 'CaptureMetrics' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import UIKit
import CoreGraphics

/// Computes real blur + glare metrics for a captured still. Glare is measured
/// inside the detected card rect (pixel space) when available, so a bright
/// background doesn't trip the gate. Blur is measured over the whole frame.
enum CaptureMetrics {
    struct Result: Equatable {
        var blurScore: Double
        var glareRatio: Double
    }

    static func measure(image: UIImage, cardRect: CGRect?) -> Result {
        guard let cg = image.cgImage,
              let buffer = GrayscaleBuffer(cgImage: cg, maxDimension: 512) else {
            // No decodable image — worst case so the gate rejects.
            return Result(blurScore: 0, glareRatio: 1)
        }
        let blur = BlurMetric.laplacianVariance(buffer)
        let normRect = cardRect.map { rect -> CGRect in
            let w = CGFloat(cg.width), h = CGFloat(cg.height)
            guard w > 0, h > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
            return CGRect(x: rect.minX / w, y: rect.minY / h,
                          width: rect.width / w, height: rect.height / h)
        }
        let glare = GlareMetric.overexposedRatio(buffer, in: normRect)
        return Result(blurScore: blur, glareRatio: glare)
    }
}
```

- [ ] **Step 4: Run the metrics test to verify it passes**

Run the same test command. Expected: PASS (3 tests).

- [ ] **Step 5: Wire the real metrics into the still re-gate**

In `GradingCaptureView.swift`, replace the capture-gate block (currently lines ~211–219):

```swift
            let image = try await stillCapture.capture()
            let detection = try await detector.detect(in: image)
            // Real blur/glare scoring is wired in a follow-up; for now we pass safe defaults
            // through the gate so it only short-circuits on resolution + card detection.
            let outcome = gate.evaluate(image: image, cardDetection: detection, blurScore: 200, glareRatio: 0)
            if case .rejected(let reason) = outcome {
                qualityMessage = reason
                return
            }
```

with:

```swift
            let image = try await stillCapture.capture()
            let detection = try await detector.detect(in: image)
            let metrics = CaptureMetrics.measure(image: image, cardRect: detection?.boundingBox)
            let outcome = gate.evaluate(
                image: image,
                cardDetection: detection,
                blurScore: metrics.blurScore,
                glareRatio: metrics.glareRatio
            )
            if case .rejected(let reason) = outcome {
                qualityMessage = reason
                return
            }
```

- [ ] **Step 6: Build to verify it compiles**

Run:
```bash
xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add ios/slabbist/slabbist/Core/Vision/CaptureMetrics.swift ios/slabbist/slabbistTests/Core/Vision/CaptureMetricsTests.swift ios/slabbist/slabbist/Features/Grading/Capture/GradingCaptureView.swift
git commit -m "fix(ios): re-gate captured stills with real blur/glare metrics"
```

---

### Task 8: Live readiness — analyzer + view-model state + gated shutter

> **Invoke `swiftui-expert-skill` before this task** and follow its state-management/concurrency rules.

Tap the existing `CameraSession.setOnSampleBuffer` hook, analyze frames at ~4 Hz on the sample queue, and publish `CaptureReadiness` to the view model. The shutter is disabled until `isReady`; the chip shows the live failing reason. No auto-capture.

**Files:**
- Create: `ios/slabbist/slabbist/Features/Grading/Capture/LiveReadinessAnalyzer.swift`
- Modify: `ios/slabbist/slabbist/Features/Grading/Capture/GradingCaptureViewModel.swift`
- Modify: `ios/slabbist/slabbist/Features/Grading/Capture/GradingCaptureView.swift`

- [ ] **Step 1: Add live-readiness state to the view model**

In `GradingCaptureViewModel.swift`, after the `lastError` property (line ~23), add:

```swift
    /// Latest live capture readiness published by `LiveReadinessAnalyzer`.
    /// Drives the shutter-enabled state and the QualityChip while framing.
    private(set) var liveReadiness: CaptureReadiness?

    /// Called from the camera sample queue (hopped to MainActor). Ignored once
    /// we leave the camera (uploading/analyzing/done/failed) so a late frame
    /// can't repaint the chip behind the analysis overlay.
    func updateLiveReadiness(_ readiness: CaptureReadiness) {
        guard phase == .front || phase == .back else { return }
        liveReadiness = readiness
    }
```

- [ ] **Step 2: Create the analyzer**

```swift
import AVFoundation
import CoreImage
import CoreGraphics
import UIKit

/// Throttled per-frame capture-quality analysis on the camera sample stream.
/// Created and used on the camera sample queue; `@unchecked Sendable` because
/// all mutable state is touched only from that single serial queue. Publishes
/// a `CaptureReadiness` via `onReadiness` (the caller hops to MainActor).
final class LiveReadinessAnalyzer: @unchecked Sendable {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let gate = CaptureQualityGate()
    private var steadiness = SteadinessTracker()
    private var lastProcessed: Double = -1
    private let interval: Double = 0.25   // ~4 Hz
    private let onReadiness: @Sendable (CaptureReadiness) -> Void

    init(onReadiness: @escaping @Sendable (CaptureReadiness) -> Void) {
        self.onReadiness = onReadiness
    }

    func handle(_ sampleBuffer: CMSampleBuffer) {
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        if lastProcessed >= 0, t - lastProcessed < interval { return }
        lastProcessed = t

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent),
              let buffer = GrayscaleBuffer(cgImage: cg, maxDimension: 512) else { return }

        let detection = CardRectangleDetector.detect(in: cg)
        let cardDetected = detection != nil
        let sharp = BlurMetric.laplacianVariance(buffer) >= gate.thresholds.minBlurScore

        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let normRect: CGRect? = detection.flatMap { det in
            guard w > 0, h > 0 else { return nil }
            return CGRect(x: det.boundingBox.minX / w, y: det.boundingBox.minY / h,
                          width: det.boundingBox.width / w, height: det.boundingBox.height / h)
        }
        let glareOK = GlareMetric.overexposedRatio(buffer, in: normRect) <= gate.thresholds.maxGlareRatio

        if let det = detection, w > 0, h > 0 {
            steadiness.push(CGPoint(x: det.boundingBox.midX / w, y: det.boundingBox.midY / h))
        } else {
            steadiness.reset()
        }

        onReadiness(CaptureReadiness(
            cardDetected: cardDetected, sharp: sharp,
            glareOK: glareOK, steady: steadiness.isSteady
        ))
    }
}
```

- [ ] **Step 3: Wire the analyzer into the view and gate the shutter**

In `GradingCaptureView.swift`:

(a) Add state near the other `@State` declarations (after `analysisTask`, line ~17):

```swift
    @State private var liveAnalyzer: LiveReadinessAnalyzer?
```

(b) In the `.task { ... }` block, after `session.start()` (line ~89), set up the analyzer:

```swift
            let analyzer = LiveReadinessAnalyzer { readiness in
                Task { @MainActor in viewModel.updateLiveReadiness(readiness) }
            }
            liveAnalyzer = analyzer
            session.setOnSampleBuffer { analyzer.handle($0) }
```

(c) In `.onDisappear { ... }` add the teardown alongside the existing lines:

```swift
            session.setOnSampleBuffer(nil)
            liveAnalyzer = nil
```

(d) Add a computed chip message that prefers an explicit error (attach/capture) over the live reason, and use it for the chip + overlay alignment. Add near `captureEnabled` (line ~204):

```swift
    /// Explicit capture/attach errors take precedence over the live readiness
    /// reason so a "Camera unavailable" message isn't overwritten by "Card not
    /// detected".
    private var chipMessage: String? {
        qualityMessage ?? viewModel.liveReadiness?.message
    }
```

(e) Change `captureEnabled` (line ~204-206) to require live readiness:

```swift
    private var captureEnabled: Bool {
        stillCapture != nil && qualityMessage == nil && (viewModel.liveReadiness?.isReady ?? false)
    }
```

(f) Update the two consumers in `body`: the `QualityChip(message: qualityMessage)` (line ~43) becomes `QualityChip(message: chipMessage)`, and `CardOutlineOverlay(aligned: qualityMessage == nil)` (line ~39) becomes `CardOutlineOverlay(aligned: chipMessage == nil)`.

- [ ] **Step 4: Build to verify it compiles**

Run:
```bash
xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```
Expected: BUILD SUCCEEDED, with no Swift 6 concurrency errors (the analyzer is `@unchecked Sendable`; the closure hops to MainActor).

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Grading/Capture/LiveReadinessAnalyzer.swift ios/slabbist/slabbist/Features/Grading/Capture/GradingCaptureViewModel.swift ios/slabbist/slabbist/Features/Grading/Capture/GradingCaptureView.swift
git commit -m "feat(ios): gate pre-grade shutter on live capture readiness"
```

---

### Task 9: Full test run, manual verification, and wrap-up

**Files:** none (verification only).

- [ ] **Step 1: Run the full Vision suite + grading view-model tests**

```bash
xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:slabbistTests/GrayscaleBufferTests \
  -only-testing:slabbistTests/BlurMetricTests \
  -only-testing:slabbistTests/GlareMetricTests \
  -only-testing:slabbistTests/SteadinessTrackerTests \
  -only-testing:slabbistTests/CaptureReadinessTests \
  -only-testing:slabbistTests/CaptureMetricsTests \
  -only-testing:slabbistTests/CardRectangleDetectorTests \
  -only-testing:slabbistTests/CaptureQualityGateTests \
  -only-testing:slabbistTests/GradingCaptureViewModelTests
```
Expected: all suites PASS. If `GradingCaptureViewModelTests` references the new `liveReadiness`/`updateLiveReadiness`, confirm it still compiles and passes.

- [ ] **Step 2: Manual device/simulator verification (Pre-grade tab)**

Build & run, open the Pre-grade tab → "Grade card". Verify each (this is the acceptance bar for "can't take a clean photo"):
- Point at a blank wall (no card): chip reads "Card not detected", shutter disabled.
- Frame a card but move the phone/shake: chip cycles to "Hold still…" and the shutter stays disabled until steady.
- Defocus / move very close so it blurs: chip reads "Too blurry…", shutter disabled.
- Shine a light to blow out the card: chip reads "Too much glare…", shutter disabled.
- Frame a sharp, well-lit, steady card: chip clears, outline turns gold, shutter enables; tapping it captures and advances to the back side.
- Capture a deliberately blurry still (tap the instant before focus locks, if reachable): the still re-gate rejects with the blur reason and stays on the same side rather than uploading.

Record the outcomes in the PR description. If any check fails, fix before proceeding (do not claim done — CLAUDE.md Rule 12).

- [ ] **Step 3: Finalize**

Use `superpowers:finishing-a-development-branch` to decide merge/PR. Note in the handoff that Phase 2–3 (defect analyzer, Card Vision report, backend `defects` column) is the next plan from `2026-06-03-pre-grade-robust-defects-design.md`.

---

## Self-Review

**Spec coverage (Phase 1 scope only):**
- "Real blur metric (Laplacian variance)" → Task 2. ✓
- "Real glare metric (luma > 250 within card rect)" → Task 3 + Task 7 (rect wiring). ✓
- "Stability lock / steadiness" → Task 4 + Task 8. ✓
- "Live readiness chip + gated shutter, manual (no auto-capture)" → Task 5 + Task 8. ✓
- "Re-run full gate on the full-res still" → Task 7. ✓
- "New BlurMetric.swift, GlareMetric.swift; edit CaptureQualityGate call-site, capture VM/View" → Tasks 2,3,7,8. (`CaptureQualityGate.swift` itself needs no edit — it already accepts real `blurScore`/`glareRatio`; only the hardcoded call-site at `GradingCaptureView.swift:215` changes. Spec text said "edit CaptureQualityGate"; the accurate change is the call-site. Noted.) ✓
- "Live frame analyzer uses its own consumer; no OCR contention" → Task 8 uses `setOnSampleBuffer` on the grading screen's own `CameraSession` instance. ✓
- Phase 2–3 items (defect analyzer, Card Vision, backend column) → explicitly deferred to a separate plan. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. ✓

**Type consistency:** `GrayscaleBuffer` (Tasks 1,2,3,7,8), `BlurMetric.laplacianVariance` (2,7,8), `GlareMetric.overexposedRatio` (3,7,8), `SteadinessTracker` (4,8), `CaptureReadiness`/`isReady`/`message` (5,8), `CardRectangleDetector.detect(in: CGImage)` static (6,8), `CaptureMetrics.measure(image:cardRect:)` (7), `GradingCaptureViewModel.updateLiveReadiness`/`liveReadiness` (8) — names match across all referencing tasks. ✓
