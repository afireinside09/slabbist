# iOS Design Refresh — Vendor-flavored UI/UX

**Date:** 2026-04-23
**Status:** Design approved; awaiting implementation plan
**Related:** `docs/design/ios-mockup/design-brief.md`, `docs/superpowers/specs/2026-04-22-bulk-scan-comp-design.md`

## Summary

Repaint the iOS app to match the design language of the Claude-artifact mockup (dark + OKLCH gold, Instrument Serif hero numerals, kicker labels, elev-card layout), while keeping the spec's vendor-first information architecture (Lots / scans / comps, not Main Vault / portfolio). The deliverable is a clean `xcodebuild` + interactive iOS Simulator run that demonstrates the refresh across every user-visible screen on the signed-in path.

The mockup's collector-flavored IA — Main Vault, Archivist, portfolio sparkline, Pro subscription — is intentionally dropped. Only the visual language is adopted. When mockup IA and product spec conflict, the spec wins.

## Goals

1. Every user-visible screen on the sign-in → Lots → new lot → scan → sign-out path feels like one designed system. No mixed "iOS stock" and "custom dark" surfaces.
2. The primitive set captured here (kicker label, slab card, gold CTA, secondary icon button, pill toggle, stat strip) is reusable for every screen built in later sub-projects. New screens should be 80% primitive composition, 20% screen-specific glue.
3. Existing unit tests (`CurrencyTests`, `ReachabilityTests`, `OutboxItemTests`, `BulkScanViewModelTests`, `LotsViewModelTests`, `CertOCRRecognizerTests`) continue to pass without modification, because no view-model or model logic is touched.
4. `xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 15' build` exits 0.
5. Manual simulator pass completes: sign-up → Lots tab → New bulk scan → name the lot → Start scanning → camera-denied empty state → back → Scan tab → More tab → Sign out → back to AuthView.

## Non-goals

- `ScanDetailView`, `LotReviewView`, mockup batch-mode camera UI (big gold shutter + tally card), AR overlay. These are separate sub-project work.
- Onboarding, Collection grid, Search, Price Chart — out of MVP scope per spec.
- Light-mode palette. App is force-dark.
- Custom `Inter Tight` or `JetBrains Mono`. SF Pro + `.monospaced()` are close enough.
- Animation polish beyond existing shutter-flash. No spring springs, no haptic additions.
- `Color+OKLCH.swift` math converter. First-pass hex approximations of the OKLCH tokens are acceptable; the converter is a follow-up only if the hex values read wrong in simulator.

## Decisions locked during brainstorming

1. **Scanning surface scope:** tokens-only retint on `BulkScanView`. Layout and camera-session logic untouched. Full batch-mode UI redesign is a separate future sub-project.
2. **Dark mode policy:** force dark via `.preferredColorScheme(.dark)` at the app root. No adaptive light variants.
3. **Custom font:** bundle **Instrument Serif** (OFL license) for both Regular and Italic weights. SF Pro covers sans; `.monospaced()` covers mono.
4. **App shell:** introduce a 3-tab `RootTabView` (Lots | Scan | More) in this pass. Minimal `SettingsView` with sign-out + app-version readout.

## Architecture

### Module layout

```
slabbist/
├── slabbistApp.swift                        ← RootTabView wiring
├── Core/
│   ├── DesignSystem/
│   │   ├── Tokens.swift                     ← replace placeholder
│   │   ├── Typography.swift                 ← NEW — Font + .slab* modifiers
│   │   ├── Theme.swift                      ← NEW — root background, color-scheme helpers
│   │   └── Components/                      ← NEW subdirectory
│   │       ├── KickerLabel.swift
│   │       ├── SlabCard.swift
│   │       ├── PrimaryGoldButton.swift
│   │       ├── SecondaryIconButton.swift
│   │       ├── PillToggle.swift
│   │       └── StatStrip.swift
│   └── … (unchanged: Networking, Persistence, Sync, Models, Utilities)
├── Features/
│   ├── Auth/AuthView.swift                  ← repaint
│   ├── Lots/LotsListView.swift              ← repaint
│   ├── Lots/NewLotSheet.swift               ← repaint
│   ├── Scanning/BulkScan/BulkScanView.swift ← tokens-only retint
│   ├── Scanning/BulkScan/ScanQueueView.swift← tokens retint
│   ├── Shell/RootTabView.swift              ← NEW
│   ├── Shell/ScanShortcutView.swift         ← NEW
│   └── Settings/SettingsView.swift          ← NEW
└── Resources/
    └── Fonts/
        ├── InstrumentSerif-Regular.ttf      ← NEW, OFL
        └── InstrumentSerif-Italic.ttf       ← NEW, OFL
```

Rules carried forward from existing structure: `Core/` never imports from `Features/`; feature folders don't import each other. The new `Shell/` and `Settings/` feature folders follow the same pattern.

### Dependency flow

```
slabbistApp (root) ──┬─ AuthView (signed-out)
                     └─ RootTabView (signed-in)
                        ├─ LotsListView  ── NewLotSheet ── BulkScanView
                        ├─ ScanShortcutView ─→ BulkScanView or NewLotSheet
                        └─ SettingsView

All three tab destinations import: Core/DesignSystem (Tokens, Typography, Theme, Components/*).
Only Shell imports Auth for session dependency — via SessionStore environment object (already in place).
```

## Data flow

No model, repository, or view-model changes. This is a view-layer refresh only. Tests at the view-model layer remain green without touching them.

`RootTabView` observes `SessionStore` the same way `RootView` currently does. `ScanShortcutView` uses the existing `LotsViewModel` to find the most-recent open lot (existing `listOpenLots()` method, first element). If none, it presents `NewLotSheet`; otherwise it pushes `BulkScanView`.

`SettingsView` calls `session.signOut()` — that method must exist on `SessionStore`. **Verification step in the plan:** read `SessionStore.swift` and confirm a sign-out method exists; if not, add a minimal implementation that clears the session and deletes the Supabase auth token. (Likely already present given the session bootstrap pattern, but cannot be assumed.)

## Design tokens

See `docs/design/ios-mockup/design-brief.md` §"Design tokens" for the source-of-truth mapping. Summary for implementation:

```swift
enum AppColor {
    // Surfaces
    static let ink             = Color(hex: 0x08080A)           // primary background
    static let surface         = Color(hex: 0x101013)
    static let elev            = Color(hex: 0x17171B)           // card / row
    static let elev2           = Color(hex: 0x1E1E23)           // nested / selected

    // Dividers
    static let hairline        = Color.white.opacity(0.08)
    static let hairlineStrong  = Color.white.opacity(0.14)

    // Content
    static let text            = Color(hex: 0xF4F2ED)
    static let muted           = Color(hex: 0xF4F2ED).opacity(0.58)
    static let dim             = Color(hex: 0xF4F2ED).opacity(0.36)

    // Accent (OKLCH approximations; revisit if off-feel in simulator)
    static let gold            = Color(hex: 0xE2B765)
    static let goldDim         = Color(hex: 0xA47E3D)

    // Semantic
    static let positive        = Color(hex: 0x76D49D)
    static let negative        = Color(hex: 0xE0795B)

    // Legacy aliases (remove after all call sites migrate)
    static let accent  = gold
    static let success = positive
    static let warning = gold
    static let danger  = negative
    static let surfaceAlt = elev
}

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs:  CGFloat = 4
    static let s:   CGFloat = 8
    static let m:   CGFloat = 12
    static let md:  CGFloat = 14
    static let l:   CGFloat = 16
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

enum Radius {
    static let xs: CGFloat = 6
    static let s:  CGFloat = 10
    static let m:  CGFloat = 14
    static let l:  CGFloat = 18
    static let xl: CGFloat = 22
}
```

The existing `AppColor` names (`accent`, `success`, `warning`, `danger`, `surfaceAlt`) stay as aliases through the implementation so no existing call site breaks until each is migrated. Aliases are removed at the end of the refresh in a single cleanup pass.

A `Color.init(hex: UInt32)` helper lives next to `AppColor` (or is inlined if only 10 usages). If already present in another form, reuse it.

## Typography

`Typography.swift` exposes:

```swift
enum SlabFont {
    static func serif(size: CGFloat) -> Font
    static func serifItalic(size: CGFloat) -> Font
    static func sans(size: CGFloat, weight: Font.Weight = .regular) -> Font
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font
}

extension View {
    func slabHero() -> some View    // 68pt serif, tracking ≈ -2
    func slabTitle() -> some View   // 36pt serif, tracking ≈ -1
    func slabKicker() -> some View  // 11pt sans medium, UPPERCASE, tracking 2.0, .dim
    func slabRowTitle() -> some View // 14pt sans medium, tracking -0.15
    func slabMetric() -> some View   // 14pt mono medium
}
```

Instrument Serif is registered through `Info.plist > UIAppFonts`. At `SlabbistApp.init`, a one-line OSLog warning fires if `UIFont(name: "InstrumentSerif-Regular", size: 10)` returns nil — a cheap sanity check that catches missing/misnamed font files in CI.

Fonts are downloaded from Google Fonts (OFL) and added to the Xcode target. The `.ttf` files are committed to `slabbist/Resources/Fonts/` and added to the `slabbist` target's Copy Bundle Resources phase. The plan must cover both the file placement AND the Xcode project file (`project.pbxproj`) changes needed for the build system to pick them up.

## Theme

`Theme.swift` exposes:

```swift
struct SlabbedRoot<Content: View>: View {
    // dark ink background; edge-to-edge; forces .dark color scheme
}

extension View {
    // Ambient gold radial gradient for hero screens (AuthView top-right).
    func ambientGoldBlob(placement: AmbientBlobPlacement) -> some View
}
```

`AmbientBlobPlacement` is a small enum (`.topLeading`, `.topTrailing`, `.bottomLeading`, `.bottomTrailing`). The blob is a `RadialGradient` rendered behind content with low opacity and blur — matches the mockup's ambient accents.

## Primitives

Each primitive is a SwiftUI `View` struct with a `#Preview` that renders it against `AppColor.ink` in both the compact and regular size classes where relevant.

### `KickerLabel(_ text: String)`
`Text(text.uppercased()).font(SlabFont.sans(size: 11, weight: .medium)).tracking(2.0).foregroundStyle(AppColor.dim)`. That's the whole thing.

### `SlabCard<Content: View>` with a `@ViewBuilder` content closure
Rounded rectangle (radius `.l`), fill `AppColor.elev`, 1pt stroke in `AppColor.hairline`. Content inset `Spacing.md` vertical / `Spacing.l` horizontal.

Variant: `SlabCard(sections:)` that takes `[AnyView]` and inserts hairline dividers between them (the mockup's grouped-list pattern). Both variants are the same struct, picked by which init is used.

### `PrimaryGoldButton(title:systemIcon:trailingChevron:action:)`
Height 52–68 depending on context; gradient `LinearGradient(.gold → goldDim, 135°)`. Text in `AppColor.ink`. Drop-shadow `0 14 36 gold.opacity(0.13)`. Optional left-side inset circle tile holding the icon (matches mockup's "Scan cards" CTA). Optional trailing chevron right-arrow.

### `SecondaryIconButton(systemIcon:action:)`
40×40 circle, `AppColor.elev` fill, 1pt `AppColor.hairline` stroke, `AppColor.text` icon. Used for close/back/bell/filter.

### `PillToggle<Value: Hashable>(selection:options:)`
Horizontal pill with inset selected pill. Two visual variants via enum param:
- `.accent` — selected pill is `AppColor.gold` with `.ink` foreground (camera mode toggle).
- `.neutral` — selected pill is `AppColor.elev2` with `.text` foreground (grid/list view toggle).

### `StatStrip(_ items: [StatStrip.Item])`
3-to-4 cell horizontal row. Each cell: `.slabMetric` numeral + `.slabKicker` sub-label. Dividers are 1pt vertical strokes in `AppColor.hairline`. Cells have equal width.

## App shell

### `RootTabView`

```swift
struct RootTabView: View {
    var body: some View {
        TabView {
            LotsListView()
                .tabItem { Label("Lots", systemImage: "square.stack.3d.up") }
            ScanShortcutView()
                .tabItem { Label("Scan", systemImage: "viewfinder") }
            SettingsView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(AppColor.gold)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
```

Accent tint is `AppColor.gold` so selected tab icons read warm. Dark material tab-bar background matches the mockup's bottom-of-screen translucency without needing custom drawing.

### `ScanShortcutView`

Not a view that the user spends time on — it resolves to one of two destinations:

```swift
struct ScanShortcutView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @State private var resolvedLot: Lot?
    @State private var showingNewLot = false

    var body: some View {
        // On appear: query LotsViewModel.listOpenLots().first.
        // If found → NavigationStack pushing BulkScanView(lot:).
        // If none → NewLotSheet as a sheet; on save → resolve + push.
    }
}
```

Same bootstrap pattern as `LotsListView` for getting a `LotsViewModel`. When the tab is tapped repeatedly (user taps Scan tab twice), the view re-resolves — acceptable behavior; no need for more complex state.

### `SettingsView`

Dark root. Top: `KickerLabel("MORE")` + `.slabTitle` "Settings".

One `SlabCard` with a single row: `Sign out` (left-aligned title, trailing chevron, calls `session.signOut()`).

One `SlabCard` with two read-only rows: `Version` / `Build` pulled from `Bundle.main.infoDictionary`.

No other settings. Scan quality, price alerts, collections — all deferred.

## Screen repaints

### AuthView

- `SlabbedRoot` background + `.ambientGoldBlob(.topTrailing)`.
- Header: small gold square brand tile + uppercase "SLABBIST" wordmark (mockup pattern, top-left, `padding(Spacing.xxl)`).
- Center stack, vertically ~1/3 from top:
  - `KickerLabel(viewModel.mode == .signIn ? "WELCOME BACK" : "CREATE ACCOUNT")`
  - `.slabTitle` "Slabbist" below the kicker.
  - One-sentence subtitle in `AppColor.muted`.
- `SlabCard` containing a vertical `VStack` of fields with hairline dividers between:
  - Email field — `TextField` with `.tint(AppColor.gold)`, placeholder in `.dim`, no rounded-border style.
  - Password field — `SecureField` same treatment.
  - (Signup only) Store name.
- Below the card: inline error `Text` in `AppColor.negative`, only when present.
- `PrimaryGoldButton(title: viewModel.mode == .signIn ? "Sign in" : "Create account", action: { Task { await viewModel.submit() } })`. Full-width.
- Mode toggle: plain `Button` at the bottom, `.muted` text — "Don't have an account? Create one" / "Already have an account? Sign in". Drops the segmented picker entirely.

### LotsListView

- `SlabbedRoot` background.
- Header block (outside the list):
  - `KickerLabel("CURRENT LOTS")`
  - `.slabTitle` text reads either `"\(openCount) open lots"` or `"No open lots"` (sentence form, not just a number).
  - Sub-line: `.slabMetric` showing total scans across open lots (e.g. `"47 scans · Last updated 3m ago"`). Placeholder math is acceptable — scan count exists on `Lot`, last-updated is `lot.updatedAt` max.
- `PrimaryGoldButton(title: "New bulk scan", systemIcon: "viewfinder", trailingChevron: true, action: { showingNewLot = true })`. Edge-to-edge inside `Spacing.xxl` horizontal padding.
- Two `SlabCard` grouped sections:
  - "OPEN LOTS" section header (kicker). Rows: one per open lot. Row content: `.slabRowTitle` lot name, `.slabMetric` scan count + relative last-updated.
  - "RECENT LOTS" section header. Rows: closed lots within the last 30 days. Greyed slightly with `.muted` title color.
- Empty state (no lots at all): centered `SlabCard` with kicker "NO LOTS YET" + `.slabTitle` "Start your first scan." + `PrimaryGoldButton`. Replaces the existing `Image(systemName:)` + `Text` stack.
- Toolbar `New bulk scan` `+` button is removed — the primary button on the screen body replaces it.
- `NavigationStack` + `navigationDestination(item: $selectedLot)` logic stays identical.

### NewLotSheet

- Presented as a sheet over the darkened Lots tab.
- `SlabbedRoot` background inside the sheet.
- Top bar: `SecondaryIconButton(systemIcon: "xmark", action: dismiss)` on left, no title in the bar.
- `KickerLabel("NEW LOT")` + `.slabTitle` "Start scanning" in a left-aligned block.
- `SlabCard` with a single `TextField` "Lot name" — `.tint(AppColor.gold)`, placeholder in `.dim`.
- Optional error `Text` below.
- `PrimaryGoldButton(title: "Start scanning", action: { … })` full-width at the bottom.
- Drops `Form` + `NavigationStack`-inside-sheet entirely.

### BulkScanView (tokens-only)

- Root background of the whole screen stays the camera view — camera itself is untouched.
- The bottom area below the camera:
  - Background changes from `AppColor.surface` to `AppColor.ink`.
  - `ScanQueueView` rows get repainted: each row uses `SlabCard` inner hairline divider styling (no full SlabCard per row — rows live inside one SlabCard container).
  - Existing `summaryLine` becomes `KickerLabel("\(count) SCANNED")` + `.slabMetric` on a second line (or side-by-side).
- Camera-denied empty state:
  - Dark background (`.ink`).
  - Icon + message in `.muted`.
  - `PrimaryGoldButton(title: "Open Settings", action: …)` replaces `.borderedProminent`.
- Navigation bar: `.toolbarBackground(.ultraThinMaterial, for: .navigationBar)` + `.toolbarBackground(.visible, for: .navigationBar)`. Title remains the lot name.

## Testing strategy

### Automated

- **Keep green:** all existing unit tests must continue to pass without modification:
  - `slabbistTests/Core/CurrencyTests`
  - `slabbistTests/Core/ReachabilityTests`
  - `slabbistTests/Core/OutboxItemTests`
  - `slabbistTests/Features/BulkScanViewModelTests`
  - `slabbistTests/Features/LotsViewModelTests`
  - `slabbistTests/Features/CertOCRRecognizerTests`
- **New:** `slabbistTests/Core/DesignSystem/PrimitiveSmokeTests` — one test per primitive that instantiates the view with representative props and asserts it produces a non-nil `UIHostingController.view`. No image diffing. This catches "primitive crashes at runtime" without the maintenance cost of snapshot tests.
- **Build gate:** `xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 15' build` must exit 0. Captured as a command in the final completion report.

### Manual simulator verification

Run on the iPhone 15 simulator. Steps:

1. Launch app — lands on `AuthView`.
2. Tap "Create one" mode toggle — screen flips to signup mode with store-name field.
3. Enter test credentials + store name, tap **Create account** — lands on `LotsListView` (Lots tab).
4. Observe header kicker + serif title, gold `New bulk scan` CTA, empty state `SlabCard`.
5. Tap `New bulk scan` — `NewLotSheet` presents with kicker + serif title + gold CTA.
6. Edit the auto-generated lot name, tap **Start scanning** — pushes to `BulkScanView`.
7. Simulator has no camera; the permission flow resolves to `.denied` after the prompt — observe the repainted empty state with gold `Open Settings` button.
8. Back out → `LotsListView` now shows one `SlabCard` row for the new open lot.
9. Tap **Scan** tab — `ScanShortcutView` resolves to the same lot and pushes `BulkScanView` again.
10. Back out → tap **More** tab → observe kicker + serif title + sign-out row.
11. Tap **Sign out** — returns to `AuthView`.

Any step that fails blocks completion.

## Error handling

No new error paths are introduced. Existing handlers (camera permission denied, sign-in failure, lot-creation failure) continue to surface errors through the existing `AppLog`/`errorMessage` channels; the refresh only changes how those surfaces render.

The new `PrimitiveSmokeTests` covers the "primitive crashes due to missing font" risk. The startup font-load OSLog warning covers it at runtime.

## Observability

- One-line `OSLog.warning` at app launch if Instrument Serif fails to load.
- No other new logs. Existing logs untouched.

## Rollout

Not applicable — this is a pre-release app. No feature flag, no gradual rollout.

## Risks

1. **Xcode project file (`project.pbxproj`) edits for adding font resources** are fiddly — plan must include the exact build-phase update, not just copying files. Mitigation: verify by running `xcodebuild` after the font add commit, not just trusting Xcode's file inspector.
2. **OKLCH → hex approximation drift.** The `gold` token especially might read warmer or cooler than the mockup. Mitigation: compare simulator output to the mockup's rendered gold side-by-side after first screen lands; adjust hex once if off.
3. **`session.signOut()` may not exist yet.** Mitigation: plan first step is to read `SessionStore.swift`; if the method is missing, adding it is the very first task.
4. **Force-dark conflicts with a user's system preference** — they cannot override. Accepted per Question 2 decision.

## Follow-up tasks (captured for the plan step, not this spec)

- `Color+OKLCH.swift` converter — if the hex approximations feel off in simulator.
- Bundle `Inter Tight` — if SF Pro feels visibly off against the serif.
- `BulkScanView` full redesign per mockup batch mode (separate brainstorm + plan cycle).
- `ScanDetailView` + `LotReviewView` — next sub-project-5 sprint.
- Animation polish (capture pulse, value-change spring) — low priority.

## Definition of done

- All files in the module layout exist and compile.
- All six primitives have Xcode Previews that render against `AppColor.ink`.
- `xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 15' build` exits 0.
- Every existing test passes; `PrimitiveSmokeTests` passes.
- Manual simulator verification steps 1–11 all pass.
- Legacy `AppColor` aliases (`accent`, `success`, `warning`, `danger`, `surfaceAlt`) are removed (final cleanup commit).
- No new warnings introduced (Xcode's new-in-target warning count ≤ pre-refresh baseline).
