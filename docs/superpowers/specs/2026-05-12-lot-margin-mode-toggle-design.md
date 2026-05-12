# Lot Margin Mode Toggle

**Date:** 2026-05-12  
**Status:** Approved

## Problem

`LotMarginSheet` lets operators edit the lot's fixed margin % and the store ladder, but provides no way to switch a lot's pricing mode between "fixed %" and "store ladder". The only way to revert a lot to ladder pricing is to clear `marginPctSnapshot` from outside the UI — there is no affordance for it and no `clearLotMargin` method exists.

## Intended Outcome

Operators can toggle between "Fixed %" and "Store ladder" modes directly in the `LotMarginSheet`. Switching to "Store ladder" immediately re-prices all non-overridden scans using the ladder and clears the per-lot override. Switching to "Fixed %" restores the snap-button/slider flow. The `marginRow` on `LotDetailView` continues to display "Auto (ladder)" or "X% of comp" based on the live data — no changes needed there.

---

## Changes

### 1. `OfferRepository` — new `clearLotMargin(on:)` (`Features/Offers/OfferRepository.swift`)

```swift
/// Revert a lot to ladder pricing. Sets `marginPctSnapshot = nil` and
/// re-derives buy prices for every non-overridden scan using `resolveMarginPct`,
/// which falls through to the store ladder (then store default) now that the
/// snapshot is cleared. Mirrors `setLotMargin`'s outbox + save pattern.
func clearLotMargin(on lot: Lot) throws {
    lot.marginPctSnapshot = nil
    lot.updatedAt = Date()
    enqueueLotPatch(lot)

    let lotId = lot.id
    let descriptor = FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
    let scans = try context.fetch(descriptor)
    for scan in scans where !scan.buyPriceOverridden {
        let auto = OfferPricingService.defaultBuyPrice(
            reconciledCents: scan.reconciledHeadlinePriceCents,
            marginPct: resolveMarginPct(scan: scan, lot: lot)
        )
        scan.buyPriceCents = auto
        scan.updatedAt = Date()
        enqueueScanBuyPricePatch(scan)
    }
    try recompute(lot: lot.id)
    try context.save()
    kicker.kick()
}
```

`resolveMarginPct` correctly falls through to the ladder after `marginPctSnapshot` is set to `nil` — no changes to that method needed.

---

### 2. `LotMarginSheet` — mode toggle (`Features/Offers/LotMarginSheet.swift`)

**New `MarginMode` enum (nested in `LotMarginSheet`):**

```swift
enum MarginMode { case fixed, ladder }
```

**Updated init signature:**

```swift
init(
    currentPct: Double,
    usesLadder: Bool,
    storeId: UUID,
    onSelectLotMargin: @escaping (Double) -> Void,
    onSelectLadder: @escaping () -> Void
)
```

**New state:**

```swift
@State private var mode: MarginMode
```

Initialized in `init` via `_mode = State(initialValue: usesLadder ? .ladder : .fixed)`. When `usesLadder` is true and the user switches to "Fixed %", the slider starts at `currentPct` (passed as `lot.marginPctSnapshot ?? 0.7`, so 70% when the lot has no prior override).

**Updated `lotSection` layout:**

```
KickerLabel("Lot margin override")

Picker("Margin type", selection: $mode) {
    Text("Fixed %").tag(MarginMode.fixed)
    Text("Store ladder").tag(MarginMode.ladder)
}
.pickerStyle(.segmented)
.accessibilityIdentifier("margin-mode-picker")

── if mode == .fixed ──────────────────────────────────
Text("{N}% of comp")          ← live preview
[snap buttons 70–100%]        ← accessibilityIdentifier: margin-snap-{N}
[Slider]                      ← accessibilityIdentifier: margin-slider
PrimaryGoldButton("Save lot margin")
    action: onSelectLotMargin(pct) + dismiss()
    accessibilityIdentifier: margin-save

── if mode == .ladder ─────────────────────────────────
Text("Slabs priced per the store ladder below.")
    font: SlabFont.sans(size: 13), foregroundStyle: AppColor.muted
PrimaryGoldButton("Apply ladder")
    action: onSelectLadder() + dismiss()
    accessibilityIdentifier: margin-apply-ladder
```

The store ladder section below is unchanged.

---

### 3. `LotDetailView` — updated sheet call (`Features/Lots/LotDetailView.swift`)

In the `.sheet(isPresented: $showingMarginSheet)` modifier, pass two new arguments:

```swift
.sheet(isPresented: $showingMarginSheet) {
    LotMarginSheet(
        currentPct: lot.marginPctSnapshot ?? 0.7,
        usesLadder: lot.marginPctSnapshot == nil,
        storeId: lot.storeId,
        onSelectLotMargin: { pct in
            try? offerRepository().setLotMargin(pct, on: lot)
        },
        onSelectLadder: {
            try? offerRepository().clearLotMargin(on: lot)
        }
    )
}
```

---

## Files changed

| File | Change |
|------|--------|
| `Features/Offers/OfferRepository.swift` | Add `clearLotMargin(on:)` |
| `Features/Offers/LotMarginSheet.swift` | Add `MarginMode` enum, `usesLadder`/`onSelectLadder` params, mode toggle UI |
| `Features/Lots/LotDetailView.swift` | Pass `usesLadder` and `onSelectLadder` to `LotMarginSheet` |

## Out of scope

- `marginRow` display on `LotDetailView` — already correct ("Auto (ladder)" vs "X% of comp")
- Store ladder section in `LotMarginSheet` — unchanged
- Individual slab buy-price overrides — `clearLotMargin` skips `buyPriceOverridden == true` scans, same as `setLotMargin`

## Verification

1. Open `LotMarginSheet` on a lot with a fixed margin override → segmented control starts on "Fixed %", snap buttons visible.
2. Switch to "Store ladder" → snap/slider hide, "Apply ladder" button appears.
3. Tap "Apply ladder" → sheet dismisses, `marginRow` on `LotDetailView` shows "Auto (ladder)", slab buy prices update to reflect the ladder.
4. Re-open sheet → segmented control starts on "Store ladder".
5. Open `LotMarginSheet` on a lot already using the ladder → segmented control starts on "Store ladder".
6. Switch to "Fixed %" → snap buttons and slider appear, defaulting to 70%.
7. Tap "Save lot margin" → sheet dismisses, `marginRow` shows the chosen %, slab prices re-derived.
8. Existing unit tests for `OfferRepository` pass; existing UI tests for margin flow (`lot-margin-adjust`, `margin-snap-70`, `margin-save`) pass.
