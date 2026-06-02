# Photo Cert Parse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a third slab-input method to the Scan tab — pick a grader, take one still photo of a tray of same-grader slabs, extract every matching cert on-device, review/correct, and record all through the existing scan pipeline.

**Architecture:** A pure, unit-tested `PhotoCertParser` does multi-cert extraction given a known grader. A `StillPhotoCamera` (`AVCapturePhotoOutput`) captures a high-res still; a `PhotoScanView` coordinator runs Vision OCR on it, parses, and presents an editable review list. Confirmed certs flow through the existing `BulkScanViewModel.record(candidate:)` path (dedup → cert-lookup → comp). Entry is a toolbar button on `BulkScanView`; the live OCR session pauses while the photo cover is up.

**Tech Stack:** SwiftUI, AVFoundation (`AVCapturePhotoOutput`), Vision (`VNRecognizeTextRequest`), Swift Testing (`import Testing`), SwiftData (existing record path).

**Spec:** `docs/superpowers/specs/2026-06-02-photo-cert-parse-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `slabbist/Features/Scanning/PhotoScan/PhotoCertParser.swift` (create) | Pure multi-cert extraction given a known grader. No Vision/UIKit deps. |
| `slabbist/Features/Scanning/PhotoScan/StillPhotoCamera.swift` (create) | `@Observable` wrapper around `AVCaptureSession` + `AVCapturePhotoOutput` for one-shot stills. |
| `slabbist/Features/Scanning/PhotoScan/PhotoTextRecognizer.swift` (create) | Vision OCR helper: `UIImage` → `[String]`, plus the `CGImagePropertyOrientation` bridge. |
| `slabbist/Features/Scanning/PhotoScan/PhotoScanView.swift` (create) | Cover-root coordinator: owns grader + phase + camera; runs OCR + parser; hosts subviews; record loop. |
| `slabbist/Features/Scanning/PhotoScan/PhotoScanCaptureView.swift` (create) | Capture subview: grader picker, still preview, shutter, denied UI, simulator fixture. |
| `slabbist/Features/Scanning/PhotoScan/PhotoScanReviewView.swift` (create) | Editable review list; per-row validity + already-in-lot marker; "Add N to lot". |
| `slabbist/Features/Scanning/BulkScan/BulkScanView.swift` (modify) | Add photo toolbar button + `.fullScreenCover`; pause/resume live session. |
| `slabbistTests/Features/Scanning/PhotoScan/PhotoCertParserTests.swift` (create) | The real coverage — fixture OCR strings → exact extracted set. |

---

## Task 1: `PhotoCertParser` (the tested core)

**Files:**
- Create: `slabbist/Features/Scanning/PhotoScan/PhotoCertParser.swift`
- Test: `slabbistTests/Features/Scanning/PhotoScan/PhotoCertParserTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `slabbistTests/Features/Scanning/PhotoScan/PhotoCertParserTests.swift`:

```swift
import Foundation
import Testing
@testable import slabbist

@Suite("PhotoCertParser")
struct PhotoCertParserTests {
    @Test("extracts every PSA cert from separate OCR lines")
    func extractsMultiplePSA() {
        let lines = ["GEM MT 10", "09812345", "MINT 9", "081234567"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .PSA)
        #expect(certs == ["09812345", "081234567"])
    }

    @Test("dedupes a cert that OCR read on two lines")
    func dedupesRepeatedReads() {
        let lines = ["09812345", "PSA 10", "09812345"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .PSA)
        #expect(certs == ["09812345"])
    }

    @Test("excludes a year and a short population count for PSA")
    func excludesNonCertNumbers() {
        // WHY: a 4-digit year (2022) and a 4-digit pop count must never be
        // mistaken for a cert. If length filtering regresses, this fails.
        let lines = ["POKEMON 2022", "POP 1234", "09812345"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .PSA)
        #expect(certs == ["09812345"])
    }

    @Test("a 10-digit number is not picked up as a PSA cert")
    func tenDigitsNotPSA() {
        // WHY: BGS-length runs must not leak into a PSA scan.
        let lines = ["0123456789"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .PSA)
        #expect(certs.isEmpty)
    }

    @Test("extracts BGS 10-digit certs")
    func extractsBGS() {
        let lines = ["BECKETT 9.5", "0123456789", "1234509876"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .BGS)
        #expect(certs == ["0123456789", "1234509876"])
    }

    @Test("extracts SGC 7- and 8-digit certs")
    func extractsSGC() {
        let lines = ["SGC 10", "0011223", "00112233"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .SGC)
        #expect(certs == ["0011223", "00112233"])
    }

    @Test("extracts alphanumeric TAG certs but not pure-digit runs")
    func extractsTAG() {
        // WHY: TAG's [A-Z0-9]{10,12} would also match a 10-digit number;
        // the letter requirement keeps plain digit runs out.
        let lines = ["TAG", "A1B2C3D4E5F6", "0123456789"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .TAG)
        #expect(certs == ["A1B2C3D4E5F6"])
    }

    @Test("empty input yields empty output")
    func emptyInput() {
        #expect(PhotoCertParser.extractCerts(from: [], grader: .PSA).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
cd /Users/dixoncider/slabbist && xcodebuild test \
  -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:slabbistTests/PhotoCertParserTests 2>&1 | tail -20
```
Expected: FAIL — `Cannot find 'PhotoCertParser' in scope`.

- [ ] **Step 3: Write the implementation**

Create `slabbist/Features/Scanning/PhotoScan/PhotoCertParser.swift`:

```swift
import Foundation

/// Multi-cert extraction for the photo-scan flow. The grader is declared by
/// the user before capture, so there is no grader inference — given the
/// grader and the OCR text lines, return every distinct cert number matching
/// that grader's format, in first-appearance order.
///
/// Pure (no Vision/UIKit dependency) so it is fully unit-testable. The
/// per-grader formats mirror `CertOCRPatterns` and `ManualEntrySheet.validate`
/// — kept local here to avoid a Vision dependency. If these formats ever
/// consolidate, change all three together.
enum PhotoCertParser {
    private static func pattern(for grader: Grader) -> NSRegularExpression {
        let body: String
        switch grader {
        case .PSA:       body = #"\b(\d{8,9})\b"#
        case .BGS, .CGC: body = #"\b(\d{10})\b"#
        case .SGC:       body = #"\b(\d{7,8})\b"#
        case .TAG:       body = #"\b([A-Z0-9]{10,12})\b"#
        }
        return try! NSRegularExpression(pattern: body, options: [.caseInsensitive])
    }

    static func extractCerts(from recognizedStrings: [String], grader: Grader) -> [String] {
        let regex = pattern(for: grader)
        var seen = Set<String>()
        var result: [String] = []
        for line in recognizedStrings {
            let upper = line.uppercased()
            let range = NSRange(upper.startIndex..<upper.endIndex, in: upper)
            for m in regex.matches(in: upper, options: [], range: range) {
                guard m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: upper) else { continue }
                let cert = String(upper[r])
                // TAG patterns also match pure 10-digit runs; require a letter
                // so a BGS-shaped number can't masquerade as a TAG cert.
                if grader == .TAG && !cert.contains(where: \.isLetter) { continue }
                if seen.insert(cert).inserted { result.append(cert) }
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
cd /Users/dixoncider/slabbist && xcodebuild test \
  -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:slabbistTests/PhotoCertParserTests 2>&1 | tail -20
```
Expected: PASS — all 8 tests pass (`** TEST SUCCEEDED **`).

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Scanning/PhotoScan/PhotoCertParser.swift \
        ios/slabbist/slabbistTests/Features/Scanning/PhotoScan/PhotoCertParserTests.swift
git commit -m "feat(ios): PhotoCertParser — multi-cert extraction for a known grader

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `PhotoTextRecognizer` (Vision OCR helper)

**Files:**
- Create: `slabbist/Features/Scanning/PhotoScan/PhotoTextRecognizer.swift`

No unit test — Vision is non-deterministic in a unit harness (stated coverage gap in the spec). Verified by build + the manual device pass in Task 6.

- [ ] **Step 1: Write the implementation**

Create `slabbist/Features/Scanning/PhotoScan/PhotoTextRecognizer.swift`:

```swift
import Vision
import UIKit
import ImageIO

/// One-shot Vision text recognition over a still image. Mirrors the live
/// scan path's request config (`.accurate`, language correction off) so a
/// photo reads cert digits the same way the camera loop does. Synchronous
/// and `nonisolated` — call it off the MainActor (see `PhotoScanView`).
enum PhotoTextRecognizer {
    static func recognizeText(in image: UIImage) -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}

/// Bridge `UIImage.Orientation` → `CGImagePropertyOrientation` so Vision
/// uprights a photo captured in any device orientation before OCR.
extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:            self = .up
        case .upMirrored:    self = .upMirrored
        case .down:          self = .down
        case .downMirrored:  self = .downMirrored
        case .left:          self = .left
        case .leftMirrored:  self = .leftMirrored
        case .right:         self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd /Users/dixoncider/slabbist && xcodebuild \
  -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Scanning/PhotoScan/PhotoTextRecognizer.swift
git commit -m "feat(ios): PhotoTextRecognizer — Vision OCR over a still image

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `StillPhotoCamera`

**Files:**
- Create: `slabbist/Features/Scanning/PhotoScan/StillPhotoCamera.swift`

No unit test (camera hardware). Verified by build + device pass.

- [ ] **Step 1: Write the implementation**

Create `slabbist/Features/Scanning/PhotoScan/StillPhotoCamera.swift`:

```swift
import AVFoundation
import Observation
import UIKit

/// One-shot still-capture session for the photo-scan flow. Parallel to
/// `CameraSession` (which owns the live video-data OCR loop) but configured
/// with `AVCapturePhotoOutput` for a full-resolution still — live video
/// frames are downscaled and too soft to read many small labels at once.
///
/// Isolated from `CameraSession` on purpose. The two never run concurrently:
/// `BulkScanView` stops its live session while the photo cover is up.
@MainActor
@Observable
final class StillPhotoCamera: NSObject {
    enum Authorization: Equatable {
        case notDetermined, authorized, denied, restricted
    }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var isConfigured: Bool = false

    nonisolated(unsafe) let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()

    /// Held across the async `capture()` round-trip; resumed by the
    /// AVFoundation delegate callback. Only one capture is in flight at a
    /// time (the shutter is disabled while capturing).
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    func requestAuthorization() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:  authorization = .authorized
        case .denied:      authorization = .denied
        case .restricted:  authorization = .restricted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorization = granted ? .authorized : .denied
        @unknown default:
            authorization = .denied
        }
    }

    func configure() throws {
        guard !isConfigured else { return }
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "StillPhotoCamera", code: 1, userInfo: [NSLocalizedDescriptionKey: "No rear camera"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw NSError(domain: "StillPhotoCamera", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"])
        }
        captureSession.addInput(input)

        guard captureSession.canAddOutput(photoOutput) else {
            throw NSError(domain: "StillPhotoCamera", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot add photo output"])
        }
        captureSession.addOutput(photoOutput)
        isConfigured = true
    }

    func start() {
        guard !captureSession.isRunning else { return }
        Task.detached(priority: .userInitiated) {
            self.captureSession.startRunning()
        }
    }

    func stop() {
        guard captureSession.isRunning else { return }
        Task.detached(priority: .userInitiated) {
            self.captureSession.stopRunning()
        }
    }

    /// Capture one full-res still. Returns `nil` if not configured or capture
    /// fails. Resolves on the AVFoundation delegate callback.
    func capture() async -> UIImage? {
        guard isConfigured else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            captureContinuation = cont
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension StillPhotoCamera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            let cont = self.captureContinuation
            self.captureContinuation = nil
            cont?.resume(returning: image)
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd /Users/dixoncider/slabbist && xcodebuild \
  -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Scanning/PhotoScan/StillPhotoCamera.swift
git commit -m "feat(ios): StillPhotoCamera — one-shot full-res still capture

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `PhotoScanReviewView` (editable review list)

**Files:**
- Create: `slabbist/Features/Scanning/PhotoScan/PhotoScanReviewView.swift`

No unit test (SwiftUI view). The validity logic it relies on is a small local helper; the parser already guarantees format on first detection, and edits are re-validated here.

- [ ] **Step 1: Write the implementation**

Create `slabbist/Features/Scanning/PhotoScan/PhotoScanReviewView.swift`. Uses the project's design-system primitives (`SlabbedRoot`, `SlabCard`, `KickerLabel`, `PrimaryGoldButton`, `AppColor`, `SlabFont`, `Spacing`, `Radius`) which already exist in the codebase.

```swift
import SwiftUI

/// Editable review list for photo-detected certs. Each row is one detected
/// cert for the already-chosen grader; the user fixes misreads, removes
/// false positives, then commits the survivors. Certs already in the lot are
/// shown unchecked with a muted marker (record() would no-op them anyway).
struct PhotoScanReviewView: View {
    let grader: Grader
    let existingCertsInLot: Set<String>
    let onCommit: ([String]) -> Void
    let onRetake: () -> Void

    /// Editable working copy. `included` is the checkbox; pre-set to false
    /// for certs already in the lot.
    @State private var rows: [Row]

    struct Row: Identifiable {
        let id = UUID()
        var cert: String
        var included: Bool
    }

    init(grader: Grader,
         detectedCerts: [String],
         existingCertsInLot: Set<String>,
         onCommit: @escaping ([String]) -> Void,
         onRetake: @escaping () -> Void) {
        self.grader = grader
        self.existingCertsInLot = existingCertsInLot
        self.onCommit = onCommit
        self.onRetake = onRetake
        _rows = State(initialValue: detectedCerts.map {
            Row(cert: $0, included: !existingCertsInLot.contains($0))
        })
    }

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                if rows.isEmpty {
                    emptyState
                } else {
                    list
                }
                Spacer(minLength: 0)
                PrimaryGoldButton(
                    title: addButtonTitle,
                    isEnabled: includedValidCount > 0
                ) {
                    onCommit(includedValidCerts)
                }
                .accessibilityIdentifier("photo-scan-add-button")
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Photo scan")
            Text(rows.isEmpty ? "No \(grader.rawValue) certs found"
                              : "Found \(rows.count) \(grader.rawValue) slab\(rows.count == 1 ? "" : "s")")
                .slabTitle()
        }
    }

    private var emptyState: some View {
        FeatureEmptyState(
            systemImage: "viewfinder",
            title: "Nothing to add",
            subtitle: "No \(grader.rawValue) cert numbers were readable in that photo. Retake with better lighting, or move closer so each label fills more of the frame.",
            steps: []
        )
    }

    private var list: some View {
        SlabCard {
            VStack(spacing: 0) {
                ForEach($rows) { $row in
                    if row.id != rows.first?.id { SlabCardDivider() }
                    rowView($row)
                }
            }
        }
    }

    private func rowView(_ row: Binding<Row>) -> some View {
        let cert = row.wrappedValue.cert
        let alreadyInLot = existingCertsInLot.contains(cert)
        let formatProblem = validate(cert)
        return HStack(spacing: Spacing.m) {
            Button {
                row.wrappedValue.included.toggle()
            } label: {
                Image(systemName: row.wrappedValue.included ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.wrappedValue.included ? AppColor.gold : AppColor.dim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.wrappedValue.included ? "Exclude \(cert)" : "Include \(cert)")

            TextField("", text: row.cert)
                .keyboardType(grader == .TAG ? .asciiCapable : .numberPad)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .font(SlabFont.mono(size: 15))
                .foregroundStyle(AppColor.text)
                .tint(AppColor.gold)

            Spacer()

            if alreadyInLot {
                Text("in lot")
                    .font(SlabFont.mono(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.dim)
            } else if let formatProblem {
                Text(formatProblem)
                    .font(SlabFont.mono(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.negative)
            }

            Button {
                rows.removeAll { $0.id == row.wrappedValue.id }
            } label: {
                Image(systemName: "xmark")
                    .font(SlabFont.sans(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.dim)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(cert)")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
    }

    private var includedValidCerts: [String] {
        rows.filter { $0.included && validate($0.cert) == nil }.map(\.cert)
    }
    private var includedValidCount: Int { includedValidCerts.count }
    private var addButtonTitle: String {
        includedValidCount == 0 ? "Add to lot" : "Add \(includedValidCount) to lot"
    }

    /// Per-grader format check. Mirrors `ManualEntrySheet.validate` — short
    /// message used as a row flag rather than a blocking error.
    private func validate(_ cert: String) -> String? {
        switch grader {
        case .PSA:
            return (cert.allSatisfy(\.isNumber) && (8...9).contains(cert.count)) ? nil : "8–9 digits"
        case .BGS, .CGC:
            return (cert.allSatisfy(\.isNumber) && cert.count == 10) ? nil : "10 digits"
        case .SGC:
            return (cert.allSatisfy(\.isNumber) && (7...8).contains(cert.count)) ? nil : "7–8 digits"
        case .TAG:
            let alnum = cert.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
            return (alnum && (10...12).contains(cert.count)) ? nil : "10–12 chars"
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd /Users/dixoncider/slabbist && xcodebuild \
  -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. (If `SlabCardDivider` or `FeatureEmptyState` resolve to a different name, grep `slabbist/DesignSystem` / existing usages in `LotsListView.swift` and `ScanShortcutView.swift` — both are already used there — and match.)

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Scanning/PhotoScan/PhotoScanReviewView.swift
git commit -m "feat(ios): PhotoScanReviewView — editable list of detected certs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `PhotoScanCaptureView` + `PhotoScanView` coordinator

**Files:**
- Create: `slabbist/Features/Scanning/PhotoScan/PhotoScanCaptureView.swift`
- Create: `slabbist/Features/Scanning/PhotoScan/PhotoScanView.swift`

No unit test (camera + Vision + view). Verified by build + device pass.

- [ ] **Step 1: Write `PhotoScanCaptureView`**

Create `slabbist/Features/Scanning/PhotoScan/PhotoScanCaptureView.swift`:

```swift
import SwiftUI

/// Capture screen for the photo-scan flow: pick the grader, frame the slabs,
/// tap the shutter. Camera concerns only — OCR + parsing happen in the
/// coordinator (`PhotoScanView`). Mirrors `BulkScanView`'s camera-permission
/// and simulator handling.
struct PhotoScanCaptureView: View {
    @Binding var grader: Grader
    let camera: StillPhotoCamera
    let isCapturing: Bool
    /// Real shutter — coordinator captures a still then OCRs it.
    let onShutter: () -> Void
    /// Simulator-only — feed fixture OCR strings straight to the parser.
    let onSimulate: ([String]) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            AppColor.ink.ignoresSafeArea()
            VStack(spacing: Spacing.l) {
                graderPicker
                cameraArea
                    .clipShape(RoundedRectangle(cornerRadius: Radius.l))
                shutterRow
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.l)
        }
        .overlay(alignment: .topLeading) {
            SecondaryIconButton(systemIcon: "xmark", accessibilityLabel: "Cancel") {
                onCancel()
            }
            .padding(.top, Spacing.l)
            .padding(.leading, Spacing.l)
        }
    }

    private var graderPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Grading company")
            Picker("Grader", selection: $grader) {
                ForEach(Grader.allCases, id: \.self) { g in
                    Text(g.rawValue).tag(g)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("photo-scan-grader-picker")
        }
    }

    @ViewBuilder
    private var cameraArea: some View {
        #if targetEnvironment(simulator)
        ZStack {
            AppColor.surface
            VStack(spacing: Spacing.m) {
                Image(systemName: "camera.metering.center.weighted")
                    .font(.system(size: 40))
                    .foregroundStyle(AppColor.gold.opacity(0.7))
                Text("Simulator — no camera")
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.dim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        switch camera.authorization {
        case .authorized:
            CameraPreview(session: camera.captureSession)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied, .restricted:
            VStack(spacing: Spacing.m) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColor.dim)
                Text("Camera access is required to scan slabs.")
                    .font(SlabFont.sans(size: 15))
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
                PrimaryGoldButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            ProgressView()
                .tint(AppColor.gold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #endif
    }

    private var shutterRow: some View {
        VStack(spacing: Spacing.m) {
            #if targetEnvironment(simulator)
            Button("Simulate photo") {
                // Two PSA-shaped certs + a year to prove filtering, so the
                // simulator exercises the full parse → review path.
                onSimulate(["GEM MT 10", "09812345", "POKEMON 2022", "081234567"])
            }
            .font(SlabFont.sans(size: 14, weight: .semibold))
            .foregroundStyle(AppColor.ink)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.md)
            .background(AppColor.gold, in: Capsule())
            .accessibilityIdentifier("photo-scan-simulate")
            #else
            Button(action: onShutter) {
                ZStack {
                    Circle().fill(AppColor.gold).frame(width: 68, height: 68)
                    if isCapturing {
                        ProgressView().tint(AppColor.ink)
                    } else {
                        Circle().stroke(AppColor.ink, lineWidth: 3).frame(width: 56, height: 56)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isCapturing)
            .accessibilityLabel("Capture photo")
            .accessibilityIdentifier("photo-scan-shutter")
            #endif
        }
    }
}
```

- [ ] **Step 2: Write `PhotoScanView` coordinator**

Create `slabbist/Features/Scanning/PhotoScan/PhotoScanView.swift`:

```swift
import SwiftUI

/// Cover-root coordinator for the photo-scan flow. Owns the grader selection,
/// the still camera, and the capture→OCR→parse→review phase machine. Confirmed
/// certs are recorded through the existing `BulkScanViewModel.record` path.
struct PhotoScanView: View {
    let viewModel: BulkScanViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var grader: Grader = .PSA
    @State private var phase: Phase = .capture
    @State private var camera = StillPhotoCamera()
    @State private var isCapturing = false

    enum Phase: Equatable {
        case capture
        case review([String])
    }

    var body: some View {
        Group {
            switch phase {
            case .capture:
                PhotoScanCaptureView(
                    grader: $grader,
                    camera: camera,
                    isCapturing: isCapturing,
                    onShutter: shutter,
                    onSimulate: { strings in process(recognizedStrings: strings) },
                    onCancel: { dismiss() }
                )
            case .review(let certs):
                PhotoScanReviewView(
                    grader: grader,
                    detectedCerts: certs,
                    existingCertsInLot: existingCerts(for: grader),
                    onCommit: commit,
                    onRetake: { phase = .capture }
                )
            }
        }
        .task {
            #if !targetEnvironment(simulator)
            await camera.requestAuthorization()
            guard camera.authorization == .authorized else { return }
            try? camera.configure()
            camera.start()
            #endif
        }
        .onDisappear { camera.stop() }
    }

    private func shutter() {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            let image = await camera.capture()
            let strings: [String]
            if let image {
                strings = await Task.detached { PhotoTextRecognizer.recognizeText(in: image) }.value
            } else {
                strings = []
            }
            isCapturing = false
            process(recognizedStrings: strings)
        }
    }

    private func process(recognizedStrings: [String]) {
        let certs = PhotoCertParser.extractCerts(from: recognizedStrings, grader: grader)
        phase = .review(certs)
    }

    /// Records each confirmed cert through the existing pipeline (dedup →
    /// cert-lookup → comp), then dismisses back to the live scanner.
    private func commit(_ certs: [String]) {
        for cert in certs {
            let candidate = CertCandidate(
                grader: grader,
                certNumber: cert,
                confidence: 1.0,
                rawText: "photo scan"
            )
            do {
                try viewModel.record(candidate: candidate)
            } catch {
                AppLog.scans.error("photo-scan record failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        dismiss()
    }

    /// Certs already in the lot for the chosen grader, so the review list can
    /// pre-exclude them.
    private func existingCerts(for grader: Grader) -> Set<String> {
        Set(viewModel.recentScans.filter { $0.grader == grader }.map(\.certNumber))
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
cd /Users/dixoncider/slabbist && xcodebuild \
  -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Scanning/PhotoScan/PhotoScanCaptureView.swift \
        ios/slabbist/slabbist/Features/Scanning/PhotoScan/PhotoScanView.swift
git commit -m "feat(ios): PhotoScanView coordinator + capture screen

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Wire into `BulkScanView` (entry point + session pause)

**Files:**
- Modify: `slabbist/Features/Scanning/BulkScan/BulkScanView.swift`

- [ ] **Step 1: Add the presentation state**

In `BulkScanView`'s stored properties (near `@State private var showingManualEntry = false`, ~line 232), add:

```swift
    @State private var showingPhotoScan = false
```

- [ ] **Step 2: Add the toolbar button**

In the `.toolbar { … }` block, add a new `ToolbarItem` immediately **before** the existing manual-entry (`keyboard`) `ToolbarItem` so the order reads photo → keyboard → Done:

```swift
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPhotoScan = true
                } label: {
                    Image(systemName: "text.viewfinder")
                        .foregroundStyle(AppColor.gold)
                }
                .accessibilityLabel("Scan from photo")
                .accessibilityIdentifier("photo-scan-button")
                .disabled(controller.viewModel == nil)
            }
```

- [ ] **Step 3: Add the full-screen cover + live-session pause/resume**

Add this modifier next to the existing `.sheet(isPresented: $showingManualEntry) { … }` (~line 342). The live OCR session is stopped while the cover is up and restarted on dismiss so the two sessions never run concurrently:

```swift
        .fullScreenCover(isPresented: $showingPhotoScan, onDismiss: {
            #if !targetEnvironment(simulator)
            if cameraSession.authorization == .authorized,
               cameraSession.isConfigured,
               !cameraSession.isRunning {
                cameraSession.start()
            }
            #endif
        }) {
            if let viewModel = controller.viewModel {
                PhotoScanView(viewModel: viewModel)
            }
        }
        .onChange(of: showingPhotoScan) { _, isPresented in
            #if !targetEnvironment(simulator)
            if isPresented { cameraSession.stop() }
            #endif
        }
```

- [ ] **Step 4: Build to verify it compiles**

Run:
```bash
cd /Users/dixoncider/slabbist && xcodebuild \
  -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the full test suite (regression)**

Run:
```bash
cd /Users/dixoncider/slabbist && xcodebuild test \
  -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:slabbistTests 2>&1 | tail -15
```
Expected: `** TEST SUCCEEDED **` (PhotoCertParser tests + existing suites all pass).

- [ ] **Step 6: Manual device/simulator verification** (stated coverage gap for camera/Vision/UI)

In the iOS Simulator: open the Scan tab → resume/create a lot → tap the **`text.viewfinder`** button → tap **"Simulate photo"** → confirm the review list shows `09812345` and `081234567` (the `2022` year is **excluded**) → tap **"Add 2 to lot"** → confirm two new rows appear in the scan queue and dismiss returns to the live scanner. On a physical device, additionally verify a real photo of 3–6 PSA slabs is captured and parsed.

- [ ] **Step 7: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanView.swift
git commit -m "feat(ios): add photo-scan entry point to BulkScanView toolbar

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Pick grader before capture → Task 5 (`graderPicker`, grader defaults `.PSA`). ✅
- Camera still only, high-res → Task 3 (`AVCapturePhotoOutput`, `.photo` preset). ✅
- On-device multi-cert extraction for the known grader → Task 1. ✅
- Editable review list (fix/remove, validity flag, already-in-lot) → Task 4. ✅
- Record via existing pipeline (no new write surface/schema) → Task 5 `commit` loops `viewModel.record`. ✅
- Entry point in `BulkScanView` toolbar next to manual entry → Task 6. ✅
- Pause live session while cover up → Task 6 Step 3. ✅
- Error handling: denied (Task 5 capture view denied UI), zero certs (Task 4 empty state), offline (record path unchanged), dupes (parser dedup + Task 4 marker). ✅
- Testing: `PhotoCertParserTests` (Task 1); stated UI/camera gap with manual verification (Task 6 Step 6). ✅

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✅

**Type consistency:** `PhotoCertParser.extractCerts(from:grader:)`, `StillPhotoCamera.capture() -> UIImage?`, `PhotoTextRecognizer.recognizeText(in:) -> [String]`, `PhotoScanReviewView(grader:detectedCerts:existingCertsInLot:onCommit:onRetake:)`, `PhotoScanView(viewModel:)`, `CertCandidate(grader:certNumber:confidence:rawText:)` — names match across tasks and against the existing `CertCandidate` initializer and `Grader`/`ScanStatus` enums. ✅

**Known risk to verify during execution:** design-system symbol names (`SlabCardDivider`, `FeatureEmptyState`, `SecondaryIconButton`, `AppColor.surface`, `SlabFont.mono`) are assumed from existing usage in `LotsListView.swift` / `ScanShortcutView.swift` / `ManualEntrySheet.swift`. If any differ, the Task 4/5 build step will surface it; grep the existing callers and match.
