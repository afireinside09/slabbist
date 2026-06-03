# Robust Pre-Grade — Trustworthy Capture + On-Device Defect Analysis — Design

**Status:** Design proposed 2026-06-03. Awaiting user review, then implementation plan.
**Builds on:** `2026-04-23-pre-grade-estimator-design.md` (the existing pre-grade estimator). This is an enhancement, not a rewrite — the capture flow, `grade-estimate` Edge Function, `grade_estimates` table, report screen, and history all exist and stay.

## 1. Problem

The Pre-grade tab is functionally complete but weak in two ways the user named directly:

1. **Capture is broken.** `GradingCaptureView` invokes `CaptureQualityGate.evaluate(...)` with `blurScore: 200, glareRatio: 0` hardcoded. Those are pass-everything values, so the blur and glare checks never fire — the gate is effectively a no-op. Combined with a manual shutter that grabs whatever frame is on screen, the user "can't even take a clean photo": blurry and glary captures sail through to the grader.

2. **Analysis beyond centering is 100% the LLM's guess.** Centering is measured on-device and passed as ground truth; corners/edges/surface are pure model inference with nothing anchoring them and nothing shown to the user. The user wants TAG-style robustness: a contrast/defect visualization, edge/corner whitening, surface white-spot detection, and crease/print-line flags.

### What TAG actually does (and the honest gap)

TAG's edge is **hardware**: *Photometric Stereoscopic Imaging* — each card is photographed under multiple controlled light angles in a fixed rig, reconstructing surface topology. That is how they reliably catch creases, dents, print lines, and scratches that are invisible under flat, even lighting. Their consumer-facing "Card Vision" is a transparency slider blending the normal photo with a high-contrast enhanced render, plus 800x zoom and per-category "DINGS" (defect) counts across Centering / Corners / Edges / Surface / Dimensions.

A single phone photo per side **cannot** replicate photometric stereo. This design does not pretend otherwise. It delivers what is honestly achievable on-device and is explicit about confidence everywhere it is not.

| TAG capability | Achievable from one flat phone photo? | Approach here |
|---|---|---|
| Centering | Already shipped | Vision rectangle + ratio math (unchanged) |
| Card Vision contrast view | Yes | CoreImage grayscale + local-contrast + edge blend, scrubbable slider |
| Edge/corner whitening | Strong on dark borders, weak on light | Luminance band analysis; low-confidence/omit on light borders |
| White spots / print dots | Partial | Bright local-outlier blob detection, size/contrast filtered |
| Creases / dents / print lines | Weak | Directional line candidates, **always low confidence**, never asserted |

## 2. Decisions (locked with user, 2026-06-03)

- **Static capture only.** No tilt/multi-frame "raking light" capture. Single front + back still per estimate, as today.
- **Capture-first sequencing.** Phase 1 (trustworthy capture) lands and is verified before Phase 2/3 analysis is built on top of it. One spec, phased plan.
- **All four analysis features** in scope: Card Vision contrast slider, edge/corner whitening, white-spot/print-dot detection, crease/print-line candidates.
- **Manual shutter gated by live readiness.** No auto-capture. The shutter button is disabled until every quality gate passes on the live frame; a live readiness chip explains what is failing. The user always presses the button.
- **Persist defects + feed the grader.** Additive `defects` jsonb column on `grade_estimates`; on-device measurements passed to Claude as ground truth alongside centering.
- **Honest whitening on light borders.** Detect border luminance; on light borders, mark whitening low-confidence or omit it rather than fabricate a number.

## 3. Goals & non-goals

### Goals
- Make capture trustworthy: real blur and glare metrics, a live readiness chip, and a shutter that cannot fire on a bad frame; re-gate on the full-res still.
- Add a `CardDefectAnalyzer` that produces measured, normalized-coordinate defect data on-device for both sides.
- Surface the data: a Card Vision contrast/transparency slider with zoom, toggleable overlay layers, and TAG-style defect counts on the report.
- Feed the measurements to the grader as ground truth; update the prompt to treat measured values as fact and candidate lines/creases as low confidence.
- Be explicit about confidence everywhere the flat-photo constraint bites.

### Non-goals
- **No photometric stereo / tilt capture.** Out of scope by decision.
- **No raw card identification, no submission-EV calculator, no new graders.** Inherited from the v1 estimator non-goals.
- **No persisted rendered overlay PNGs.** The contrast view is regenerated on-device from the original; overlays are redrawn from persisted measurements.
- **No estimate-vs-actual feedback loop.** Still post-MVP.

## 4. Phase 1 — Trustworthy capture

### 4.1 Real quality metrics

- **`Core/Vision/BlurMetric.swift` (new)** — Laplacian-variance sharpness. Downscale to grayscale, convolve with a Laplacian kernel via Accelerate/vImage, return the variance. Higher = sharper. Threshold starts at 100 (per the v1 spec), calibrated against fixtures.
- **`Core/Vision/GlareMetric.swift` (new)** — over-exposed pixel ratio. Compute the fraction of pixels with luma > 250 **within the detected card rect** (not the whole frame, so a bright background doesn't trip it). vImage histogram. Threshold < 2%.
- **`Core/Vision/CaptureQualityGate.swift` (edit)** — already shaped to accept `blurScore`/`glareRatio`; remove the hardcoded call-site values and pass the real metrics. Thresholds unchanged from the v1 spec (min 1500×2100, blur ≥ 100, glare < 2%, card-detection confidence ≥ 0.85, aspect ~0.71 ±10%).

### 4.2 Live readiness + gated shutter

Live per-frame gating does not exist today — the gate runs only on the captured still. We add a throttled (~4 Hz) live frame analyzer on the grading capture screen.

- **Frame source.** `CameraSession` already owns an `AVCaptureVideoDataOutput` (used by bulk-scan OCR). The grading screen subscribes to frames through its own analyzer; the grading flow has its own session/screen so there is no contention with OCR. If exposing a second consumer on the existing VDO is awkward, the analyzer attaches its own VDO delegate on the grading session.
- **Per-frame pipeline (throttled, off main thread):** downscaled card detection (reuse `CardRectangleDetector`) → blur + glare on the downscaled frame → centering preview. Produces a `CaptureReadiness { cardDetected, aspectOK, sharp, glareOK, centeredEnough, steady }`.
- **Steadiness.** Track card-rect centroid jitter across the last ~5 frames; `steady` requires low jitter. Prevents the shutter enabling on a momentarily-good but shaking frame.
- **Shutter gating.** The capture button is **disabled** unless all readiness flags are true. The existing `QualityChip` shows the first failing reason in actionable copy ("Too blurry — hold steady", "Glare on the left", "Move closer", "Card not detected", "Hold still"). `CardOutlineOverlay` strokes gold when ready, muted otherwise.
- **Still re-gate.** On press, capture the full-res still and re-run the full gate (real blur/glare on the still). A failure pops a retake with the specific reason rather than proceeding — this catches the case where the still differs from the preview.

### 4.3 Phase 1 verification
- Unit tests: `BlurMetric` on sharp vs Gaussian-blurred fixtures asserts the threshold splits them; `GlareMetric` on clean vs blown-highlight fixtures asserts the ratio crosses 2%.
- Manual: a blurry/glary card keeps the shutter disabled with the right chip; a clean card enables it and the captured still passes re-gating.

## 5. Phase 2 — On-device defect analysis

New module `Core/Vision/Grading/` with a `CardDefectAnalyzer` actor. Input: full-res front/back `UIImage` + the detected card rect. Output `CardDefectAnalysis` (all coordinates **normalized 0…1** so overlays redraw after the original image is purged):

```swift
struct CardDefectAnalysis: Codable, Sendable, Equatable {
    var border: BorderProfile          // .dark | .light | .mixed  (drives whitening confidence)
    var whitening: WhiteningReport     // per-edge + per-corner exposure %, severity, confidence
    var whiteSpots: [SurfaceSpot]      // normalized centroid, radius, intensity
    var lineCandidates: [LineCandidate]// normalized segment endpoints, orientation, strength, confidence
}
```

The analyzer runs off the main thread on a shared Metal-backed `CIContext`; target < 2s for both sides combined.

### 5.1 Card Vision contrast slider
CoreImage pipeline producing an "enhanced" render: grayscale (luma matrix) → local-contrast / CLAHE-style tone boost (`CIColorControls` contrast + tone curve, `CIHighlightShadowAdjust`) → optional `CIEdges` blend so whitening and lines pop. A `CardVisionRenderer` caches the enhanced `CIImage`. The report shows a 0→100% transparency slider blending original ↔ enhanced (mirrors TAG's slider) with pinch-zoom. Regenerated on-device from the stored original; after the 30-day purge only the thumbnail remains, so the slider operates at thumbnail fidelity (stated in the report).

### 5.2 Edge/corner whitening
1. Sample a thin band just inside the detected card rect around the full perimeter; compute mean luma to classify `border` as `.dark`, `.light`, or `.mixed`.
2. **Dark border:** whitening = ratio of bright pixels (luma above an adaptive threshold relative to the band mean) within the band, computed per-edge (T/R/B/L) and per-corner (TL/TR/BL/BR). Emit exposure % + severity per region.
3. **Light/mixed border:** whitening is largely invisible against a light border → emit `confidence: .low` with no fabricated severity, or omit affected regions. The grader and UI are told this is unmeasurable here.
Overlay: heatmap strokes along regions exceeding threshold. Numbers feed the grader as ground truth.

### 5.3 White-spot / print-dot detection
Over the artwork region (inside the border band): detect small bright local-outlier blobs via top-hat morphology or local-contrast thresholding. Filter by **size** (small) and **local contrast** (must stand out from its neighborhood) to suppress intentional bright art. Emit normalized centroids + radii + intensity. Drawn as ring markers; framed as "possible surface marks (N)". Reported as candidates, not confirmed defects.

### 5.4 Crease / print-line candidates
Sobel gradient magnitude + orientation (or `VNDetectContours`) to find long, thin, near-straight, low-curvature features spanning a meaningful fraction of the card. Print lines: thin, often full-width, consistent orientation. Creases: longer, may bend. **Always low confidence** under flat light — emitted as dashed candidate markers, never asserted as fact in copy or prompt. Honors the static-capture decision.

## 6. Phase 3 — Feed the grader + report

### 6.1 Backend (`supabase/functions/grade-estimate`)
- Request body adds `defects_front` and `defects_back` (the `CardDefectAnalysis` shape: border type, whitening per-region %, white-spot count, line-candidate summary).
- Prompt update: on-device measurements (centering + whitening %) are **ground truth — do not re-estimate**. White spots are **candidates**. Line/crease candidates are **low confidence — treat as possible, never assert a crease/line exists**. Each sub-grade note must reference a measurement or a specific visible feature. Keep the hyper-critical, pessimistic framing and the existing composite/confidence bounds.
- The grader uses whitening to anchor the edges/corners sub-grades and the spot/line candidates to inform surface, without inflating confidence.

### 6.2 Data model
Additive migration on `grade_estimates`:

| column | type | notes |
|---|---|---|
| `defects` | `jsonb` nullable | `{ front: CardDefectAnalysis, back: CardDefectAnalysis }`; null for pre-existing rows |

No other schema changes. The DTO (`GradeEstimateDTO`) and `GradeEstimateRepository` gain the `defects` field. Persisting the analysis lets the report redraw overlays after the 30-day image purge and keeps an audit trail. RLS, bucket policies, and the purge job are unchanged.

### 6.3 Report screen
- **Card Vision section:** front/back with the transparency slider + pinch-zoom and toggleable overlay layers (whitening / spots / lines), each legend-coded. Overlays drawn from the normalized coordinates in `defects` (work even after image purge; the underlying contrast view degrades to thumbnail fidelity).
- **Defect summary:** TAG-style counts — e.g. "Whitening: 3 edges affected • Surface marks: 2 possible • Lines: 1 possible (low confidence)". Tapping a count highlights its markers on the image.
- Existing sub-grade cards stay; the edges/corners notes now cite measured whitening %.
- **Footer addition:** "Surface topology — creases, dents — can't be fully assessed from a flat photo; those flags are possibilities, not confirmations." Existing disclaimer footer remains.

## 7. Files

**New**
- `Core/Vision/BlurMetric.swift`, `Core/Vision/GlareMetric.swift`
- `Core/Vision/Grading/CardDefectAnalyzer.swift` and supporting types (`CardDefectAnalysis`, `WhiteningReport`, `SurfaceSpot`, `LineCandidate`, `BorderProfile`)
- `Core/Vision/Grading/CardVisionRenderer.swift`
- `Features/Grading/Report/CardVisionView.swift` (slider + zoom + overlay layers), `Features/Grading/Report/DefectSummaryView.swift`
- Migration `supabase/migrations/<ts>_grade_estimates_defects.sql`

**Edited**
- `Core/Vision/CaptureQualityGate.swift` (real metrics, no hardcoded values)
- `Features/Grading/Capture/GradingCaptureViewModel.swift` (live readiness loop, steadiness, gated shutter, still re-gate)
- `Features/Grading/Capture/GradingCaptureView.swift` (remove `blurScore: 200, glareRatio: 0`; wire live frames; disabled-shutter UI)
- `Features/Grading/Capture/QualityChip.swift`, `CardOutlineOverlay.swift` (readiness states)
- `Features/Scanning/Camera/CameraSession.swift` (expose a frame consumer for grading, if needed)
- `Core/Data/DTOs/GradeEstimateDTO.swift`, `Core/Data/Repositories/GradeEstimateRepository.swift` (defects field)
- `Features/Grading/Report/GradeReportView.swift` (Card Vision + defect summary sections, footer)
- `supabase/functions/grade-estimate/{index.ts,types.ts,prompt.ts}` (defects inputs + prompt rules)

## 8. Performance & UX constraints
- All Vision/CoreImage work off the main thread; the live readiness loop throttled to ~4 Hz and operating on a downscaled frame.
- `CardDefectAnalyzer` target < 2s for both sides; show the existing analysis spinner.
- Shared Metal-backed `CIContext` reused across renders; enhanced render cached.
- Design system: `.impeccable.md` palette/typography for the new report sections and overlay legends; overlay marker colors must meet WCAG AA contrast against both the original and enhanced renders.

## 9. Risks

| Risk | Mitigation |
|---|---|
| On-device metrics are wrong and over/under-reject captures | Thresholds from the v1 spec, calibrated against a fixture set; unit tests pin behavior; chip copy is actionable so the user can correct. |
| Whitening fabricated on light-bordered cards | Border-luminance classification; low-confidence/omit on light borders; grader told it is unmeasurable. |
| Crease/line false positives erode trust | Always low confidence, "possible" copy, dashed markers, prompt forbidden from asserting. |
| White-spot detector flags intentional bright art | Size + local-contrast filtering; framed as candidates; tap-to-inspect lets the user dismiss visually. |
| Defect analysis blows the latency budget | Downscale for detection, full-res only for final measure; off-thread; < 2s target; spinner. |
| Overlays break after 30-day image purge | Normalized coordinates persisted in `defects`; markers redraw on the thumbnail; contrast slider degrades gracefully with a note. |
| Live frame analyzer contends with OCR VDO | Grading has its own screen/session; analyzer uses its own consumer/delegate. |

## 10. Open questions for the implementation plan
- Exact Laplacian kernel and downscale size for `BlurMetric`; calibrate the 100 threshold against fixtures.
- Adaptive whitening threshold formula (offset above band mean) and the dark/light border cutoff.
- Top-hat structuring-element size and contrast cutoff for white spots.
- Line-candidate minimum length/curvature/strength to qualify as a "possible" flag.
- Whether to render the enhanced Card Vision image via chained CIFilters or a small Metal shader (pick during plan; CIFilter chain is the default).
- Prompt wording and a small re-calibration pass against the existing test-card set now that measured defects are inputs.
