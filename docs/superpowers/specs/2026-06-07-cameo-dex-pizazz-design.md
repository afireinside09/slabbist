# Cameo Dex: first-tap pizazz + row artwork

**Date:** 2026-06-07
**Surface:** iOS — hidden "Pokemon Cameos" page (the Psyduck easter egg)
**Status:** Approved design

## Problem

The Pokemon Cameos page is reached by tapping the peeking Psyduck. Two gaps:

1. The first tap is anticlimactic — it presents `CameoSecretView` via a plain
   `fullScreenCover` with no celebration for discovering a hidden screen.
2. The subject list (`CameoSubjectRow`) is text-only (name, `No. {ndex}`/region,
   card count, chevron). A flat list of Pokémon names reads as lame.

## Goals

- First-ever Psyduck tap plays a celebratory shimmer transition into the dex.
- Subsequent taps open the dex directly (no celebration).
- Each Pokémon row shows official artwork; trainers get a sensible fallback.

## Non-goals

- No schema, scraper, repository, or Edge Function changes. `ndex` already
  ships in `CameoSubjectDTO`.
- No new image cache layer — use native `AsyncImage`, matching the app's
  existing pattern (`CameoSubjectDetailView`, `CameoCardDetailView`).
- No change to navigation, search, or the detail screens.

## Design

### 1. First-tap shimmer transition

**New component — `Features/Cameo/CameoDiscoveryShimmer.swift`**

A self-contained, full-screen overlay that plays once:

- Dark scrim fades in.
- A diagonal gold gradient band sweeps across the screen.
- A scatter of gold sparkle particles bloom and fade. Particle positions are
  derived from their index (no reliance on `Math.random`/`Date.now` in a way
  that would make behavior untestable; randomness, if used, is purely cosmetic).
- A success haptic fires on start (`UINotificationFeedbackGenerator`).
- Calls `onComplete` after ~0.9s.
- Respects `accessibilityReduceMotion`: skips the sweep/particles but still
  fires the haptic and `onComplete`, so the feature can never get stuck.

Interface: `CameoDiscoveryShimmer(onComplete: () -> Void)`.

**Wiring — `Features/Shell/RootTabView.swift`**

- Add `@AppStorage("cameoDexDiscovered") private var cameoDexDiscovered = false`
  and `@State private var playCameoDiscovery = false`.
- Psyduck tap closure: capture `playCameoDiscovery = !cameoDexDiscovered`, set
  `cameoDexDiscovered = true`, then `showCameoDex = true`.
- The existing single `.fullScreenCover(isPresented: $showCameoDex)` passes
  `playDiscovery: playCameoDiscovery` into `CameoSecretView`.

**Shimmer placement — inside the cover, not on the root.** `CameoSecretView`
takes `var playDiscovery: Bool = false` and, on first appear, shows
`CameoDiscoveryShimmer` as an `.overlay` (with `.transition(.opacity)`). The
shimmer's `onComplete` removes the overlay inside `withAnimation(.easeOut)`, so
the gold wash fades to reveal the dex *beneath it* — a true dissolve into the
dex. This is simpler than a second overlay/presentation path on `RootTabView`
and avoids the cover's slide-up briefly showing the prior screen.

Result: first discovery = haptic + gold wash → dex. Every tap after = straight
to the dex.

### 2. Row artwork

**New helper — `Features/Cameo/CameoArtwork.swift`**

```swift
func cameoArtworkURL(ndex: Int?) -> URL?
```

Returns the PokeAPI official-artwork URL for a given national dex number:

```
https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/{ndex}.png
```

Returns `nil` when `ndex` is `nil`. Kept out of `CameoSubjectDTO` so the Core
data layer stays free of presentation concerns.

**`CameoSubjectRow` — leading thumbnail (~44×44)**

- Pokémon (has `ndex`): `AsyncImage` of `cameoArtworkURL(ndex:)`, `scaledToFit`
  in a 44×44 frame.
- Trainers / missing `ndex`: fallback — an SF Symbol (`person.fill`, gold/dim
  tint) in a rounded square.
- Placeholder (load + failure): rounded square matching the app's existing
  placeholder styling (`Radius`, `AppColor`), consistent with
  `CameoSubjectDetailView`'s `thumbnailPlaceholder`.
- The existing name/subtitle/count/chevron layout is unchanged — it is simply
  inset after the thumbnail.

## Testing

- **Unit test** `cameoArtworkURL(ndex:)`:
  - a known dex number (e.g. `25`) → the exact expected URL.
  - `nil` → `nil`.
  This encodes intent: the row must build the correct artwork source from the
  dex number it already has, and must degrade to a fallback for trainers.
- Shimmer/animation is logic-light and not unit-tested; `reduceMotion` path is
  verified to still call `onComplete`.

## Conventions

- SwiftUI work follows `swiftui-expert-skill` rules.
- Colors/spacing/radii via existing `AppColor` / `Spacing` / `Radius` tokens
  (`.impeccable.md` design system).
