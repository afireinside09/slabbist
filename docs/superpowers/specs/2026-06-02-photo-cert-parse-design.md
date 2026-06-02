# Photo Cert Parse — Design Spec

**Feature:** Scan a still photo of a stack of slabs and parse out all cert numbers
**Date:** 2026-06-02
**Status:** Design approved; awaiting implementation plan

## Summary

A third slab-input method on the Scan tab, alongside live continuous OCR and manual entry. The user **picks the grading company first**, takes **one still photo** of several slabs laid out in front of them, and Slabbist extracts every cert number of that grader's format from the image. The detected certs land in an **editable review list** where the user fixes misreads and drops false positives, then taps "Add N to lot." Each confirmed cert flows through the existing `BulkScanViewModel.record(candidate:)` path — so cert-lookup and eBay comp fire automatically, identically to a manually-entered or live-scanned slab.

Because the user declares the grader up front, grader attribution is solved by user input. There is **no spatial / per-slab grader inference** — extraction collapses to "find every cert-shaped run matching the one selected grader's format in the photo."

## Goals

1. Let a dealer capture a tray of same-grader slabs in one shot instead of flipping through them one at a time.
2. Reuse the existing record → cert-lookup → comp pipeline with **no new write surface, no outbox changes, no schema changes**.
3. Keep extraction **on-device and offline-first** (Vision OCR), consistent with the rest of the scan flow.
4. Preserve the "defensible number" bar: the user reviews and corrects detected certs before they become scans.

## Non-goals

- **Mixed-grader photos / spatial grader attribution.** One photo = one grader, declared before capture. Explicitly out of scope.
- **Photo library import.** Camera still-capture only for v1. (Cheap to add later via `PhotosPicker`; leave the parser independent of capture source so it's a clean seam.)
- **Server-side vision-LLM extraction.** Would break offline-first and add Edge Function + cost/latency. Not in v1.
- **Label-vs-cert fraud cross-check.** Out of scope (as in the bulk-scan spec).
- **Batch undo beyond the review list.** The review list is the correction surface; after commit, corrections happen in the existing scan queue.

## Architecture

### User flow & entry point

A new **photo icon** in `BulkScanView`'s top-right toolbar, next to the existing keyboard (manual-entry) icon. It lives **inside** `BulkScanView` — which always has an active lot to record into — exactly like manual entry. It is **not** on the Scan-tab landing (`ScanShortcutView`).

Tapping it presents a **full-screen cover**:

```
toolbar:  ‹Back   Friday Haul   [▦ photo] [⌨ manual] [Done]›
                                    │
                                    ▼  full-screen cover
   ┌─ Pick grader:  [ PSA | BGS | CGC | SGC | TAG ] ──┐   ← segmented, defaults PSA
   │  ┌─ live still preview ─────────────────────┐     │
   │  │   [slab] [slab] [slab]                    │     │
   │  │   [slab] [slab] [slab]                    │     │
   │  └───────────────────────────────────────────┘    │
   │                ( ● capture )                       │
   └─────────────────────────────────────────────────┘
                       │ shutter
                       ▼
   Found 6 PSA slabs
   ┌────────────────────────────┐
   │ ✓ 09812345                 │
   │ ✓ 08123456                 │
   │ ✓ 09987654   [edit digits] │
   │ ⚠ 0981234    too short     │ ← fails PSA format, flagged
   │ • 09812345   already in lot│ ← dupe of existing scan, pre-excluded
   └────────────────────────────┘
              [ Add 5 to lot ]  → dismiss, back to live scanner
```

### Camera coexistence

`BulkScanView` already runs a live `AVCaptureSession` (video-data output for continuous OCR). The photo flow needs a **high-resolution still** (`AVCapturePhotoOutput`) — live video frames are downscaled and too soft to reliably read many small labels in one frame.

**Decision:** the capture flow owns its **own** capture session, and the live session is **paused while the full-screen cover is up** (resumed on dismiss). The two sessions never run concurrently, avoiding resource conflict. Rejected alternative: adding a photo output to the shared `CameraSession`, which entangles its live-OCR responsibility.

### Components

Each unit has one job and a well-defined interface.

**1. `PhotoCertParser`** — pure, no Vision/UIKit dependency, fully unit-testable. The heart of the feature.

```swift
enum PhotoCertParser {
    /// Given OCR text lines and the user-declared grader, return every
    /// distinct cert number matching that grader's format, in stable
    /// order of first appearance.
    static func extractCerts(from recognizedStrings: [String], grader: Grader) -> [String]
}
```

- Builds the selected grader's format pattern, reusing the per-grader regexes already in `CertOCRPatterns` (PSA `\d{8,9}`, BGS/CGC `\d{10}`, SGC `\d{7,8}`, TAG `[A-Z0-9]{10,12}`).
- Finds **all** matches across all lines (not just the first — the existing `match`/`matchPermissive` stop at the first hit; this is the new multi-match behavior).
- Length-validates, **dedupes**, preserves first-appearance order.
- This is where false positives (years like `2022`, population counts) are filtered by the format/length rule.

**2. `StillPhotoCamera`** — small `@Observable` wrapper around `AVCaptureSession` + `AVCapturePhotoOutput`, parallel to `CameraSession` but for one-shot stills. Owns authorization, `configure()`, `capture() async -> CGImage?`. Isolated from the live-OCR `CameraSession`.

**3. `PhotoScanCaptureView`** — SwiftUI. Grader segmented picker (top, defaults PSA) + still preview + shutter. On capture: get the `CGImage` → one-off `VNRecognizeTextRequest` (`.accurate`, `usesLanguageCorrection = false`, same config as the live path) → `PhotoCertParser.extractCerts(…, grader:)` → push to the review view.

**4. `PhotoScanReviewView`** — SwiftUI. Editable list. Each detected cert is a row: `TextField` for digit fixes, ✕/swipe to remove, per-grader format-validity flag (reusing `ManualEntrySheet`'s `validate` logic), and a muted "already in lot" marker for certs matching an existing scan in this lot. "Add N to lot" loops the survivors and dismisses.

### Data flow

```
pick grader ─▶ capture still ─▶ Vision OCR ─▶ PhotoCertParser.extractCerts
                                                        │
                                                        ▼  [cert, cert, …]
                                            PhotoScanReviewView (edit/remove)
                                                        │  for each confirmed:
                                                        ▼
        CertCandidate(grader: picked, certNumber: cert, confidence: 1.0,
                      rawText: "photo scan")
                                                        │
                                                        ▼
                          viewModel.record(candidate:)   ← EXISTING path
                          (dedup → cert-lookup → comp-fetch, all automatic)
```

No new write surface, no outbox kinds, no schema changes. A photo-scanned slab is indistinguishable downstream from a manual or live-scanned one.

### Error handling

- **Camera permission denied** → reuse `BulkScanView`'s existing "Open Settings" denied UI pattern.
- **Capture fails** → inline error; stay on the capture screen.
- **Zero certs found** → review screen shows an empty state ("No PSA certs found — try better lighting or move closer") with a "Retake" action.
- **Offline** → unchanged; `record()` lands scans as `pendingValidation` and lookups retry when connectivity returns.
- **Duplicate reads within one photo** → collapsed by the parser's dedup.
- **Duplicates of existing lot scans** → pre-excluded (marked, unchecked) in the review list; `record()`'s `isDuplicateLocally` is a backstop no-op anyway.

### Testing

- **`PhotoCertParserTests`** — the real coverage (per repo Rule 9, tests encode *why*). Fixture OCR string arrays → assert the exact extracted set:
  - multiple valid PSA certs in one photo → all returned;
  - the same cert read twice → deduped to one;
  - a 4-digit year / a population number present → **excluded** (this test fails if length-filtering regresses);
  - BGS/CGC 10-digit; SGC 7–8 digit; TAG alphanumeric 10–12;
  - empty input → empty output.
- **Camera / Vision / review UI** — not unit-tested (camera + Vision are non-deterministic in a unit harness). Covered by the parser tests plus manual on-device verification. **Known coverage gap, stated rather than faked.**

## Open questions / future seams

- **Library import** — `PhotoScanCaptureView` is the only capture-source-specific unit; the parser takes plain `[String]`, so adding a `PhotosPicker` source later is isolated.
- **Ordering** — review-list order is first-appearance from OCR; if users want top-to-bottom reading order, bounding-box sorting can be added in `PhotoScanCaptureView` without touching the parser.
