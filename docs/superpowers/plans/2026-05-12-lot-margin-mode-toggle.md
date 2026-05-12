# Lot Margin Mode Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let operators toggle a lot between "Fixed %" and "Store ladder" pricing modes directly from `LotMarginSheet`, with immediate re-pricing on switch.

**Architecture:** New `clearLotMargin(on:)` in `OfferRepository` mirrors `setLotMargin` but sets `marginPctSnapshot = nil` and re-prices via the existing `resolveMarginPct` chain. `LotMarginSheet` gains a `MarginMode` enum, a segmented control, and an `onSelectLadder` callback. `LotDetailView` threads the new parameters through.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, xcodebuild

---

## File Map

| File | Action |
|------|--------|
| `ios/slabbist/slabbist/Features/Offers/OfferRepository.swift` | **Modify** — add `clearLotMargin(on:)` |
| `ios/slabbist/slabbist/Features/Offers/LotMarginSheet.swift` | **Modify** — add `MarginMode`, segmented control, `usesLadder`/`onSelectLadder` params |
| `ios/slabbist/slabbist/Features/Lots/LotDetailView.swift` | **Modify** — pass `usesLadder` and `onSelectLadder` to sheet |
| `ios/slabbist/slabbistTests/Features/Offers/OfferRepositoryTests.swift` | **Modify** — add two tests for `clearLotMargin` |

---

## Task 1: `clearLotMargin` in `OfferRepository`

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Offers/OfferRepository.swift`
- Modify: `ios/slabbist/slabbistTests/Features/Offers/OfferRepositoryTests.swift`

- [ ] **Step 1.1: Add failing tests**

In `OfferRepositoryTests.swift`, add these two tests after `setLotMarginPreservesOverriddenScans` (around line 80):

```swift
@Test func clearLotMarginSetsSnapshotToNil() throws {
    let (repo, _, lot, _) = makeContext()
    // makeContext sets lot.marginPctSnapshot = 0.6
    try repo.clearLotMargin(on: lot)
    #expect(lot.marginPctSnapshot == nil)
}

@Test func clearLotMarginPreservesOverriddenScans() throws {
    let (repo, _, lot, scan) = makeContext()
    scan.buyPriceCents = 999
    scan.buyPriceOverridden = true
    try repo.clearLotMargin(on: lot)
    #expect(scan.buyPriceCents == 999)
    #expect(lot.marginPctSnapshot == nil)
}
```

- [ ] **Step 1.2: Run to confirm failure**

```bash
xcodebuild test \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:slabbistTests/OfferRepositoryTests/clearLotMarginSetsSnapshotToNil \
  2>&1 | grep -E "error:|passed|failed"
```

Expected: build error — `clearLotMargin` is not defined.

- [ ] **Step 1.3: Implement `clearLotMargin`**

In `OfferRepository.swift`, add this method directly after `setLotMargin` (after line 225):

```swift
/// Revert a lot to ladder pricing. Sets `marginPctSnapshot = nil` and
/// re-derives buy prices for every non-overridden scan using
/// `resolveMarginPct`, which now falls through to the store ladder
/// (then `store.defaultMarginPct`) since the snapshot is cleared.
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

- [ ] **Step 1.4: Run tests**

```bash
xcodebuild test \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:slabbistTests/OfferRepositoryTests \
  2>&1 | grep -E "passed|failed|error:"
```

Expected: all `OfferRepositoryTests` pass, including both new tests.

- [ ] **Step 1.5: Commit**

```bash
git add \
  ios/slabbist/slabbist/Features/Offers/OfferRepository.swift \
  ios/slabbist/slabbistTests/Features/Offers/OfferRepositoryTests.swift
git commit -m "feat(ios): OfferRepository.clearLotMargin — revert lot to ladder pricing"
```

---

## Task 2: Mode toggle in `LotMarginSheet`

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Offers/LotMarginSheet.swift`

- [ ] **Step 2.1: Add `MarginMode` enum, new stored properties, and update `init`**

In `LotMarginSheet.swift`, make the following changes:

**a) Add the `MarginMode` enum** inside the struct, just before `var body: some View` (after the `private static let snaps` line):

```swift
enum MarginMode { case fixed, ladder }
```

**b) Add `onSelectLadder` stored property** after `let onSelectLotMargin`:

```swift
let onSelectLadder: () -> Void
```

**c) Add `@State private var mode: MarginMode`** after `@State private var ladderError: String?`:

```swift
@State private var mode: MarginMode
```

**d) Replace the entire `init`** (currently lines 26–31) with:

```swift
init(
    currentPct: Double,
    usesLadder: Bool,
    storeId: UUID,
    onSelectLotMargin: @escaping (Double) -> Void,
    onSelectLadder: @escaping () -> Void
) {
    self.currentPct = currentPct
    self.storeId = storeId
    self.onSelectLotMargin = onSelectLotMargin
    self.onSelectLadder = onSelectLadder
    _pct = State(initialValue: currentPct)
    _mode = State(initialValue: usesLadder ? .ladder : .fixed)
}
```

- [ ] **Step 2.2: Replace `lotSection`**

Find `private var lotSection: some View` (currently around line 50) and replace the entire computed property with:

```swift
private var lotSection: some View {
    VStack(alignment: .leading, spacing: Spacing.l) {
        KickerLabel("Lot margin override")
        Picker("Margin type", selection: $mode) {
            Text("Fixed %").tag(MarginMode.fixed)
            Text("Store ladder").tag(MarginMode.ladder)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("margin-mode-picker")
        if mode == .fixed {
            Text("\(Int((pct * 100).rounded()))% of comp").slabTitle()
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 56), spacing: Spacing.s)],
                alignment: .leading,
                spacing: Spacing.s
            ) {
                ForEach(Self.snaps, id: \.self) { snap in
                    Button("\(Int(snap * 100))%") { pct = snap }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.s)
                        .background(snap == pct ? AppColor.gold.opacity(0.2) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColor.gold, lineWidth: snap == pct ? 1.5 : 0.5)
                        )
                        .accessibilityIdentifier("margin-snap-\(Int(snap * 100))")
                }
            }
            Slider(value: $pct, in: 0.70...1.00, step: 0.01)
                .accessibilityIdentifier("margin-slider")
            PrimaryGoldButton(title: "Save lot margin") {
                onSelectLotMargin(pct)
                dismiss()
            }
            .accessibilityIdentifier("margin-save")
        } else {
            Text("Slabs priced per the store ladder below.")
                .font(SlabFont.sans(size: 13))
                .foregroundStyle(AppColor.muted)
            PrimaryGoldButton(title: "Apply ladder") {
                onSelectLadder()
                dismiss()
            }
            .accessibilityIdentifier("margin-apply-ladder")
        }
    }
}
```

- [ ] **Step 2.3: Build to confirm no errors**

```bash
xcodebuild build \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`

- [ ] **Step 2.4: Commit**

```bash
git add ios/slabbist/slabbist/Features/Offers/LotMarginSheet.swift
git commit -m "feat(ios): LotMarginSheet mode toggle — Fixed % vs Store ladder"
```

---

## Task 3: Wire `LotDetailView`

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Lots/LotDetailView.swift`

- [ ] **Step 3.1: Update the sheet call**

In `LotDetailView.swift`, find the `.sheet(isPresented: $showingMarginSheet)` modifier (around line 77). It currently reads:

```swift
.sheet(isPresented: $showingMarginSheet) {
    LotMarginSheet(
        currentPct: lot.marginPctSnapshot ?? 0.7,
        storeId: lot.storeId,
        onSelectLotMargin: { pct in
            try? offerRepository().setLotMargin(pct, on: lot)
        }
    )
}
```

Replace it with:

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

- [ ] **Step 3.2: Build to confirm no errors**

```bash
xcodebuild build \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`

- [ ] **Step 3.3: Run full unit test suite**

```bash
xcodebuild test \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:slabbistTests \
  2>&1 | grep -E "passed|failed|error:" | grep -v "^Test case.*passed"
```

Expected: no new failures (pre-existing snapshot/outbox failures are unrelated to this change).

- [ ] **Step 3.4: Commit**

```bash
git add ios/slabbist/slabbist/Features/Lots/LotDetailView.swift
git commit -m "feat(ios): wire LotDetailView to LotMarginSheet mode toggle"
```

---

## Verification Checklist

1. Open `LotMarginSheet` on a lot with a fixed margin → segmented control shows "Fixed %" selected, snap buttons and slider visible.
2. Switch to "Store ladder" → snap/slider disappear, "Slabs priced per the store ladder below." note appears, "Apply ladder" button visible.
3. Tap "Apply ladder" → sheet dismisses, `marginRow` on `LotDetailView` shows "Auto (ladder)", slab buy prices update.
4. Re-open sheet → segmented control starts on "Store ladder".
5. Open `LotMarginSheet` on a lot already in ladder mode → segmented control starts on "Store ladder".
6. Switch to "Fixed %" → snap buttons/slider appear, defaulting to 70%.
7. Tap "Save lot margin" at 80% → sheet dismisses, `marginRow` shows "80% of comp", slab prices re-derived.
8. `OfferRepositoryTests` — all pass including `clearLotMarginSetsSnapshotToNil` and `clearLotMarginPreservesOverriddenScans`.
9. Existing `OfferPricingFlowUITests` (margin flow: `lot-margin-adjust`, `margin-snap-70`, `margin-save`) — still pass.
