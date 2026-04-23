# Pre-grade Estimator — Design

**Status:** Design approved 2026-04-23. Awaiting implementation plan.
**Sub-project home:** Side-quest feature, lives next to sub-project 9 (raw card ID) and 10 (grading workflow). Designed so sub-project 9 can later attach reports to raw scans inside a lot.

## 1. Problem

Three user classes want to know what grade a raw (ungraded) card would receive *before* spending the submission fee:

- **Buyer at the counter (primary)** — vendor evaluating a raw card a walk-in is trying to sell. Needs an anchor for "what's this worth assuming a Y grade?"
- **Submitter** — vendor (or operator) deciding which raw cards in inventory are worth sending to PSA/BGS/CGC.
- **Collector** — non-vendor user who wants a grade preview before paying for grading themselves.

Existing OCR is for graded slab cert numbers. This feature requires fundamentally different vision work: centering, corners, edges, and surface analysis of a raw card from front and back photos.

## 2. Goals & non-goals

### Goals
- Generate a hyper-critical, sub-grade-by-sub-grade PSA-style estimate from a front + back photo pair.
- Per-axis explanation that anchors to something visible in the photo or to a measured ratio.
- Composite predicted grade with a verdict (submit at tier X / don't submit / borderline reshoot).
- PSA primary scale; BGS/CGC/SGC available under a toggle.
- Persistent personal history with photo retention rules.
- Refuse to grade bad photos with a specific reason rather than producing a junk score.

### Non-goals (v1)
- **Raw card identification** — user already knows what card it is. The estimator does not look up the card in `tcg_products` or any catalog.
- **Submission cost / EV calculator** — sub-project 10 territory.
- **Estimate-vs-actual feedback loop** — comparing prediction against the real grade after submission is post-MVP.
- **Per-grader training data** — the toggle uses the same sub-grades with documented per-grader composite math, not separately trained models.
- **Iterative refinement** — no "here's a better corner photo, regrade." Single-shot per estimate.
- **Bulk grading inside a lot** — single-card flow only in v1. Sub-project 9 wires it into raw scans later.

## 3. User flow

1. User taps **"Grade card"** in the shell.
2. **First-run consent** — full-screen disclaimer ("Estimate, not a guarantee. Real grades depend on submission tier, current grader trends, and minor surface defects not visible in photos."). Stored as `user_consents.pre_grade_estimator_v1 = true`. Skipped on subsequent runs.
3. **Guided front capture** — full-screen camera, card-outline overlay, distance prompt, real-time centering preview, glare/blur warning chip. The pre-flight quality gate runs locally before allowing capture.
4. **Flip prompt** — "Flip the card. Same orientation."
5. **Guided back capture** — same overlay and same gate.
6. **Library fallback** — a "Use existing photos" link on the capture screen drops to the iOS photo picker, accepts two images, runs the same quality gate before upload.
7. **Upload + analysis** — spinner with "Analyzing — usually 6-12 seconds."
8. **Report renders** — sub-grade cards, composite, verdict, disclaimer footer.
9. **Auto-saved** to history. Star, share (PNG export), or delete from the report or the history list.

### Error paths
- Quality gate refuses photo → specific reason (blur / glare / too small / no card detected) + retake button.
- LLM call fails or times out (>20s) → "Couldn't analyze this card. Try again." Retry uses cached photos; user is not charged a rate-limit slot for failures.
- Rate limit hit (20/day) → "Daily limit reached. Resets at midnight UTC."

## 4. Architecture

```
┌──────────────────────┐     ┌────────────────────────────┐     ┌──────────────────────┐
│  iOS capture flow    │     │  Supabase Storage          │     │  Edge Function       │
│  - guided camera     │───▶│  grade-photos/<user>/...   │───▶│  /grade-estimate     │
│  - quality gate      │     │  (signed URL upload)       │     │  - calls Claude vis  │
│  - on-device center  │     └────────────────────────────┘     │  - persists row      │
└──────────────────────┘                                         │  - returns report    │
         │                                                        └──────────────────────┘
         │                                                                  │
         │                                                                  ▼
         │                                                        ┌──────────────────────┐
         │◀──────────────────────────────────────────────────────│  grade_estimates     │
         │                                                        │  table + Storage     │
         │                                                        └──────────────────────┘
         ▼
   Report screen (renders persisted row)
```

Centering is measured client-side and passed to the function so the LLM never has to estimate the one thing it's worst at. The LLM gets the images plus the measured ratios as ground truth.

## 5. iOS implementation

### New files
- `Features/Grading/GradingShellEntry.swift` — adds the entry point in the shell tab bar / nav.
- `Features/Grading/Capture/GradingCaptureView.swift` — front + back capture flow.
- `Features/Grading/Capture/GradingCaptureViewModel.swift` — state machine: `consent → front → back → uploading → done`.
- `Features/Grading/Report/GradeReportView.swift` — full report screen.
- `Features/Grading/History/GradeHistoryView.swift` — list view.
- `Features/Grading/History/GradeReportRow.swift` — list row.
- `Core/Vision/CardRectangleDetector.swift` — wraps `VNDetectRectanglesRequest`, returns the inner card rectangle in normalized image coordinates.
- `Core/Vision/CaptureQualityGate.swift` — applies four checks and returns either `.ok(QualityMetadata)` or `.rejected(reason: String)`.
- `Core/Vision/CenteringMeasurement.swift` — given a detected rectangle and the underlying image bounds, returns `{left, right, top, bottom}` ratios in 0...1.
- `Core/Data/Repositories/GradeEstimateRepository.swift` — fetch / list / delete estimates.
- `Core/Data/DTOs/GradeEstimateDTO.swift` — Codable mirror of the table row.

### Reused
- `CameraSession` from `Features/Scanning/Camera/` — extended to support a "still capture" mode alongside the existing live OCR mode.
- `SupabaseRepository` — for the storage upload and function invocation.

### Quality gate thresholds
- Min resolution: 1500×2100 (sufficient for surface defect inspection at PSA scale).
- Blur: Laplacian variance ≥ 100 (calibrate against test set; threshold is the v1 starting point).
- Glare: over-exposed pixel ratio (pixels with luma > 250) must be < 2% of frame.
- Card detection confidence: `VNDetectRectanglesRequest` returns ≥ 0.85 confidence on a quad with aspect ratio in the card range (~0.71 for standard pokemon cards, ±10%).

All four are measured every frame in the capture preview; the capture button stays disabled with a labeled chip ("Too blurry — hold steady") until all four pass. After the static capture, gates re-run on the full-resolution still and a failure pops a retake.

## 6. Backend

### Edge Function: `supabase/functions/grade-estimate/index.ts`

**Inputs (POST JSON):**
```json
{
  "front_image_path": "grade-photos/<user>/<estimate-id>/front.jpg",
  "back_image_path":  "grade-photos/<user>/<estimate-id>/back.jpg",
  "centering_front":  {"left": 0.48, "right": 0.52, "top": 0.50, "bottom": 0.50},
  "centering_back":   {"left": 0.49, "right": 0.51, "top": 0.50, "bottom": 0.50},
  "include_other_graders": false
}
```

**Steps:**
1. Validate JWT, derive `user_id`.
2. Check `grade_estimates` count for `(user_id, created_at::date = today)` against the daily limit. Reject with 429 if at limit.
3. Generate signed URLs for both image paths.
4. Build the prompt (see prompt section).
5. Call Claude Sonnet 4.6 vision with both images + the structured prompt. `max_tokens` 1500. Hard 18s timeout (UI shows 20s).
6. Validate the JSON response against the schema. On schema failure, retry once. If second attempt also fails, return 502.
7. Insert row into `grade_estimates`.
8. Return the persisted row.

### Prompt design

System prompt establishes:
- Role: "You are a hyper-critical card grader. Your job is to give the most pessimistic defensible PSA grade for the card in these photos. Real submissions cost real money; over-estimating is worse than under-estimating."
- Hard rules:
  - Centering ratios are provided as ground truth — use them, do not re-estimate centering.
  - For corners, edges, and surface: if you cannot clearly see the relevant area in the photo, score it as if it has wear (do not score generously when the photo is ambiguous).
  - Each sub-grade explanation must reference a specific visible feature (a corner, an edge segment, a surface area) or a measured ratio. No generic prose.
  - The composite is bounded by the lowest sub-grade: composite must be no higher than `min(sub_grades) + 1`.
  - Output must validate against the JSON schema. Anything else is a failure.

User prompt includes:
- The two images (front, back).
- The four centering ratios (front and back) with the implied PSA centering grade tier they fall in.
- The grader-toggle flag.

Required output schema:
```json
{
  "sub_grades": {
    "centering": 1-10, "corners": 1-10, "edges": 1-10, "surface": 1-10
  },
  "sub_grade_notes": {
    "centering": "string referencing measured ratios",
    "corners": "string referencing specific corners (TL/TR/BL/BR, front/back)",
    "edges": "string referencing specific edges",
    "surface": "string referencing specific surface areas"
  },
  "composite_grade": "number (PSA scale, may be .5)",
  "confidence": "low|medium|high",
  "verdict": "submit_economy|submit_value|submit_express|do_not_submit|borderline_reshoot",
  "verdict_reasoning": "string",
  "other_graders": null | {
    "bgs": {...same shape as PSA but using BGS scale and tolerances...},
    "cgc": {...},
    "sgc": {...}
  }
}
```

**Confidence floor rule** — embedded in the prompt: if `confidence` is `low`, the composite must be at most the median of the sub-grades minus 1, never higher.

## 7. Data model

### Table: `grade_estimates`

| column | type | notes |
|---|---|---|
| `id` | `uuid` pk default `gen_random_uuid()` | |
| `user_id` | `uuid` fk `auth.users(id)` not null | |
| `scan_id` | `uuid` fk `scans(id)` nullable | sub-project 9 hook — null in v1 |
| `front_image_path` | `text` not null | path in `grade-photos` bucket |
| `back_image_path` | `text` not null | |
| `front_thumb_path` | `text` not null | 400×560 thumbnail |
| `back_thumb_path` | `text` not null | |
| `images_purged_at` | `timestamptz` nullable | set when originals are removed by purge job |
| `centering_front` | `jsonb` not null | `{left, right, top, bottom}` |
| `centering_back` | `jsonb` not null | |
| `sub_grades` | `jsonb` not null | `{centering, corners, edges, surface}` |
| `sub_grade_notes` | `jsonb` not null | parallel keys to `sub_grades` |
| `composite_grade` | `numeric(3,1)` not null | PSA scale, may include `.5` |
| `confidence` | `text` not null check `('low','medium','high')` | |
| `verdict` | `text` not null check `('submit_economy','submit_value','submit_express','do_not_submit','borderline_reshoot')` | |
| `verdict_reasoning` | `text` not null | |
| `other_graders` | `jsonb` nullable | populated only when toggle requested |
| `model_version` | `text` not null | e.g. `"claude-sonnet-4-6@2026-04-23"` for replay |
| `is_starred` | `boolean` not null default false | |
| `created_at` | `timestamptz` not null default `now()` | |

### Indexes
- `(user_id, created_at desc)` for the history list.
- `(user_id, is_starred) where is_starred` for starred filter.
- `images_purged_at where images_purged_at is null` for the purge job.

### RLS
- `select` / `update` / `delete` allowed where `user_id = auth.uid()`.
- `insert` only via the Edge Function (which runs with service role and sets `user_id` from the JWT).

### Storage bucket: `grade-photos`
- Private, per-user prefix: `grade-photos/<user_id>/<estimate_id>/{front,back,front_thumb,back_thumb}.jpg`.
- Bucket-level RLS allows the user to read their own prefix only.
- Function uploads use service-role client to write.

### Purge job
- Daily Supabase scheduled function: select rows where `images_purged_at is null and created_at < now() - interval '30 days'`. For each, delete `front_image_path` and `back_image_path` from storage (keep thumbs), set `images_purged_at = now()`.
- Report screen handles `images_purged_at != null` by hiding the "view full image" affordance and showing the thumbnail only.

## 8. UI

### Capture screen
- Full-screen camera preview.
- Card outline overlay (animated stroke when card aligned, dimmed otherwise).
- Real-time centering readout in two thin bars at top and side ("L/R 48/52, T/B 50/50").
- Quality chip below capture button when a check fails ("Too blurry", "Glare on left", "Move closer", "Card not detected"). Capture button disabled.
- Flip prompt between sides — animated card icon rotating, "Flip the card. Same orientation."
- Library fallback link bottom-left.

### Report screen
- **Header**: composite grade in display weight ("PSA 7.5"), confidence chip, verdict pill ("Submit at Value tier") with verdict reasoning beneath.
- **Sub-grade cards** (4 stacked cards, top-to-bottom: centering, corners, edges, surface):
  - Score (1–10) on the right.
  - One-paragraph note on the left.
  - "Data point" line at the bottom for centering ("Front L/R 48/52, T/B 50/50 — within PSA 9 tolerance"); for the others, the model's referenced visible feature.
- **Other graders toggle** — collapsed by default. Expanded shows BGS/CGC/SGC composites and sub-grades in a dense table.
- **Photos** — front/back thumbnails, tap to expand (full image while available, thumbnail only after 30-day purge).
- **Disclaimer footer** — always visible.
- Actions: star, share (PNG export of the report), delete.

### History screen
- List of past reports: thumbnail (front), composite grade, verdict, date.
- Filter chips: all / starred / verdict type / grade range.
- Search by date.
- Tap → report screen.

## 9. Disclaimer & liability

- First-run full-screen consent before any capture.
- Persistent footer on every report: *"Estimate only — not a guarantee. Real grades depend on submission tier, current grader trends, and minor surface defects not visible in photos. Slabbist is not responsible for grading outcomes."*
- Verdict copy uses probabilistic language ("Likely PSA 8", "Borderline", never "This is a PSA 9").
- The PSA "Other graders" disclaimer notes that BGS/CGC/SGC predictions use the same sub-grades with adjusted composite math, not separately calibrated models.

## 10. Rate limits & cost

- 20 estimates per user per 24 hours (rolling on UTC midnight).
- Buyer-at-counter operator accounts that hit this regularly: revisit limit after first month of usage data.
- Approximate cost per estimate: $0.01–$0.04 (Claude Sonnet vision, 2 images, ~1500 output tokens).
- Failed analyses (server errors, timeouts) do not consume a rate-limit slot.

## 11. Telemetry

- Log per estimate: `user_id`, `created_at`, `composite_grade`, `verdict`, `confidence`, `model_version`, latency, gate-rejection counts during capture, whether other-graders toggle was used.
- Aggregate dashboard (post-launch): grade distribution, verdict distribution, rate-limit hits, gate-rejection breakdown by reason. These signal whether the prompt is biased generous, whether the gate is too strict, and whether the rate limit is binding.

## 12. Migration plan

Single migration adds the `grade_estimates` table, the storage bucket and bucket policies, and the daily purge cron schedule. No changes to existing tables. The `scan_id` foreign key targets the existing `scans` table from sub-project 5 — that table is already live, so the FK can be added directly.

## 13. Risks

| Risk | Mitigation |
|---|---|
| LLM invents details not visible in the photo | Prompt requires each sub-grade note to reference a specific visible feature; confidence-floor rule pins composite when the model is uncertain. |
| User blames the camera, not the card | Pre-flight quality gate refuses bad inputs with specific reasons; no grade is ever generated from a rejected photo. |
| Cost runaway from a heavy user | 20/day rate limit; on-device centering avoids one round-trip class; failed calls don't consume slots. |
| Liability from a bad prediction | Persistent disclaimer, probabilistic copy, first-run consent gate, no "guarantee" language anywhere in the app. |
| Storage cost from accumulated images | 30-day auto-purge to thumbnail-only. |
| LLM schema drift across model upgrades | `model_version` recorded per row; schema validation in the function with a single retry; failures return 502 rather than corrupt data. |
| Per-grader predictions in (B) toggle are fictional calibration | Toggle is documented as "same sub-grades with adjusted composite math," not separately trained. Real per-grader calibration is post-MVP. |

## 14. Open questions for the implementation plan

- Exact prompt text and few-shot examples for the LLM call — drafted in plan, refined against a small test set of 10–20 cards with known grades before launch.
- Laplacian-variance blur threshold — start at 100, calibrate against the test set.
- Card aspect ratio tolerance — Pokémon-only at v1, but tolerance band needs picking (sports cards are slightly different).
- Whether to vendor a small Swift Laplacian implementation or use Accelerate's vDSP — pick during plan.
- Thumbnail generation: client-side before upload vs server-side in the Edge Function — recommend client-side to save the round-trip.
