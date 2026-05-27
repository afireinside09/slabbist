# Movers row thumbnail

Date: 2026-05-26

## Problem

The Movers tab's Top Gainers / Top Losers slates (English and Japanese)
identify each card by product name only. Operators triaging a slate to
spot a mover have to read every row title; recognising a card by art
would be faster and more accurate (multiple sets reuse the same
character name; variants share the same product name with only a badge
to disambiguate).

The eBay-Listings tab on the same screen already shows a thumbnail per
product. The mover detail view already shows a hero image. The image
URL is already on the wire — `MoverDTO.imageUrl` is populated by the
`get_top_movers` and `get_set_movers` RPCs.

The gap is entirely in row presentation.

## Goal

Render a small card thumbnail in each `MoverRow` (gainers and losers
slates) so an operator can recognise a card without reading the title.

## Out of scope

- eBay listings tab — already has a thumbnail.
- Detail view — already has a hero image.
- Set rail / search suggestions / tier chips — chips and tabs are text
  by design.
- Image caching beyond what `AsyncImage` already provides — this is
  not a measured perf concern and the existing eBay row uses the same
  defaults.
- Backend / RPC changes — `image_url` is already returned.

## Design

### Where the change lives

One file: `ios/slabbist/slabbist/Features/Movers/MoversListView.swift`.

Two private structs in that file change:

1. `MoverRow` (≈line 558) — gains a `thumbnail` view, inserted into
   the row's `HStack` between the rank label and the name/set
   `VStack`.
2. `SkeletonRows` (≈line 654) — shimmer placeholder gains a
   40×56 rectangle in the same slot, so rows don't reflow when real
   data lands.

### Thumbnail spec

- Size: **40 pt wide × 56 pt tall** (matches a Pokémon card's natural
  2.5:3.5 aspect; no letterboxing).
- Corner radius: `Radius.xs` (same as eBay row thumbnail).
- Background: `AppColor.elev2` filled `RoundedRectangle`, so the slot
  is visible even when the image is loading or missing.
- Image: `AsyncImage(url:)` reading `mover.imageUrl`. `.success` →
  `image.resizable().scaledToFit()`. `.empty` / `.failure` /
  `@unknown default` → `Image(systemName: "photo")` in
  `AppColor.dim`, mirroring `EbayProductRow.thumbnail` at
  [MoversListView.swift:863-886](../../ios/slabbist/slabbist/Features/Movers/MoversListView.swift#L863-L886).
- When `mover.imageUrl` is `nil` or fails to parse as a `URL`, render
  the placeholder slot only — no `AsyncImage` wrapper.
- Accessibility: `.accessibilityHidden(true)` on the thumbnail. The
  row's existing `accessibilityLabel` already names the product, set,
  variant, price, and percentage; an image element would add only
  redundant noise for VoiceOver users.

### Row layout

The `HStack` in `MoverRow` becomes:

```
[rank "01"] [thumbnail 40×56] [name + set VStack] [Spacer] [price + pct VStack] [chevron]
```

Spacing stays `Spacing.m` between elements. Vertical alignment stays
`.center`, so the thumbnail vertically centres next to the two-line
name/set block.

Row height grows from approximately 52 pt to approximately 60 pt
(driven by the 56 pt-tall thumbnail). This is the only visible
side-effect on layout density.

### Skeleton parity

`SkeletonRows` currently shows a small rank pill, two stacked title
bars, and two stacked price bars. To prevent reflow when real rows
arrive, add a 40×56 `RoundedRectangle(cornerRadius: Radius.xs)` filled
with `AppColor.elev2` between the rank pill and the title-bars
`VStack`. The same shimmer opacity animation applies.

## Tests

`slabbistTests/Features/MoversRenderTests.swift` already exercises the
row. The change is structural enough that any snapshot-style assertion
on row dimensions or hierarchy will need to be updated. Plan:

- Run the existing test suite. If `MoversRenderTests` fails because of
  the new image element, update the affected expectations and re-run.
- Do not add speculative tests for image loading — `AsyncImage`
  itself is not under test, and the existing accessibility label is
  unchanged.

## Risk

Low. Mirrors patterns already used elsewhere in the same file. No
data-layer, RPC, or schema changes. No new dependencies. Bundle size
unchanged. The only product-visible side effect is taller rows in the
gainers / losers slates.

## Verification

- Build and run the iOS scheme in the simulator.
- Open the Movers tab.
- English tab: confirm thumbnails appear next to gainers and losers,
  loading skeleton has the same slot.
- Japanese tab: same.
- A row whose `imageUrl` is `nil` (synthetic or via a card without an
  image) shows the photo placeholder, not a broken view.
- eBay Listings tab unchanged.
- VoiceOver reads the row's existing label, not "image".
