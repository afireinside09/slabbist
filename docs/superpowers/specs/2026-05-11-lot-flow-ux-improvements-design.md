# Lot Flow UX Improvements

**Date:** 2026-05-11  
**Status:** Approved

## Problem

Several friction points exist in the lot → offer flow:

1. The "Adjust" button on the Lot detail margin row only opens a simple per-lot override picker. Operators who want to change the store-wide margin ladder must leave the lot and navigate to Settings → More → Margin ladder, breaking context.
2. After tapping "Send to offer" (which creates the offer), the operator must then find and tap a separate "Resume offer" NavigationLink to reach the Offer review screen — an unnecessary extra step.
3. "Resume offer", "Bounce back", and "Decline" render as plain text / unstyled links. They are not obviously tappable and the visual hierarchy is unclear relative to primary actions.
4. After tapping "Bounce back" in the Offer review screen, the lot state reverts to `.priced` but the operator stays on the Offer review screen. They must manually navigate back to the Lot detail page.

## Intended Outcome

- One sheet handles both lot-level margin override and store-level ladder editing.
- "Create Offer" (renamed from "Send to offer") takes the operator directly to Offer review in a single tap.
- Secondary actions ("Resume offer", "Bounce back", "Decline") have clear button affordance but are visually subordinate to the primary gold buttons.
- "Bounce back" automatically returns to the Lot detail page.

---

## Changes

### 1. `LotMarginSheet` (new file: `Features/Offers/LotMarginSheet.swift`)

Replaces `MarginPickerSheet` as the target of the "Adjust" button in `LotDetailView`.

**Interface:**
```swift
struct LotMarginSheet: View {
    let currentPct: Double
    let storeId: UUID
    let onSelectLotMargin: (Double) -> Void
}
```
Uses `@Environment(\.modelContext)`, `SessionStore`, and `OutboxKicker` from the environment — same pattern as `MarginLadderView`.

**Layout (single scroll, two sections):**

```
[Sheet root]
  
  ── Section: This lot ──────────────────────
  KickerLabel("Lot margin override")
  Text("{N}% of comp")           ← live preview, updates with slider/snaps
  LazyVGrid snap buttons (70–100%)
  Slider (0.70–1.00, step 0.01)
  PrimaryGoldButton("Save lot margin")   ← calls onSelectLotMargin + dismiss
  
  ── Section: Store defaults ────────────────
  KickerLabel("Margin ladder")
  Text("Changes apply to all future auto-priced lots.")   ← scope note
  [Tier rows — same as MarginLadderView.laddersSection]
    • "If comp ≥ $X" / "Pay Y%" fields per tier
    • minus.circle remove button
    • Add tier row at bottom
  [Error label if save fails]
  PrimaryGoldButton("Save ladder", isEnabled: hasChanges)
  Button("Reset to defaults")    ← plain, muted
```

**State:** `LotMarginSheet` owns the `@State var tiers: [Row]` and `@State var storeId: UUID?` that `MarginLadderView` currently owns, loaded via the same `loadFromStore()` pattern. `storeId` is seeded from the `storeId` init parameter (avoids the userId→Store fetch when caller already knows the storeId).

**Save logic:**
- "Save lot margin" → `onSelectLotMargin(pct)` + `dismiss()`
- "Save ladder" → `StoreSettingsRepository(context:kicker:currentStoreId:).updateMarginLadder(...)` + update `initialTiers`, no dismiss (allows further edits)

**`MarginPickerSheet` is unchanged** — it remains in the codebase as-is (still reachable from any future surface that only needs the override picker).

---

### 2. `LotDetailView` changes (`Features/Lots/LotDetailView.swift`)

**a) Thread navigation path**

Add `@Binding var path: [LotsRoute]` to the initializer. Update `LotsListView.routeDestination(.lot(lotId))` to pass `$path`.

**b) Use `LotMarginSheet`**

In the `.sheet(isPresented: $showingMarginSheet)` modifier, replace `MarginPickerSheet(...)` with `LotMarginSheet(currentPct:storeId:onSelectLotMargin:)`.

**c) Rename + auto-navigate**

In `actionBar`, `.priced` case:
- Change button title `"Send to offer"` → `"Create Offer"`.
- After `offerRepository().sendToOffer(lot)` succeeds, append `LotsRoute.offerReview(lot.id)` to `path`.

**d) Style "Resume offer"**

In `actionBar`, `.presented` / `.accepted` case, replace the plain `NavigationLink("Resume offer", ...)` with a `SecondaryButton` that wraps a `NavigationLink(value: LotsRoute.offerReview(lot.id))`. Styled as `.standard` role.

---

### 3. `OfferReviewView` changes (`Features/Offers/OfferReviewView.swift`)

**a) Bounce Back auto-dismiss**

In `actionStack`, after `offerRepository().bounceBack(lot)` succeeds, call `dismiss()`. This returns the operator to `LotDetailView` where the lot is now in `.priced` state and "Create Offer" is the visible action.

**b) Button hierarchy**

Replace the current `HStack` of plain "Bounce back" / "Decline" buttons with a vertical `VStack` using `SecondaryButton`:
- "Bounce back" → `SecondaryButton(title:, role: .standard)`
- "Decline" → `SecondaryButton(title:, role: .destructive)`

Both full-width, stacked below `PrimaryGoldButton("Mark paid")`.

---

### 4. `SecondaryButtonStyle` + `SecondaryButton` (new file: `Core/DesignSystem/Components/SecondaryButton.swift`)

Define a `ButtonStyle` so the appearance can be applied to both `Button` and `NavigationLink` (needed for "Resume offer"):

```swift
struct SecondaryButtonStyle: ButtonStyle {
    enum Role { case standard, destructive }
    var role: Role = .standard
}
```

Applied like:
```swift
// Plain button (Bounce back, Decline)
Button("Bounce back") { ... }
    .buttonStyle(SecondaryButtonStyle())

Button("Decline") { ... }
    .buttonStyle(SecondaryButtonStyle(role: .destructive))

// NavigationLink (Resume offer)
NavigationLink(value: LotsRoute.offerReview(lot.id)) {
    Text("Resume offer")
}
.buttonStyle(SecondaryButtonStyle())
```

Also provide a convenience `SecondaryButton` view wrapper (same pattern as `PrimaryGoldButton`) for the common `action: () -> Void` case.

**Visual spec for `SecondaryButtonStyle`:**
- Full-width, height 44pt
- Transparent background
- `RoundedRectangle(cornerRadius: Radius.l)` stroke border, lineWidth 1
  - `.standard`: `AppColor.muted` border + `AppColor.muted` label text
  - `.destructive`: `AppColor.negative` border + `AppColor.negative` label text
- `font(SlabFont.sans(size: 15, weight: .semibold))` on label
- `opacity(configuration.isPressed ? 0.6 : 1.0)` for press feedback

No shadow, no gradient — intentionally lighter than `PrimaryGoldButton`.

---

### 5. `LotsListView` changes (`Features/Lots/LotsListView.swift`)

In `routeDestination(.lot(lotId))`, pass `$path` to `LotDetailView`:
```swift
LotDetailView(lot: lot, path: $path)
```

---

## Files changed

| File | Change |
|------|--------|
| `Features/Offers/LotMarginSheet.swift` | **New** — combined lot override + ladder editor |
| `Core/DesignSystem/Components/SecondaryButton.swift` | **New** — outlined secondary button |
| `Features/Lots/LotDetailView.swift` | Add `$path` binding; use `LotMarginSheet`; rename + auto-nav; style Resume |
| `Features/Offers/OfferReviewView.swift` | Bounce Back dismiss; restyle secondary actions |
| `Features/Lots/LotsListView.swift` | Pass `$path` to `LotDetailView` |

## Out of scope

- **UX architect flow audit** — a full cross-flow UX review is a separate effort; no spec exists for it yet.
- `MarginPickerSheet` — unchanged, stays in codebase.
- Offer state machine — no changes to `OfferRepository` logic.

## Verification

1. Tap "Adjust" on a lot's margin row → sheet opens with both sections; save lot margin updates the row; save ladder persists tiers (verify in Settings → Margin ladder).
2. Tap "Create Offer" on a `.priced` lot → navigates directly to Offer review without an intermediate tap.
3. From Offer review, tap "Bounce back" → lot reverts to `.priced` AND view dismisses back to Lot detail.
4. "Resume offer", "Bounce back", "Decline" all render with visible borders and are clearly tappable.
5. "Resume offer" and "Bounce back" are visually subordinate to "Create Offer" / "Mark paid".
6. Existing UI tests (`send-to-offer`, `bounce-back`, `decline-offer`, `margin-save`, `margin-slider`) pass.
