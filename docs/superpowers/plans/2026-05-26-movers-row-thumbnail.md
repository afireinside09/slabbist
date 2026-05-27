# Movers Row Thumbnail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 40×56 portrait card thumbnail to each `MoverRow` in the
Top Gainers and Top Losers slates of the Movers tab so operators can
recognise a card by art, not just product name.

**Architecture:** Pure SwiftUI presentation change in one file. Add an
`AsyncImage`-backed `thumbnail` view to `MoverRow`, slot it between
the rank label and the name/set `VStack`, and add a matching 40×56
placeholder to `SkeletonRows` so the loading state doesn't reflow when
real data lands. Mirrors the existing `EbayProductRow.thumbnail`
pattern from the same file. `MoverDTO.imageUrl` is already populated
by `get_top_movers` and `get_set_movers`, so no data-layer work.

**Tech Stack:** SwiftUI, AsyncImage. iOS 26.4 target. Xcode 16,
`xcodebuild` for headless builds + tests.

**Spec:** `docs/superpowers/specs/2026-05-26-movers-row-thumbnail-design.md`

---

## File map

- Modify: `ios/slabbist/slabbist/Features/Movers/MoversListView.swift`
  - `MoverRow` (≈line 558) — add thumbnail view, insert into row HStack.
  - `SkeletonRows` (≈line 654) — add matching 40×56 placeholder rect.
- No other files change. `MoverDTO.imageUrl` is already wired.
- No new tests required. Existing `MoversRenderTests.moversListViewRenders`
  is a hosting-controller smoke test and will continue to pass; existing
  DTO decode tests already cover `image_url` in fixtures.

---

## Task 1: Add the thumbnail to `MoverRow`

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Movers/MoversListView.swift:558-630`

This task adds the visible card image inside the row. The implementation
mirrors `EbayProductRow.thumbnail` from the same file (≈line 863), but
sized 40×56 (portrait card aspect) instead of 56×56 (square).

- [ ] **Step 1: Add a `thumbnail` computed view to `MoverRow`**

Insert this view inside `private struct MoverRow` in
`ios/slabbist/slabbist/Features/Movers/MoversListView.swift`, just
after the `accessibilityLabel` computed property and before the
closing brace of the struct (around line 629).

```swift
    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(AppColor.elev2)
            if let urlString = mover.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .empty, .failure:
                        Image(systemName: "photo")
                            .font(SlabFont.sans(size: 14))
                            .foregroundStyle(AppColor.dim)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "photo")
                    .font(SlabFont.sans(size: 14))
                    .foregroundStyle(AppColor.dim)
            }
        }
        .frame(width: 40, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        .accessibilityHidden(true)
    }
```

Why these choices:
- `40×56` matches a Pokémon card's natural 2.5:3.5 ratio — no
  letterboxing.
- `AppColor.elev2` backdrop keeps the slot visible during load and on
  failure, consistent with `EbayProductRow.thumbnail`.
- The `photo` SF symbol is the same fallback used by `EbayProductRow`
  and `MoverDetailView.imagePlaceholder`.
- `accessibilityHidden(true)` because `MoverRow` already combines
  children into a single accessibility element with a complete label
  (`accessibilityLabel` at line 624) — adding the image as a separate
  VO element only adds noise.

- [ ] **Step 2: Insert the thumbnail into the row's HStack**

In the same struct, find the `body` HStack (starts at line 566) and
insert `thumbnail` as the second element — between the rank `Text`
and the name/set `VStack`.

Change this:

```swift
            HStack(alignment: .center, spacing: Spacing.m) {
                Text(String(format: "%02d", rank))
                    .font(SlabFont.mono(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.dim)
                    .frame(width: 22, alignment: .leading)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
```

To this:

```swift
            HStack(alignment: .center, spacing: Spacing.m) {
                Text(String(format: "%02d", rank))
                    .font(SlabFont.mono(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.dim)
                    .frame(width: 22, alignment: .leading)

                thumbnail

                VStack(alignment: .leading, spacing: Spacing.xxs) {
```

Spacing stays `Spacing.m`; `alignment: .center` keeps the thumbnail
vertically centred next to the two-line name/set block.

- [ ] **Step 3: Verify the file still compiles**

Run from the repo root:

```bash
xcodebuild -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | tail -30
```

Expected: build succeeds. Look for `** BUILD SUCCEEDED **` in the
output tail. If you see errors, they should reference the change you
made; fix and rebuild.

- [ ] **Step 4: Commit**

```bash
git add ios/slabbist/slabbist/Features/Movers/MoversListView.swift
git commit -m "feat(movers): show card thumbnail in MoverRow

Adds a 40x56 portrait thumbnail to each row in the Top Gainers /
Top Losers slates. MoverDTO.imageUrl is already on the wire; this
is a pure presentation change mirroring EbayProductRow.thumbnail."
```

---

## Task 2: Match the skeleton to the new row shape

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Movers/MoversListView.swift:654-702`

Without this, the loading shimmer leaves a 40-pt-wide horizontal gap
where the thumbnail will land, and rows visibly reflow when data
arrives. We add a matching placeholder rect.

- [ ] **Step 1: Insert a thumbnail placeholder into `SkeletonRows`**

Inside `private struct SkeletonRows`, find the `HStack` inside the
`ForEach` (starts at line 665). Insert a 40×56 rectangle between the
rank rectangle (width 22, height 10) and the title-bars `VStack`.

Change this:

```swift
                HStack(spacing: Spacing.m) {
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(AppColor.elev2)
                        .frame(width: 22, height: 10)

                    VStack(alignment: .leading, spacing: 6) {
```

To this:

```swift
                HStack(spacing: Spacing.m) {
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(AppColor.elev2)
                        .frame(width: 22, height: 10)

                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(AppColor.elev2)
                        .frame(width: 40, height: 56)

                    VStack(alignment: .leading, spacing: 6) {
```

The same shimmer opacity animation (the row's `.opacity(shimmer ? 0.55 : 1.0)`
modifier at line 693) already applies to the whole `HStack`, so the
placeholder shimmers in sync with the rest of the row.

- [ ] **Step 2: Verify the file still compiles**

```bash
xcodebuild -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/Movers/MoversListView.swift
git commit -m "feat(movers): match SkeletonRows to new MoverRow layout

Adds a 40x56 placeholder rect so the loading shimmer has the same
shape as the loaded row — no reflow when data arrives."
```

---

## Task 3: Run existing tests

**Files:** none modified.

The render test (`MoversRenderTests.moversListViewRenders`) just
hosts the view and checks it lays out. Adding a thumbnail shouldn't
break it, but we run the suite to confirm.

- [ ] **Step 1: Run the Movers test suite**

```bash
xcodebuild -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test \
  -only-testing:slabbistTests/MoversRenderTests 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **` and all four tests in the suite
(`priceFormat`, `percentFormat`, `moversListViewRenders`,
`moverDTODecodesNumbers`, `moverDTODecodesNumericStrings`) pass.

If anything fails, the failure should be self-explanatory. The render
test is the only one with any chance of regressing — fix any layout
issue exposed by it.

- [ ] **Step 2: Run the broader Movers tests as a sanity check**

```bash
xcodebuild -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test \
  -only-testing:slabbistTests/MoversViewModelTests \
  -only-testing:slabbistTests/MoverDetailViewModelTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`. These don't touch the row at all,
so this is purely a regression sanity check — they should pass
unchanged.

---

## Task 4: Manual UI verification

**Files:** none modified.

A render smoke test doesn't catch layout problems. The user explicitly
wants to see the cards, so verify in the simulator.

- [ ] **Step 1: Build and run the app in the iOS Simulator**

Open the project in Xcode (`open ios/slabbist/slabbist.xcodeproj`)
and run on an iPhone 16 Pro simulator with `Cmd+R`, or via CLI:

```bash
xcodebuild -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | tail -5
# Then launch from Xcode for interactive testing.
```

- [ ] **Step 2: Walk the verification checklist**

In the running app, exercise these paths:

1. Open the Movers tab.
2. **English tab** (the default): scroll the Top Gainers and Top
   Losers slates. Confirm each row shows a 40×56 card thumbnail to
   the right of the rank number. Cards should be the right shape
   (portrait, no obvious letterboxing).
3. **Loading state**: pull-to-refresh. While the new fetch is in
   flight, the skeleton rows should show a 40×56 grey rect in the
   thumbnail slot — same width as the loaded row, so no visible
   reflow when data arrives.
4. **Japanese tab**: tap to switch. Same checks as English.
5. **Missing image**: if you can find a row whose `imageUrl` is
   nil or returns 404, it should show the `photo` SF Symbol on an
   `AppColor.elev2` background — not a broken view or empty box.
6. **eBay Listings tab**: unchanged. The existing 56×56 thumbnail
   on `EbayProductRow` should still render the way it did before.
7. **Detail view**: tap a row. The detail view's hero image should
   still render — we didn't touch it.
8. **VoiceOver**: turn on VO and swipe through a few rows. Each row
   should announce its existing combined label
   ("Rank 01. Charizard ex, Holo, Scarlet & Violet - 151. $1,240.50.
   +12.4%."). The thumbnail itself should not announce ("image",
   "photo") because we set `accessibilityHidden(true)`.

- [ ] **Step 3: Report results**

If everything passes, you're done. If you find an issue, fix it,
re-run the relevant verification, then return to the report step.

Do **not** mark this task complete on a build-only basis — the spec's
`## Verification` section is explicit that a working simulator run is
the acceptance check.

---

## Done criteria

- [ ] `xcodebuild ... build` succeeds.
- [ ] `xcodebuild ... test -only-testing:slabbistTests/MoversRenderTests`
  passes.
- [ ] In the simulator, thumbnails render in both English and Japanese
  Movers slates (gainers + losers), skeleton matches, missing-image
  rows show a placeholder, VoiceOver does not surface the image as a
  separate element, and the eBay tab + detail view are unaffected.
- [ ] Two commits on the branch (one per task), each touching only
  `MoversListView.swift`.
