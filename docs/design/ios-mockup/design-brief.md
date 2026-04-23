# Slabbist iOS — design brief (from HTML mockup)

Distilled from `unpacked/*.jsx`. Use as the authoritative reference for look-and-feel when implementing screens. When in doubt, read the JSX — precise numbers and animations live there.

## Positioning caveat — read before copying wholesale

The mockup is positioned as a **collector / portfolio** app ("Main vault", "Archivist", "Collections", "Graded submissions", hero sparkline of portfolio value, Pro subscription tier).

The product spec (`docs/superpowers/specs/2026-04-22-bulk-scan-comp-design.md`) positions Slabbist as a **hobby-store vendor / buy-side** tool — the primary workflow is *scan stack → comp → offer → transact at the counter*, and the core entity is a **`Lot`**, not a portfolio.

The **visual language** (dark + gold premium, serif hero numerals, OKLCH palette, monospace metrics) is fully reusable. The **information architecture** needs translation — e.g. "Main vault / Collection" becomes "Open lots / Recent lots"; "Portfolio value sparkline" becomes "Lot total + confidence-weighted estimate"; "Price chart with TikTok viral events" becomes "per-scan comp + 7/30/90d velocity". Don't port collector-mode IA by reflex.

When a design choice conflicts between the mockup and the spec, **the spec wins**.

## Design tokens

Source: `unpacked/94984bdf-…jsx` (`SB_TOKENS`).

### Colors

| Token | Value | Role |
|---|---|---|
| `ink` | `#08080A` | Primary background |
| `surface` | `#101013` | Screen background alt |
| `elev` | `#17171B` | Card / row container |
| `elev2` | `#1E1E23` | Nested / selected state |
| `hairline` | `rgba(255,255,255,0.08)` | Default divider / border |
| `hairlineStrong` | `rgba(255,255,255,0.14)` | Stronger divider / pressed state |
| `text` | `#F4F2ED` | Primary content |
| `muted` | `rgba(244,242,237,0.58)` | Secondary content |
| `dim` | `rgba(244,242,237,0.36)` | Kicker labels, tertiary |
| `gold` | `oklch(0.82 0.13 78)` | Accent / CTA / highlight |
| `goldDim` | `oklch(0.58 0.09 75)` | Gold gradient partner |
| `goldInk` | `oklch(0.32 0.07 72)` | Text-on-gold (rarely used; usually `ink`) |
| `pos` | `oklch(0.78 0.14 155)` | Positive change / live status |
| `neg` | `oklch(0.68 0.18 25)` | Negative change / error |

**OKLCH → SwiftUI.** SwiftUI has no OKLCH literal, but OKLCH→P3 conversion is straightforward. For `oklch(L C H)`:

- Convert via the standard OKLCH→Oklab→linear sRGB→sRGB pipeline (code snippets widely available).
- Target `Color(.displayP3, red:, green:, blue:)` — most of these saturated values clip in sRGB.
- Approx hex equivalents for quick bootstrap (verify against the browser mockup):
  - `gold` ≈ `#E2B765` / P3 displayP3 ≈ `(0.886, 0.718, 0.396)`
  - `goldDim` ≈ `#A47E3D`
  - `pos` ≈ `#76D49D`
  - `neg` ≈ `#E0795B`

Add a `Color+OKLCH.swift` helper once there are ≥2 OKLCH-derived colors in the system rather than hard-coding hex.

### Typography

| Family | Mockup string | Proposed iOS stack |
|---|---|---|
| Serif (hero numerals, titles) | `"Instrument Serif", "Canela", Georgia, serif` | **Instrument Serif** (Google Fonts, OFL) bundled as a custom font — *or* `.serif` design w/ `New York` if we skip custom fonts for MVP. |
| Sans (body, buttons) | `"Inter Tight", "Inter", -apple-system, system-ui, sans-serif` | **Inter Tight** bundled — *or* fall back to SF Pro via `.rounded` (looser match). |
| Mono (prices, stats, chips) | `"JetBrains Mono", "SF Mono", ui-monospace, monospace` | `.monospaced` modifier on SF — perfectly adequate. Skip JetBrains Mono. |

**Recommendation:** bundle **Instrument Serif** as a single custom font (it carries 80% of the premium feel — the giant `$68` hero numerals). Use system SF for sans (`Inter Tight` and SF are visually close) and `.monospaced` for mono. Revisit Inter Tight only if the sans feels visibly off.

### Type scale (from mockup)

| Use | Size / weight | Notes |
|---|---|---|
| Hero value | **68pt serif, weight 400, letter-spacing -2** | `$` at 36pt, opacity 0.5 |
| Screen title | **36pt serif, weight 400, letter-spacing -1** | e.g. "Collection", "Search" |
| Card detail title | **40pt serif, weight 400, letter-spacing -1** | |
| Price chart hero | **54pt serif, weight 400, letter-spacing -1.5** | |
| Body emphasis | 15pt sans, weight 600, letter-spacing -0.2 | |
| Body / row title | **14pt sans, weight 500, letter-spacing -0.15** | standard row text |
| Metric (price/count) | **14pt mono, weight 500** | always mono |
| Kicker label | **11pt sans, weight 500, letter-spacing 2.0–2.4, UPPERCASE**, color = `dim` | *Everywhere*: precedes every section. |
| Detail value | 13pt mono | settings rows right-edge text |
| Micro label | 10pt sans, letter-spacing 1.4–1.6 uppercase | stat-card sublabels |

### Spacing & radii

Observed values (px ≈ pt on iOS):

- Horizontal screen padding: **24**
- Row/card padding: **14–16** horizontal, **12–14** vertical
- Card corner: **18** (container), **14** (large CTA), **10–12** (medium), **6–8** (tile) — there is no single radius, but there's a rhythm: inner elements are always smaller-radius than their containers
- Button pill: **20–22** radius (full-height)
- Gap between sibling rows / cards: **12–14**
- Kicker label bottom margin: **10–14**
- Between-section spacing: **24–28**

Proposed tokens (replace `Core/DesignSystem/Tokens.swift`):

```swift
enum Spacing { static let xxs: CGFloat = 2; xs = 4; s = 8; m = 12; md = 14; l = 16; xl = 20; xxl = 24; xxxl = 32 }
enum Radius  { static let xs: CGFloat = 6; s = 10; m = 14; l = 18; xl = 22 }
```

(Sketchy names; refine when implementing.)

## Component archetypes

All observed in `unpacked/*.jsx`. Each should eventually live in `Core/DesignSystem/Components/`.

### Status bar (`SBStatusBar`)
Custom 9:41 + signal + battery. **Don't build** — iOS supplies this. Ignore the mockup version.

### Kicker label
`Text("RECENT COMPS").font(.system(size: 11, weight: .medium)).tracking(2.0).textCase(.uppercase).foregroundStyle(.secondary)` — used before every section and every paired value block.

### Hero value block
Huge serif numeral, small `$` inset, optional trailing decimal at reduced opacity. Pattern:
```
$ 4,120 .00
⬆ +2.8%  Today
```
Paired with a live-dot + "LIVE" badge on "market value" variant.

### Stat divider strip
Horizontal row of 3 values divided by 1pt hairlines; used in Collection header and BatchResult total block. Each cell: mono numeral + tiny uppercase kicker.

### Card row (elev container, hairline dividers)
`SlabRow`: thumbnail + title + sub (mono, e.g. `#072/110 · PSA 10`) + right-edge mono price + mono % change (green/red). Last-item suppresses divider.

### Rounded-card grid container
`elev` background, `hairline` border, radius 18, children separated by inner hairlines — never individual card shadows. All list sections use this.

### Pill toggle
Horizontal pill with inset selected pill. Two variants:
- **AR / Batch mode toggle** (camera screen) — selected pill is `gold` with `ink` text.
- **Grid / List view toggle** — selected pill is `elev2` with `text` foreground.

### Chip row (horizontal scrolling sort chips)
Selected: `text` background + `ink` foreground + `text` border. Unselected: `elev` bg, `muted` text, `hairline` border.

### Primary CTA (gold gradient pill)
`linear-gradient(135deg, gold, oklch(0.72 0.13 60))`, `ink` text, inset dark icon tile on the left, chevron on right, `box-shadow: 0 14px 36px gold22`. Used for "Scan cards" and onboarding continue.

### Secondary CTA / icon button
40×40 circle, `elev` background, `hairline` border, `text` icon. Used for close/back/bell/filter everywhere.

### Camera viewfinder (scan screen)
- Radial-gradient "table" background (dark with warm wood tint at the bottom).
- SVG noise/grain overlay at 6% opacity.
- Four corner brackets in gold, 3pt stroke.
- A 2pt horizontal scan line animating top↔bottom with gold glow.
- Top bar floats: close-button | center-pill (AR/Batch) | flash-button. All with `backdrop-filter: blur(20px)` and translucent black fills.
- Bottom sheet: translucent black → clear gradient, tally card (elev, hairline, radius 22), shutter row (gallery thumb | big 76pt shutter | flip camera).

The shutter is the most distinctive element — **big hollow gold ring**, inner radial gradient disc with an inset shadow. When a capture fires, it pulses (0.4s) and the scan line flashes white.

### Price chart
- SVG path + gradient fill (gold→transparent).
- Dotted 2-4 horizontal grid lines at rgba(255,255,255,0.04).
- Annotated "events" as gold-ringed circles with vertical dotted tail to the baseline. Letter code (A, B, C) in a small monospace tile.
- Crosshair on hover (position-driven). Range selector below: 1W / 1M / 3M / 6M / 1Y / ALL pill bar.

### AR price pin
Floating above a detected card: translucent black (`rgba(10,10,12,0.82)`), blur 20, gold border at 40% alpha, small gold dot glow on the left, mono price + small-caps grade & confidence below. Triangular tail at the bottom-left. Gentle bob animation (`sbPinBob`, 2.5s alternate).

### Ambient gold blobs
Radial-gradient circles at 14–18% opacity with 30–50pt blur, placed off-screen at corners of hero screens (Onboarding, Card Detail, Batch Result). Adds a subtle gold glow without a flat accent.

### Foil card art (`SBCardArt`)
The mockup's placeholder art is an elaborate pseudo-card (hue-driven OKLCH layers, foil sheen, inner frame, art window with silhouette, title bar, bottom text block). **Don't replicate this for real slabs.** For actual captured photos, use a simple rounded rectangle image view with a 1px hairline stroke and a drop shadow — the foil treatment is only relevant if we ever show placeholder art in empty states.

## Screen patterns

| Mockup screen | Maps to (per spec) | Notes |
|---|---|---|
| `SBOnboarding` | First-launch onboarding (not in spec — punt) | 3-page black+gold, floating card stack, kicker + serif headline + CTA pill. Build last; post-MVP. |
| `SBHome` (portfolio hero + scan CTA + top movers + activity) | **`LotsListView`** (home tab) | Translate: "Portfolio value" → "Open-lots total"; "Top movers 24h" → "Open lots"; "Recent activity" → "Recent lots". The **gold scan CTA** pattern maps directly to "New bulk scan". |
| `SBCollection` (grid/list toggle + sort chips) | Future — `AllCardsView` or archived-lots browser | Defer until sub-project 8 (analytics/inventory). The list variant's row pattern *is* usable for `LotReviewView`. |
| `SBSearch` (trending / recent / browse-by-set) | Future — card search | Defer. |
| `SBScan` (AR overlay + batch) | **`BulkScanView`** | The **batch mode** (bottom "tally card" + growing row of thumbnails + big shutter) maps onto the bulk-scan workbench in the spec. The **AR mode** (pinned price tags on detected cards) is *aspirational* — not in spec scope; flag for a later sub-project. Keep the visual language for the batch mode; drop AR for MVP. |
| `SBCardDetail` (hero card + value block + comps + specs grid) | **`ScanDetailView`** | Direct map. "Market value LIVE" → "Blended comp + last refreshed". "Recent comps" table → last-5 sold listings from `/price-comp`. "Details" specs grid → card identity fields (grade, population, serial, etc.). |
| `SBPriceChart` (full-screen chart + range picker + key events) | Future — sparkline/chart on Scan detail | Spec only commits to sparkline micro-chart for 7/30/90d. Full chart is a nice-to-have; keep the range-picker and event-annotation patterns filed for later. |
| `SBBatchResult` (scan complete hero + card list) | **`LotReviewView`** | Very close map. "Scan complete / $Total / N cards / M gems / 98% confidence" → "Lot summary / total / scanned / comped / confidence". Close + "Save to vault" gold CTA → Close + Export CSV. |
| `SBProfile` (stats + grouped sections) | `SettingsView` / `More` tab | Direct pattern — grouped `elev` container, kicker labels per section, icon tile + title + sub + detail + chevron row. |

## Navigation

Mockup has a bottom tab bar (implied — all screens reserve `paddingBottom: 110`). The spec mandates **3 tabs**: Lots | Scan | More. Use the mockup's visual treatment (translucent `elev` + hairline, gold-tinted selected icon) but honour the spec's IA.

## Animation / motion

- `cubic-bezier(0.2, 0.9, 0.3, 1.1)` — the signature spring-ish easing used for value transitions, onboarding card stack, batch row slide-in, and batch-result list cascade. Use this via `SpringAnimation` with `response ≈ 0.35`, `dampingFraction ≈ 0.78` in SwiftUI.
- Scan line: linear 2s alternate. Simple `withAnimation(.linear(duration: 2).repeatForever())` on a `.offset`.
- Card hover/float on AR cards: 4s alternate sine. Subtle; easy to forget but adds life.
- Shutter pulse: 0.4s ease-out `scale(1 → 1.03 → 1)` on capture. Pair with `UIImpactFeedbackGenerator(style: .medium)`.
- Batch total recolors gold on capture for 0.4s.

## Concrete next-steps for implementation

1. **Tokens refresh.** Replace `Core/DesignSystem/Tokens.swift` with a dark-first palette, add `AppColor.ink/surface/elev/elev2/hairline/hairlineStrong/text/muted/dim/gold/goldDim/pos/neg`. Keep `Spacing` / `Radius` but expand to the observed scale.
2. **Typography helpers.** Add `Font+Slabbist.swift` with `.slabHero`, `.slabTitle`, `.slabKicker`, `.slabRowTitle`, `.slabMetric` view modifiers. Wire Instrument Serif as a bundled font; skip Inter Tight / JetBrains Mono for MVP.
3. **Primitives first.** Build `KickerLabel`, `SlabRowCard` (elev container with hairline dividers), `PrimaryGoldButton`, `SecondaryIconButton`, `PillToggle`, `StatStrip`. Each as a preview-rich SwiftUI view in `Core/DesignSystem/Components/`.
4. **Migrate existing screens.** Repaint `AuthView`, `LotsListView`, `NewLotSheet` with the new tokens before writing any new screens. These are small — the refactor is cheap.
5. **Design `BulkScanView`** against the mockup's `SBScan` batch mode (AR mode out of scope). The tally card + growing thumbnail row + giant shutter are the load-bearing elements.
6. **Design `ScanDetailView`** against `SBCardDetail`. The comps table + specs grid are lifted almost verbatim.
7. **Design `LotReviewView`** against `SBBatchResult`. Swap "Save to vault" for "Close lot" / "Export CSV".

Defer onboarding, Collection, Search, PriceChart — they're out of MVP scope.
