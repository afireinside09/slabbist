# iOS Design Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repaint the iOS app to the mockup's dark+gold vendor-flavored design language — new design tokens, bundled Instrument Serif, 6 primitives, 3-tab shell, and 4 screen repaints — ending in a clean `xcodebuild` + interactive simulator run.

**Architecture:** Primitives-first. Tokens → fonts → typography helpers → 6 primitives (each with a smoke test) → session sign-out → 3 new shell screens → 4 existing screen repaints → legacy alias cleanup → verification. Existing view-models and camera pipeline are untouched.

**Tech Stack:** SwiftUI (iOS 17+), SwiftData, Supabase swift SDK, Swift Testing framework (`@Test`, `#expect`), Xcode 16 with `PBXFileSystemSynchronizedRootGroup` (files auto-pick-up), `GENERATE_INFOPLIST_FILE = YES` (Info.plist via build settings — fonts registered via `INFOPLIST_KEY_UIAppFonts`).

**Spec:** `docs/superpowers/specs/2026-04-23-ios-design-refresh.md` (commit `4e76bdc`).

**Simulator target:** `iPhone 17` (Xcode 26 ships no iPhone 15 sim — spec's "iPhone 15" example reference is stale; `iPhone 17` is what's installed).

---

## Preflight facts (established during plan authoring)

- `Color(hex:)` helper **does not exist** in the codebase — must be added.
- `SessionStore.signOut()` **does not exist** — must be added. Supabase SDK exposes `client.auth.signOut()`.
- `slabbist/` and `slabbistTests/` are both `PBXFileSystemSynchronizedRootGroup` — new `.swift` / `.ttf` files added under those paths are auto-included in their targets.
- No `Info.plist` file on disk; project uses `GENERATE_INFOPLIST_FILE = YES`. Custom fonts register via the `INFOPLIST_KEY_UIAppFonts` build setting in `project.pbxproj`.
- Baseline `xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' build` passes with pre-existing `main actor-isolated` and `nonisolated(unsafe)` warnings that are out of scope for this plan.
- All existing unit + UI tests pass on iPhone 17 baseline.

## File Structure

**Create:**
- `ios/slabbist/slabbist/Core/DesignSystem/Color+Hex.swift` — `Color.init(hex: UInt32)` helper
- `ios/slabbist/slabbist/Core/DesignSystem/Typography.swift` — `SlabFont` + `.slab*` view modifiers
- `ios/slabbist/slabbist/Core/DesignSystem/Theme.swift` — `SlabbedRoot`, `ambientGoldBlob` modifier
- `ios/slabbist/slabbist/Core/DesignSystem/Components/KickerLabel.swift`
- `ios/slabbist/slabbist/Core/DesignSystem/Components/SlabCard.swift`
- `ios/slabbist/slabbist/Core/DesignSystem/Components/PrimaryGoldButton.swift`
- `ios/slabbist/slabbist/Core/DesignSystem/Components/SecondaryIconButton.swift`
- `ios/slabbist/slabbist/Core/DesignSystem/Components/PillToggle.swift`
- `ios/slabbist/slabbist/Core/DesignSystem/Components/StatStrip.swift`
- `ios/slabbist/slabbist/Resources/Fonts/InstrumentSerif-Regular.ttf`
- `ios/slabbist/slabbist/Resources/Fonts/InstrumentSerif-Italic.ttf`
- `ios/slabbist/slabbist/Features/Shell/RootTabView.swift`
- `ios/slabbist/slabbist/Features/Shell/ScanShortcutView.swift`
- `ios/slabbist/slabbist/Features/Settings/SettingsView.swift`
- `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift`
- `ios/slabbist/slabbistTests/Features/Auth/SessionStoreSignOutTests.swift`

**Modify:**
- `ios/slabbist/slabbist/Core/DesignSystem/Tokens.swift` — full rewrite
- `ios/slabbist/slabbist/slabbistApp.swift` — `RootView` switches to `RootTabView` when signed in
- `ios/slabbist/slabbist/Features/Auth/SessionStore.swift` — add `signOut()`
- `ios/slabbist/slabbist/Features/Auth/AuthView.swift` — repaint
- `ios/slabbist/slabbist/Features/Lots/LotsListView.swift` — repaint
- `ios/slabbist/slabbist/Features/Lots/NewLotSheet.swift` — repaint
- `ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanView.swift` — tokens retint
- `ios/slabbist/slabbist/Features/Scanning/BulkScan/ScanQueueView.swift` — tokens retint
- `ios/slabbist/ios/slabbist/slabbist.xcodeproj/project.pbxproj` — add `INFOPLIST_KEY_UIAppFonts` to both build configs

---

## Task 1: Tokens rewrite + Color(hex:) helper

**Files:**
- Create: `ios/slabbist/slabbist/Core/DesignSystem/Color+Hex.swift`
- Modify: `ios/slabbist/slabbist/Core/DesignSystem/Tokens.swift`

- [ ] **Step 1: Create the Color(hex:) helper**

Write to `ios/slabbist/slabbist/Core/DesignSystem/Color+Hex.swift`:

```swift
import SwiftUI

extension Color {
    /// Build a `Color` from a 24-bit RGB hex literal (e.g. `0xE2B765`).
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8)  & 0xFF) / 255.0,
            blue:  Double( hex        & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
```

- [ ] **Step 2: Rewrite Tokens.swift**

Replace `ios/slabbist/slabbist/Core/DesignSystem/Tokens.swift` wholesale with:

```swift
import SwiftUI

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

enum AppColor {
    // Surfaces
    static let ink             = Color(hex: 0x08080A)
    static let surface         = Color(hex: 0x101013)
    static let elev            = Color(hex: 0x17171B)
    static let elev2           = Color(hex: 0x1E1E23)

    // Dividers
    static let hairline        = Color.white.opacity(0.08)
    static let hairlineStrong  = Color.white.opacity(0.14)

    // Content
    static let text            = Color(hex: 0xF4F2ED)
    static let muted           = Color(hex: 0xF4F2ED, alpha: 0.58)
    static let dim             = Color(hex: 0xF4F2ED, alpha: 0.36)

    // Accent (OKLCH approximations; revisit if off-feel)
    static let gold            = Color(hex: 0xE2B765)
    static let goldDim         = Color(hex: 0xA47E3D)

    // Semantic
    static let positive        = Color(hex: 0x76D49D)
    static let negative        = Color(hex: 0xE0795B)

    // --- Legacy aliases (removed in Task 21) ---
    static let accent     = gold
    static let success    = positive
    static let warning    = gold
    static let danger     = negative
    static let surfaceAlt = elev
}
```

- [ ] **Step 3: Verify the project still compiles**

Run:
```bash
cd /Users/dixoncider/slabbist/ios/slabbist && \
  xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0. Legacy alias references in existing code (`AppColor.accent`, `AppColor.danger`, `AppColor.surfaceAlt`, `AppColor.surface`) still resolve through the aliases.

- [ ] **Step 4: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/DesignSystem/Color+Hex.swift \
        ios/slabbist/slabbist/Core/DesignSystem/Tokens.swift
git commit -m "$(cat <<'EOF'
feat(ios): replace placeholder design tokens with dark+gold palette

Adds Color(hex:) helper, full AppColor token set matching the design
brief, expanded Spacing/Radius scales. Legacy aliases kept for the
duration of the refresh; removed in a later cleanup task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Bundle Instrument Serif TTF files

**Files:**
- Create: `ios/slabbist/slabbist/Resources/Fonts/InstrumentSerif-Regular.ttf`
- Create: `ios/slabbist/slabbist/Resources/Fonts/InstrumentSerif-Italic.ttf`

- [ ] **Step 1: Create the Resources/Fonts directory**

```bash
mkdir -p /Users/dixoncider/slabbist/ios/slabbist/slabbist/Resources/Fonts
```

- [ ] **Step 2: Download Instrument Serif TTFs from Google Fonts mirror**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist/slabbist/Resources/Fonts
curl -fSL -o InstrumentSerif-Regular.ttf \
  https://raw.githubusercontent.com/google/fonts/main/ofl/instrumentserif/InstrumentSerif-Regular.ttf
curl -fSL -o InstrumentSerif-Italic.ttf \
  https://raw.githubusercontent.com/google/fonts/main/ofl/instrumentserif/InstrumentSerif-Italic.ttf
ls -la
```

Expected: both files present, each 40–80 KB. If curl fails (rate-limit or repo path change), fall back to downloading from https://fonts.google.com/specimen/Instrument+Serif manually and placing the extracted `.ttf` files at the same paths.

- [ ] **Step 3: Sanity-check the files are valid TrueType**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist/slabbist/Resources/Fonts
file InstrumentSerif-Regular.ttf InstrumentSerif-Italic.ttf
```

Expected output contains `TrueType Font data` or `OpenType` on each line. If it instead shows HTML or text, the download failed silently — re-download.

- [ ] **Step 4: Verify Xcode synchronized-group picks up the new files**

Synchronized root groups auto-include any file under their path. No `project.pbxproj` edit is needed for the file membership; the fonts appear in the `slabbist` target's Copy Bundle Resources automatically at next build.

Run:
```bash
cd /Users/dixoncider/slabbist/ios/slabbist && \
  xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0. The `.app` bundle now contains the two `.ttf` files — we'll verify that in Task 4.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Resources/Fonts/InstrumentSerif-Regular.ttf \
        ios/slabbist/slabbist/Resources/Fonts/InstrumentSerif-Italic.ttf
git commit -m "$(cat <<'EOF'
feat(ios): bundle Instrument Serif TTFs (OFL)

Regular + Italic weights downloaded from the google/fonts mirror.
Registered as app fonts in a follow-up task via INFOPLIST_KEY_UIAppFonts.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Register fonts in INFOPLIST_KEY_UIAppFonts

**Files:**
- Modify: `ios/slabbist/slabbist.xcodeproj/project.pbxproj`

- [ ] **Step 1: Locate the slabbist app target's build configurations**

Run:
```bash
cd /Users/dixoncider/slabbist/ios/slabbist
grep -nE '^\s*(name = (Debug|Release);|GENERATE_INFOPLIST_FILE|INFOPLIST_KEY)' \
  slabbist.xcodeproj/project.pbxproj | head -40
```
Expected: several `GENERATE_INFOPLIST_FILE = YES;` lines. The `slabbist` app target lives in the configurations with `INFOPLIST_KEY_UILaunchScreen_Generation` and `INFOPLIST_KEY_UIApplicationSceneManifest_Generation` set. Identify those two `XCBuildConfiguration` blocks by searching for them.

- [ ] **Step 2: Add INFOPLIST_KEY_UIAppFonts to both build configs**

Use Python to surgically insert the setting after each `GENERATE_INFOPLIST_FILE = YES;` line that belongs to the app target (the ones that already carry `INFOPLIST_KEY_UILaunchScreen_Generation`). Test target configs do NOT need it.

Create and run the helper script:

```bash
python3 - <<'PY'
import re
from pathlib import Path

p = Path("/Users/dixoncider/slabbist/ios/slabbist/slabbist.xcodeproj/project.pbxproj")
src = p.read_text()

# An app-target build config is one that contains INFOPLIST_KEY_UILaunchScreen_Generation.
# Match each such XCBuildConfiguration block and inject UIAppFonts inside it,
# just after GENERATE_INFOPLIST_FILE. Idempotent: skip if already present.
pattern = re.compile(
    r'(\{\s*isa = XCBuildConfiguration;.*?INFOPLIST_KEY_UILaunchScreen_Generation.*?\};)',
    re.DOTALL,
)

def inject(match: re.Match) -> str:
    block = match.group(1)
    if "INFOPLIST_KEY_UIAppFonts" in block:
        return block
    fonts = (
        "INFOPLIST_KEY_UIAppFonts = (\n"
        "\t\t\t\t\t\"InstrumentSerif-Regular.ttf\",\n"
        "\t\t\t\t\t\"InstrumentSerif-Italic.ttf\",\n"
        "\t\t\t\t);"
    )
    return block.replace(
        "GENERATE_INFOPLIST_FILE = YES;",
        f"GENERATE_INFOPLIST_FILE = YES;\n\t\t\t\t{fonts}",
    )

new = pattern.sub(inject, src)
if new == src:
    raise SystemExit("ERROR: no app-target build configs matched — verify the pbxproj layout")
p.write_text(new)
print("Injected INFOPLIST_KEY_UIAppFonts into app-target build configs")
PY
```

- [ ] **Step 3: Verify the setting lands in compiled build settings**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -showBuildSettings 2>/dev/null | grep -i UIAppFonts
```
Expected: two lines like `INFOPLIST_KEY_UIAppFonts = InstrumentSerif-Regular.ttf InstrumentSerif-Italic.ttf`.

If empty, the pbxproj edit missed the app target's configs — inspect the file and fix the regex or do it manually by hand-editing `slabbist.xcodeproj/project.pbxproj`.

- [ ] **Step 4: Build to verify fonts are embedded**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0. No new warnings about the font setting.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
chore(ios): register Instrument Serif via INFOPLIST_KEY_UIAppFonts

Injects the font filenames into both Debug and Release build configs
of the slabbist app target. Without this the bundled TTFs wouldn't be
discoverable via UIFont(name:) / Font.custom(_:size:).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Font-load sanity test + startup warning

**Files:**
- Modify: `ios/slabbist/slabbist/slabbistApp.swift`
- Create: `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift`:

```swift
import Testing
import SwiftUI
import UIKit
@testable import slabbist

@Suite("Design system smoke")
@MainActor
struct PrimitiveSmokeTests {
    @Test("Instrument Serif Regular loads from bundle")
    func instrumentSerifRegularLoads() {
        let font = UIFont(name: "InstrumentSerif-Regular", size: 12)
        #expect(
            font != nil,
            "InstrumentSerif-Regular.ttf not found — check Resources/Fonts/ files and INFOPLIST_KEY_UIAppFonts."
        )
    }

    @Test("Instrument Serif Italic loads from bundle")
    func instrumentSerifItalicLoads() {
        let font = UIFont(name: "InstrumentSerif-Italic", size: 12)
        #expect(font != nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it passes**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests' \
  -quiet 2>&1 | tail -20
```
Expected: both tests PASS. If they fail, fonts aren't being bundled — revisit Task 2 or 3.

(This is a minor deviation from strict RED→GREEN TDD — Tasks 2+3 have already made the fonts available. The test still enforces the contract going forward, which is its job.)

- [ ] **Step 3: Add startup OSLog warning when the font is missing**

Edit `ios/slabbist/slabbist/slabbistApp.swift` — replace the entire file with:

```swift
import SwiftUI
import SwiftData
import OSLog
import UIKit

@main
struct SlabbistApp: App {
    @State private var session = SessionStore()

    init() {
        Self.verifyCustomFontsLoaded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .onAppear { session.bootstrap() }
                .preferredColorScheme(.dark)
        }
        .modelContainer(AppModelContainer.shared)
    }

    private static let designLog = Logger(
        subsystem: "com.slabbist.designsystem",
        category: "fonts"
    )

    private static func verifyCustomFontsLoaded() {
        let required = ["InstrumentSerif-Regular", "InstrumentSerif-Italic"]
        for name in required where UIFont(name: name, size: 10) == nil {
            designLog.warning("Custom font \(name, privacy: .public) failed to load — bundle or UIAppFonts registration is broken.")
        }
    }
}

private struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.isSignedIn {
            LotsListView()
        } else {
            AuthView()
        }
    }
}
```

(Note: `RootView` still renders `LotsListView` here; Task 13 swaps that for `RootTabView` once the shell screens exist.)

- [ ] **Step 4: Build to verify**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/slabbistApp.swift \
        ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift
git commit -m "$(cat <<'EOF'
feat(ios): force .dark color scheme + font-load sanity check

Adds a startup warning via OSLog when a required custom font fails
to resolve. Forces .preferredColorScheme(.dark) at the app root.
Creates the PrimitiveSmokeTests suite with font-availability tests.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Typography helpers

**Files:**
- Create: `ios/slabbist/slabbist/Core/DesignSystem/Typography.swift`

- [ ] **Step 1: Create Typography.swift**

Write to `ios/slabbist/slabbist/Core/DesignSystem/Typography.swift`:

```swift
import SwiftUI

/// Font constructors tuned for the Slabbist design language.
/// Serif falls back to `.serif` design if the custom font is missing —
/// SwiftUI's `Font.custom(_:size:)` handles that automatically.
enum SlabFont {
    static func serif(size: CGFloat) -> Font {
        .custom("InstrumentSerif-Regular", size: size)
    }

    static func serifItalic(size: CGFloat) -> Font {
        .custom("InstrumentSerif-Italic", size: size)
    }

    static func sans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - View modifiers

extension View {
    /// 68pt Instrument Serif, tracking -2. For portfolio-value-sized numerals.
    func slabHero() -> some View {
        self.font(SlabFont.serif(size: 68))
            .tracking(-2)
            .foregroundStyle(AppColor.text)
    }

    /// 36pt Instrument Serif, tracking -1. For screen titles.
    func slabTitle() -> some View {
        self.font(SlabFont.serif(size: 36))
            .tracking(-1)
            .foregroundStyle(AppColor.text)
    }

    /// 11pt uppercase sans medium, tracking 2.0, .dim foreground.
    /// Precedes every section.
    func slabKicker() -> some View {
        self.font(SlabFont.sans(size: 11, weight: .medium))
            .tracking(2.0)
            .textCase(.uppercase)
            .foregroundStyle(AppColor.dim)
    }

    /// 14pt sans medium, tracking -0.15. Default row title.
    func slabRowTitle() -> some View {
        self.font(SlabFont.sans(size: 14, weight: .medium))
            .tracking(-0.15)
            .foregroundStyle(AppColor.text)
    }

    /// 14pt mono medium. For prices, counts, metric readouts.
    func slabMetric() -> some View {
        self.font(SlabFont.mono(size: 14, weight: .medium))
            .foregroundStyle(AppColor.text)
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/DesignSystem/Typography.swift
git commit -m "$(cat <<'EOF'
feat(ios): add SlabFont + typography view modifiers

SlabFont wraps Font.custom / Font.system so call sites never touch
font names directly. View modifiers (.slabHero, .slabTitle, .slabKicker,
.slabRowTitle, .slabMetric) make the mockup's type scale one-liner-ish.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Theme helpers (SlabbedRoot + ambientGoldBlob)

**Files:**
- Create: `ios/slabbist/slabbist/Core/DesignSystem/Theme.swift`

- [ ] **Step 1: Create Theme.swift**

Write to `ios/slabbist/slabbist/Core/DesignSystem/Theme.swift`:

```swift
import SwiftUI

/// Dark-ink root background for full-screen feature views. Edge-to-edge.
struct SlabbedRoot<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            AppColor.ink.ignoresSafeArea()
            content()
        }
    }
}

enum AmbientBlobPlacement {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

private struct AmbientGoldBlob: ViewModifier {
    let placement: AmbientBlobPlacement

    func body(content: Content) -> some View {
        ZStack {
            GeometryReader { proxy in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppColor.gold.opacity(0.24), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: proxy.size.width * 0.45
                        )
                    )
                    .frame(width: proxy.size.width * 0.9, height: proxy.size.width * 0.9)
                    .blur(radius: 40)
                    .position(center(in: proxy.size))
                    .allowsHitTesting(false)
            }
            content
        }
    }

    private func center(in size: CGSize) -> CGPoint {
        switch placement {
        case .topLeading:     return CGPoint(x: -size.width * 0.1, y: -size.width * 0.1)
        case .topTrailing:    return CGPoint(x: size.width * 1.1,  y: -size.width * 0.1)
        case .bottomLeading:  return CGPoint(x: -size.width * 0.1, y: size.height + size.width * 0.1)
        case .bottomTrailing: return CGPoint(x: size.width * 1.1,  y: size.height + size.width * 0.1)
        }
    }
}

extension View {
    /// Adds a soft, blurred gold radial highlight at a corner.
    /// Used on hero screens (AuthView, future onboarding).
    func ambientGoldBlob(_ placement: AmbientBlobPlacement) -> some View {
        modifier(AmbientGoldBlob(placement: placement))
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/DesignSystem/Theme.swift
git commit -m "$(cat <<'EOF'
feat(ios): add SlabbedRoot container + ambientGoldBlob modifier

SlabbedRoot is the dark-ink backdrop every feature view sits on.
ambientGoldBlob adds the mockup's soft off-screen gold highlight
via a corner-anchored radial gradient.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Primitive — KickerLabel

**Files:**
- Create: `ios/slabbist/slabbist/Core/DesignSystem/Components/KickerLabel.swift`
- Modify: `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift`

- [ ] **Step 1: Write the failing smoke test**

Append to `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift` (inside the `@Suite` struct):

```swift
    @Test("KickerLabel renders")
    func kickerLabelRenders() {
        let host = UIHostingController(rootView: KickerLabel("CURRENT LOTS"))
        _ = host.view // forces layout; non-nil if view graph compiles
        #expect(host.view != nil)
    }
```

- [ ] **Step 2: Run test — expect FAIL (type not defined)**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests/kickerLabelRenders' \
  -quiet 2>&1 | tail -10
```
Expected: BUILD FAIL with `cannot find 'KickerLabel' in scope`.

- [ ] **Step 3: Implement KickerLabel**

Write to `ios/slabbist/slabbist/Core/DesignSystem/Components/KickerLabel.swift`:

```swift
import SwiftUI

/// Small uppercase category / section label.
/// Appears above nearly every titled block in the design.
struct KickerLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .slabKicker()
    }
}

#Preview("KickerLabel") {
    VStack(alignment: .leading, spacing: 12) {
        KickerLabel("Current lots")
        KickerLabel("Recent comps")
        KickerLabel("Portfolio")
    }
    .padding()
    .background(AppColor.ink)
}
```

- [ ] **Step 4: Run test — expect PASS**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests/kickerLabelRenders' \
  -quiet 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/DesignSystem/Components/KickerLabel.swift \
        ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift
git commit -m "$(cat <<'EOF'
feat(ios): add KickerLabel primitive

Small uppercase tracking-2 label used above every titled section.
Pure composition of .slabKicker(). Smoke test guards the type.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Primitive — SlabCard

**Files:**
- Create: `ios/slabbist/slabbist/Core/DesignSystem/Components/SlabCard.swift`
- Modify: `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift`

- [ ] **Step 1: Write the failing smoke test**

Append to the `PrimitiveSmokeTests` suite:

```swift
    @Test("SlabCard renders with content")
    func slabCardRenders() {
        let host = UIHostingController(rootView: SlabCard {
            Text("body")
        })
        #expect(host.view != nil)
    }
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests/slabCardRenders' \
  -quiet 2>&1 | tail -10
```
Expected: BUILD FAIL with `cannot find 'SlabCard' in scope`.

- [ ] **Step 3: Implement SlabCard**

Write to `ios/slabbist/slabbist/Core/DesignSystem/Components/SlabCard.swift`:

```swift
import SwiftUI

/// Grouped container used for almost every row-list in the app.
/// Dark elev fill, hairline border, rounded corners. Callers handle
/// their own inner dividers (use `SlabCardDivider`).
struct SlabCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.elev)
            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .stroke(AppColor.hairline, lineWidth: 1)
            )
    }
}

/// Hairline divider for use between rows inside a `SlabCard`.
struct SlabCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColor.hairline)
            .frame(height: 1)
    }
}

#Preview("SlabCard") {
    VStack(spacing: Spacing.l) {
        SlabCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("First row").slabRowTitle()
                    Spacer()
                    Text("$1,284").slabMetric()
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
                SlabCardDivider()
                HStack {
                    Text("Second row").slabRowTitle()
                    Spacer()
                    Text("$342").slabMetric()
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
            }
        }
    }
    .padding()
    .background(AppColor.ink)
}
```

- [ ] **Step 4: Run test — expect PASS**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests/slabCardRenders' \
  -quiet 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/DesignSystem/Components/SlabCard.swift \
        ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift
git commit -m "$(cat <<'EOF'
feat(ios): add SlabCard + SlabCardDivider primitives

Grouped container with elev fill and hairline border. Callers compose
their own inner dividers. Covers the mockup's row-list pattern.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Primitive — PrimaryGoldButton

**Files:**
- Create: `ios/slabbist/slabbist/Core/DesignSystem/Components/PrimaryGoldButton.swift`
- Modify: `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift`

- [ ] **Step 1: Write the failing smoke test**

Append:

```swift
    @Test("PrimaryGoldButton renders")
    func primaryGoldButtonRenders() {
        let host = UIHostingController(
            rootView: PrimaryGoldButton(title: "Start scanning", action: {})
        )
        #expect(host.view != nil)
    }
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests/primaryGoldButtonRenders' \
  -quiet 2>&1 | tail -10
```
Expected: BUILD FAIL with `cannot find 'PrimaryGoldButton' in scope`.

- [ ] **Step 3: Implement PrimaryGoldButton**

Write to `ios/slabbist/slabbist/Core/DesignSystem/Components/PrimaryGoldButton.swift`:

```swift
import SwiftUI

/// Full-width gold-gradient CTA button. Optional leading icon tile + trailing chevron
/// match the mockup's "Scan cards" pattern.
struct PrimaryGoldButton: View {
    let title: String
    var systemIcon: String? = nil
    var trailingChevron: Bool = false
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                if let icon = systemIcon {
                    Circle()
                        .fill(AppColor.ink)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(AppColor.gold)
                        )
                }

                if isLoading {
                    ProgressView().tint(AppColor.ink)
                } else {
                    Text(title)
                        .font(SlabFont.sans(size: 16, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(AppColor.ink)
                        .frame(maxWidth: .infinity, alignment: systemIcon == nil ? .center : .leading)
                }

                if trailingChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.ink)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .frame(height: systemIcon == nil ? 52 : 68)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [AppColor.gold, AppColor.goldDim],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .shadow(color: AppColor.gold.opacity(0.13), radius: 18, y: 14)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .disabled(!isEnabled || isLoading)
    }
}

#Preview("PrimaryGoldButton") {
    VStack(spacing: Spacing.l) {
        PrimaryGoldButton(title: "Continue", action: {})
        PrimaryGoldButton(
            title: "Scan cards",
            systemIcon: "viewfinder",
            trailingChevron: true,
            action: {}
        )
        PrimaryGoldButton(title: "Loading", isLoading: true, action: {})
        PrimaryGoldButton(title: "Disabled", isEnabled: false, action: {})
    }
    .padding()
    .background(AppColor.ink)
}
```

- [ ] **Step 4: Run test — expect PASS**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests/primaryGoldButtonRenders' \
  -quiet 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/DesignSystem/Components/PrimaryGoldButton.swift \
        ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift
git commit -m "$(cat <<'EOF'
feat(ios): add PrimaryGoldButton primitive

Gold-gradient CTA with optional leading icon-tile and trailing chevron.
Supports loading and disabled states. Used for every "start" action.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Primitive — SecondaryIconButton

**Files:**
- Create: `ios/slabbist/slabbist/Core/DesignSystem/Components/SecondaryIconButton.swift`
- Modify: `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift`

- [ ] **Step 1: Write the failing smoke test**

Append:

```swift
    @Test("SecondaryIconButton renders")
    func secondaryIconButtonRenders() {
        let host = UIHostingController(
            rootView: SecondaryIconButton(systemIcon: "xmark", action: {})
        )
        #expect(host.view != nil)
    }
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests/secondaryIconButtonRenders' \
  -quiet 2>&1 | tail -10
```
Expected: BUILD FAIL.

- [ ] **Step 3: Implement SecondaryIconButton**

Write to `ios/slabbist/slabbist/Core/DesignSystem/Components/SecondaryIconButton.swift`:

```swift
import SwiftUI

/// 40×40 circular button used for close/back/bell/filter affordances.
struct SecondaryIconButton: View {
    let systemIcon: String
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemIcon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColor.text)
                .frame(width: 40, height: 40)
                .background(AppColor.elev)
                .clipShape(Circle())
                .overlay(Circle().stroke(AppColor.hairline, lineWidth: 1))
        }
        .accessibilityLabel(accessibilityLabel ?? systemIcon)
    }
}

#Preview("SecondaryIconButton") {
    HStack(spacing: Spacing.s) {
        SecondaryIconButton(systemIcon: "xmark", action: {})
        SecondaryIconButton(systemIcon: "chevron.left", action: {})
        SecondaryIconButton(systemIcon: "bell", action: {})
        SecondaryIconButton(systemIcon: "line.3.horizontal.decrease", action: {})
    }
    .padding()
    .background(AppColor.ink)
}
```

- [ ] **Step 4: Run test — expect PASS**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests/secondaryIconButtonRenders' \
  -quiet 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/DesignSystem/Components/SecondaryIconButton.swift \
        ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift
git commit -m "$(cat <<'EOF'
feat(ios): add SecondaryIconButton primitive

Small circular icon-only button used for close/back/bell/filter.
Forty-point diameter, elev fill, hairline stroke.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Primitive — PillToggle

**Files:**
- Create: `ios/slabbist/slabbist/Core/DesignSystem/Components/PillToggle.swift`
- Modify: `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift`

- [ ] **Step 1: Write the failing smoke test**

Append:

```swift
    @Test("PillToggle renders")
    @MainActor
    func pillToggleRenders() {
        struct Host: View {
            @State var selection: String = "a"
            var body: some View {
                PillToggle(
                    selection: $selection,
                    options: [("a", "One"), ("b", "Two")],
                    style: .accent
                )
            }
        }
        let host = UIHostingController(rootView: Host())
        #expect(host.view != nil)
    }
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests/pillToggleRenders' \
  -quiet 2>&1 | tail -10
```
Expected: BUILD FAIL.

- [ ] **Step 3: Implement PillToggle**

Write to `ios/slabbist/slabbist/Core/DesignSystem/Components/PillToggle.swift`:

```swift
import SwiftUI

/// Horizontal pill with an inset selected segment.
/// Two visual styles: `.accent` (gold selection, mockup's camera-mode toggle)
/// and `.neutral` (elev2 selection, grid/list view toggle).
struct PillToggle<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var style: Style = .neutral

    enum Style {
        case accent
        case neutral
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(SlabFont.sans(size: 12, weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(foreground(for: option.value))
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.s)
                        .background(background(for: option.value))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                }
            }
        }
        .padding(4)
        .background(AppColor.elev)
        .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .stroke(AppColor.hairline, lineWidth: 1)
        )
    }

    private func foreground(for value: Value) -> Color {
        let selected = selection == value
        switch style {
        case .accent:  return selected ? AppColor.ink  : AppColor.text
        case .neutral: return selected ? AppColor.text : AppColor.dim
        }
    }

    private func background(for value: Value) -> Color {
        let selected = selection == value
        switch style {
        case .accent:  return selected ? AppColor.gold  : .clear
        case .neutral: return selected ? AppColor.elev2 : .clear
        }
    }
}

#Preview("PillToggle") {
    struct Demo: View {
        @State var mode: String = "ar"
        @State var view: String = "grid"
        var body: some View {
            VStack(spacing: Spacing.l) {
                PillToggle(
                    selection: $mode,
                    options: [("ar", "AR"), ("batch", "Batch")],
                    style: .accent
                )
                PillToggle(
                    selection: $view,
                    options: [("grid", "Grid"), ("list", "List")],
                    style: .neutral
                )
            }
            .padding()
            .background(AppColor.ink)
        }
    }
    return Demo()
}
```

- [ ] **Step 4: Run test — expect PASS**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests/pillToggleRenders' \
  -quiet 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/DesignSystem/Components/PillToggle.swift \
        ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift
git commit -m "$(cat <<'EOF'
feat(ios): add PillToggle primitive

Two-segment pill with .accent (gold selection) and .neutral (elev2)
styles. Drives the mockup's mode and view toggles.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Primitive — StatStrip

**Files:**
- Create: `ios/slabbist/slabbist/Core/DesignSystem/Components/StatStrip.swift`
- Modify: `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift`

- [ ] **Step 1: Write the failing smoke test**

Append:

```swift
    @Test("StatStrip renders")
    func statStripRenders() {
        let host = UIHostingController(rootView: StatStrip(items: [
            .init(label: "Cards", value: "12"),
            .init(label: "Value", value: "$4.1k"),
            .init(label: "Change", value: "+2.4%"),
        ]))
        #expect(host.view != nil)
    }
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests/statStripRenders' \
  -quiet 2>&1 | tail -10
```
Expected: BUILD FAIL.

- [ ] **Step 3: Implement StatStrip**

Write to `ios/slabbist/slabbist/Core/DesignSystem/Components/StatStrip.swift`:

```swift
import SwiftUI

/// Horizontal 3-or-more-cell metric strip divided by vertical hairlines.
struct StatStrip: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var valueTint: Color = AppColor.text
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(AppColor.hairline)
                        .frame(width: 1)
                }
                VStack(spacing: Spacing.xs) {
                    Text(item.value)
                        .font(SlabFont.mono(size: 18, weight: .medium))
                        .tracking(-0.3)
                        .foregroundStyle(item.valueTint)
                    Text(item.label.uppercased())
                        .font(SlabFont.sans(size: 10, weight: .medium))
                        .tracking(1.4)
                        .foregroundStyle(AppColor.dim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
            }
        }
    }
}

#Preview("StatStrip") {
    VStack {
        StatStrip(items: [
            .init(label: "Cards", value: "342"),
            .init(label: "Est. value", value: "$12.4k"),
            .init(label: "30 days", value: "+4.1%", valueTint: AppColor.positive),
        ])
    }
    .padding()
    .background(AppColor.elev)
}
```

- [ ] **Step 4: Run test — expect PASS**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/PrimitiveSmokeTests/statStripRenders' \
  -quiet 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/DesignSystem/Components/StatStrip.swift \
        ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift
git commit -m "$(cat <<'EOF'
feat(ios): add StatStrip primitive

3-or-more-cell metric strip divided by vertical hairlines. Mono numerals
with a small uppercase kicker label. Used on headers and summary blocks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: SessionStore.signOut() + test

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Auth/SessionStore.swift`
- Create: `ios/slabbist/slabbistTests/Features/Auth/SessionStoreSignOutTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/slabbist/slabbistTests/Features/Auth/SessionStoreSignOutTests.swift`:

```swift
import Testing
import Foundation
@testable import slabbist

@Suite("SessionStore sign-out")
@MainActor
struct SessionStoreSignOutTests {
    @Test("signOut() exists and returns without throwing when already signed out")
    func signOutIsCallableWhenAlreadySignedOut() async {
        let store = SessionStore()
        // Not bootstrap()'d — userId is nil. signOut() should be a no-op.
        await store.signOut()
        #expect(store.userId == nil)
        #expect(store.isSignedIn == false)
    }
}
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/SessionStoreSignOutTests' \
  -quiet 2>&1 | tail -10
```
Expected: BUILD FAIL with `value of type 'SessionStore' has no member 'signOut'`.

- [ ] **Step 3: Implement signOut()**

Replace the body of `ios/slabbist/slabbist/Features/Auth/SessionStore.swift` (keep the existing methods; append `signOut`) with:

```swift
import Foundation
import Observation
import Supabase
import OSLog

@Observable
@MainActor
final class SessionStore {
    private(set) var userId: UUID?
    private(set) var isLoading = false

    private let client: SupabaseClient
    private var authTask: Task<Void, Never>?

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
    }

    func bootstrap() {
        authTask?.cancel()
        let client = self.client
        authTask = Task { [weak self] in
            for await change in client.auth.authStateChanges {
                await MainActor.run {
                    self?.userId = change.session?.user.id
                }
            }
        }

        Task { [weak self] in
            let session = try? await client.auth.session
            await MainActor.run {
                self?.userId = session?.user.id
            }
        }
    }

    /// Clears the Supabase auth session and resets local user state.
    /// No-op (still returns cleanly) when the caller is already signed out.
    func signOut() async {
        let client = self.client
        do {
            try await client.auth.signOut()
        } catch {
            Self.log.warning("Supabase signOut failed: \(error.localizedDescription, privacy: .public)")
        }
        self.userId = nil
    }

    var isSignedIn: Bool { userId != nil }

    private static let log = Logger(subsystem: "com.slabbist.auth", category: "session")
}
```

- [ ] **Step 4: Run test — expect PASS**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'slabbistTests/SessionStoreSignOutTests' \
  -quiet 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Auth/SessionStore.swift \
        ios/slabbist/slabbistTests/Features/Auth/SessionStoreSignOutTests.swift
git commit -m "$(cat <<'EOF'
feat(ios): add SessionStore.signOut()

Calls client.auth.signOut() and clears userId. Safe to call when
already signed out (no-op). Logs a warning on Supabase failure
rather than propagating — we still want local state cleared.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: SettingsView

**Files:**
- Create: `ios/slabbist/slabbist/Features/Settings/SettingsView.swift`

- [ ] **Step 1: Create SettingsView**

Write to `ios/slabbist/slabbist/Features/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header

                    SlabCard {
                        Button {
                            Task { await session.signOut() }
                        } label: {
                            HStack {
                                Text("Sign out").slabRowTitle()
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(AppColor.dim)
                            }
                            .padding(.horizontal, Spacing.l)
                            .padding(.vertical, Spacing.md)
                        }
                        .buttonStyle(.plain)
                    }

                    SlabCard {
                        VStack(spacing: 0) {
                            infoRow(label: "Version", value: Self.versionString)
                            SlabCardDivider()
                            infoRow(label: "Build", value: Self.buildString)
                        }
                    }

                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("More")
            Text("Settings").slabTitle()
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).slabRowTitle()
            Spacer()
            Text(value).slabMetric().foregroundStyle(AppColor.muted)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
    }

    private static var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private static var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

#Preview {
    SettingsView()
        .environment(SessionStore())
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Settings/SettingsView.swift
git commit -m "$(cat <<'EOF'
feat(ios): add SettingsView (sign-out + version/build readout)

Minimal "More" tab destination: one card with sign-out, one card with
read-only version + build. Composes SlabbedRoot / SlabCard / KickerLabel.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: ScanShortcutView

**Files:**
- Create: `ios/slabbist/slabbist/Features/Shell/ScanShortcutView.swift`

- [ ] **Step 1: Create ScanShortcutView**

Write to `ios/slabbist/slabbist/Features/Shell/ScanShortcutView.swift`:

```swift
import SwiftUI
import SwiftData
import OSLog

/// Destination of the "Scan" tab. Resolves to either the most recent open lot's
/// `BulkScanView` (if one exists) or presents `NewLotSheet` to create one.
struct ScanShortcutView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session

    @State private var viewModel: LotsViewModel?
    @State private var resolvedLot: Lot?
    @State private var showingNewLot = false

    var body: some View {
        NavigationStack {
            SlabbedRoot {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        KickerLabel("Scan")
                        Text("New bulk scan").slabTitle()
                    }
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.top, Spacing.l)

                    VStack(spacing: Spacing.m) {
                        PrimaryGoldButton(
                            title: "Start new lot",
                            systemIcon: "plus",
                            trailingChevron: true,
                            action: { showingNewLot = true }
                        )
                        if let lot = resolvedLot {
                            NavigationLink {
                                BulkScanView(lot: lot)
                            } label: {
                                SlabCard {
                                    HStack {
                                        VStack(alignment: .leading, spacing: Spacing.xs) {
                                            Text("Resume \(lot.name)").slabRowTitle()
                                            Text("Most recent open lot")
                                                .font(SlabFont.sans(size: 12))
                                                .foregroundStyle(AppColor.dim)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(AppColor.dim)
                                    }
                                    .padding(.horizontal, Spacing.l)
                                    .padding(.vertical, Spacing.md)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.xxl)

                    Spacer()
                }
            }
            .sheet(isPresented: $showingNewLot) {
                if let viewModel {
                    NewLotSheet { name in
                        let lot = try viewModel.createLot(name: name)
                        resolvedLot = lot
                    }
                }
            }
            .onAppear {
                bootstrap()
                refresh()
            }
        }
    }

    private func bootstrap() {
        guard viewModel == nil, let userId = session.userId else { return }
        let ownerId = userId
        var desc = FetchDescriptor<Store>(predicate: #Predicate<Store> { $0.ownerUserId == ownerId })
        desc.fetchLimit = 1
        if let store = try? context.fetch(desc).first {
            viewModel = LotsViewModel(context: context, currentUserId: userId, currentStoreId: store.id)
        }
    }

    private func refresh() {
        guard let viewModel else { return }
        resolvedLot = (try? viewModel.listOpenLots())?.first
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Shell/ScanShortcutView.swift
git commit -m "$(cat <<'EOF'
feat(ios): add ScanShortcutView (Scan tab destination)

Resolves to either a Resume-card that pushes BulkScanView for the most
recent open lot, or a "Start new lot" gold CTA that presents NewLotSheet.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: RootTabView + wire into slabbistApp

**Files:**
- Create: `ios/slabbist/slabbist/Features/Shell/RootTabView.swift`
- Modify: `ios/slabbist/slabbist/slabbistApp.swift`

- [ ] **Step 1: Create RootTabView**

Write to `ios/slabbist/slabbist/Features/Shell/RootTabView.swift`:

```swift
import SwiftUI

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

- [ ] **Step 2: Swap the root to RootTabView**

Replace `ios/slabbist/slabbist/slabbistApp.swift` with:

```swift
import SwiftUI
import SwiftData
import OSLog
import UIKit

@main
struct SlabbistApp: App {
    @State private var session = SessionStore()

    init() {
        Self.verifyCustomFontsLoaded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .onAppear { session.bootstrap() }
                .preferredColorScheme(.dark)
        }
        .modelContainer(AppModelContainer.shared)
    }

    private static let designLog = Logger(
        subsystem: "com.slabbist.designsystem",
        category: "fonts"
    )

    private static func verifyCustomFontsLoaded() {
        let required = ["InstrumentSerif-Regular", "InstrumentSerif-Italic"]
        for name in required where UIFont(name: name, size: 10) == nil {
            designLog.warning("Custom font \(name, privacy: .public) failed to load — bundle or UIAppFonts registration is broken.")
        }
    }
}

private struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.isSignedIn {
            RootTabView()
        } else {
            AuthView()
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0.

- [ ] **Step 4: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Shell/RootTabView.swift \
        ios/slabbist/slabbist/slabbistApp.swift
git commit -m "$(cat <<'EOF'
feat(ios): 3-tab RootTabView (Lots / Scan / More)

Signed-in root now renders RootTabView with gold tint, translucent
dark bar. Scan tab shortcuts to the most recent open lot or creates a
new one; More tab lands on SettingsView.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 17: Repaint AuthView

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Auth/AuthView.swift`

- [ ] **Step 1: Replace AuthView**

Write `ios/slabbist/slabbist/Features/Auth/AuthView.swift` with:

```swift
import SwiftUI

struct AuthView: View {
    @State private var viewModel = AuthViewModel()

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxxl) {
                    brand

                    VStack(alignment: .leading, spacing: Spacing.m) {
                        KickerLabel(viewModel.mode == .signIn ? "Welcome back" : "Create account")
                        Text("Slabbist").slabTitle()
                        Text(subtitle)
                            .font(SlabFont.sans(size: 15))
                            .foregroundStyle(AppColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SlabCard {
                        VStack(spacing: 0) {
                            field(icon: "envelope") {
                                TextField("", text: $viewModel.email, prompt:
                                    Text("Email").foregroundStyle(AppColor.dim))
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .foregroundStyle(AppColor.text)
                                    .tint(AppColor.gold)
                            }
                            SlabCardDivider()
                            field(icon: "lock") {
                                SecureField("", text: $viewModel.password, prompt:
                                    Text("Password").foregroundStyle(AppColor.dim))
                                    .textContentType(viewModel.mode == .signIn ? .password : .newPassword)
                                    .foregroundStyle(AppColor.text)
                                    .tint(AppColor.gold)
                            }
                            if viewModel.mode == .signUp {
                                SlabCardDivider()
                                field(icon: "storefront") {
                                    TextField("", text: $viewModel.storeName, prompt:
                                        Text("Store name (optional)").foregroundStyle(AppColor.dim))
                                        .foregroundStyle(AppColor.text)
                                        .tint(AppColor.gold)
                                }
                            }
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(SlabFont.sans(size: 13))
                            .foregroundStyle(AppColor.negative)
                    }

                    PrimaryGoldButton(
                        title: viewModel.mode == .signIn ? "Sign in" : "Create account",
                        isLoading: viewModel.isSubmitting,
                        isEnabled: !viewModel.email.isEmpty && !viewModel.password.isEmpty
                    ) {
                        Task { await viewModel.submit() }
                    }

                    Button {
                        viewModel.mode = (viewModel.mode == .signIn) ? .signUp : .signIn
                    } label: {
                        Text(viewModel.mode == .signIn
                             ? "Don't have an account? Create one"
                             : "Already have an account? Sign in")
                            .font(SlabFont.sans(size: 14))
                            .foregroundStyle(AppColor.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.xxxl)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .ambientGoldBlob(.topTrailing)
    }

    private var subtitle: String {
        viewModel.mode == .signIn
        ? "Sign in to your store to continue scanning."
        : "Create your store to start bulk-scanning slabs."
    }

    private var brand: some View {
        HStack(spacing: Spacing.s) {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(LinearGradient(colors: [AppColor.gold, AppColor.goldDim],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 18, height: 18)
            Text("SLABBIST")
                .font(SlabFont.sans(size: 14, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(AppColor.text)
        }
    }

    private func field<Content: View>(icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: icon)
                .foregroundStyle(AppColor.dim)
                .frame(width: 18)
            content()
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
    }
}

#Preview {
    AuthView()
}
```

- [ ] **Step 2: Build and run existing tests to confirm no regression**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Auth/AuthView.swift
git commit -m "$(cat <<'EOF'
feat(ios): repaint AuthView in the dark+gold design language

SlabbedRoot + ambient gold blob, kicker + serif title, SlabCard-wrapped
fields with hairline dividers, PrimaryGoldButton submit, mode toggle
moves from a segmented picker to an inline text link.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 18: Repaint LotsListView

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Lots/LotsListView.swift`

- [ ] **Step 1: Replace LotsListView**

Write `ios/slabbist/slabbist/Features/Lots/LotsListView.swift` with:

```swift
import SwiftUI
import SwiftData
import OSLog

struct LotsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session

    @State private var showingNewLot = false
    @State private var lots: [Lot] = []
    @State private var selectedLot: Lot?
    @State private var viewModel: LotsViewModel?

    var body: some View {
        NavigationStack {
            SlabbedRoot {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        header

                        PrimaryGoldButton(
                            title: "New bulk scan",
                            systemIcon: "viewfinder",
                            trailingChevron: true
                        ) {
                            showingNewLot = true
                        }

                        if lots.isEmpty {
                            emptyStateCard
                        } else {
                            openLotsSection
                        }

                        Spacer(minLength: Spacing.xxxl)
                    }
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.xxxl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingNewLot) {
                if let viewModel {
                    NewLotSheet { name in
                        let lot = try viewModel.createLot(name: name)
                        refresh()
                        selectedLot = lot
                    }
                }
            }
            .navigationDestination(item: $selectedLot) { lot in
                BulkScanView(lot: lot)
            }
            .onAppear {
                bootstrapViewModel()
                refresh()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Current lots")
            Text(headerTitle).slabTitle()
            if !lots.isEmpty {
                Text(headerSubtitle)
                    .font(SlabFont.mono(size: 13))
                    .foregroundStyle(AppColor.muted)
            }
        }
    }

    private var headerTitle: String {
        switch lots.count {
        case 0:  return "No open lots"
        case 1:  return "1 open lot"
        default: return "\(lots.count) open lots"
        }
    }

    private var headerSubtitle: String {
        let totalScans = lots.reduce(0) { $0 + $1.scans.count }
        let lastUpdated = lots.map(\.updatedAt).max()
        guard let lastUpdated else { return "\(totalScans) scans" }
        let rel = Self.relative.localizedString(for: lastUpdated, relativeTo: Date())
        return "\(totalScans) scans · Updated \(rel)"
    }

    private var openLotsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Open lots")
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(Array(lots.enumerated()), id: \.element.id) { index, lot in
                        Button {
                            selectedLot = lot
                        } label: {
                            row(for: lot)
                        }
                        .buttonStyle(.plain)
                        if index < lots.count - 1 {
                            SlabCardDivider()
                        }
                    }
                }
            }
        }
    }

    private func row(for lot: Lot) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(lot.name).slabRowTitle()
                Text(rowSubtitle(for: lot))
                    .font(SlabFont.mono(size: 12))
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColor.dim)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
    }

    private func rowSubtitle(for lot: Lot) -> String {
        let rel = Self.relative.localizedString(for: lot.updatedAt, relativeTo: Date())
        return "\(lot.scans.count) scans · \(rel)"
    }

    private var emptyStateCard: some View {
        SlabCard {
            VStack(spacing: Spacing.m) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(AppColor.gold.opacity(0.75))
                    .padding(.top, Spacing.l)
                Text("No lots yet")
                    .font(SlabFont.serif(size: 28))
                    .tracking(-0.8)
                    .foregroundStyle(AppColor.text)
                Text("Start your first bulk scan to see it here.")
                    .font(SlabFont.sans(size: 14))
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
                Spacer(minLength: Spacing.l)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.l)
        }
    }

    private func bootstrapViewModel() {
        guard viewModel == nil else { return }
        guard let userId = session.userId else { return }
        let ownerId = userId
        var descriptor = FetchDescriptor<Store>(
            predicate: #Predicate<Store> { $0.ownerUserId == ownerId }
        )
        descriptor.fetchLimit = 1
        if let store = try? context.fetch(descriptor).first {
            viewModel = LotsViewModel(context: context, currentUserId: userId, currentStoreId: store.id)
        } else {
            AppLog.lots.warning("no local Store for user \(userId, privacy: .public); view model deferred")
        }
    }

    private func refresh() {
        guard let viewModel else {
            lots = []
            return
        }
        do {
            lots = try viewModel.listOpenLots()
        } catch {
            AppLog.lots.error("listOpenLots failed: \(error.localizedDescription, privacy: .public)")
            lots = []
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0. (If `lot.scans.count` fails because `Lot` doesn't expose a `scans` relationship, swap that for the appropriate accessor — inspect `Core/Models/Lot.swift`.)

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Lots/LotsListView.swift
git commit -m "$(cat <<'EOF'
feat(ios): repaint LotsListView in the new design language

Kicker + serif header with open-lot count, gold primary CTA, SlabCard-
wrapped open-lots section with hairline-divided rows, new empty-state
card. Navigation toolbar is hidden; the in-body layout is the header.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 19: Repaint NewLotSheet

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Lots/NewLotSheet.swift`

- [ ] **Step 1: Replace NewLotSheet**

Write `ios/slabbist/slabbist/Features/Lots/NewLotSheet.swift` with:

```swift
import SwiftUI

struct NewLotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = defaultName()
    @State private var error: String?

    let onCreate: (String) throws -> Void

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                topBar
                header
                SlabCard {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(AppColor.dim)
                            .frame(width: 18)
                        TextField("", text: $name,
                                  prompt: Text("Lot name").foregroundStyle(AppColor.dim))
                            .textInputAutocapitalization(.words)
                            .foregroundStyle(AppColor.text)
                            .tint(AppColor.gold)
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
                }
                if let error {
                    Text(error)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.negative)
                }
                Spacer()
                PrimaryGoldButton(
                    title: "Start scanning",
                    isEnabled: !trimmedName.isEmpty
                ) {
                    do {
                        try onCreate(trimmedName)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
    }

    private var topBar: some View {
        HStack {
            SecondaryIconButton(systemIcon: "xmark", accessibilityLabel: "Cancel") {
                dismiss()
            }
            Spacer()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("New lot")
            Text("Start scanning").slabTitle()
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private static func defaultName() -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return "Bulk – \(fmt.string(from: Date()))"
    }
}

#Preview {
    NewLotSheet { _ in }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Lots/NewLotSheet.swift
git commit -m "$(cat <<'EOF'
feat(ios): repaint NewLotSheet in the new design language

Drops Form/NavigationStack scaffolding; sheet now renders SlabbedRoot
with top-bar close, kicker + serif title, SlabCard-wrapped field,
PrimaryGoldButton CTA.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 20: Tokens retint BulkScanView + ScanQueueView

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanView.swift`
- Modify: `ios/slabbist/slabbist/Features/Scanning/BulkScan/ScanQueueView.swift`

- [ ] **Step 1: Read ScanQueueView to understand current structure**

```bash
cat /Users/dixoncider/slabbist/ios/slabbist/slabbist/Features/Scanning/BulkScan/ScanQueueView.swift
```
Note its current row layout so the retint preserves data flow.

- [ ] **Step 2: Retint ScanQueueView**

Replace `ios/slabbist/slabbist/Features/Scanning/BulkScan/ScanQueueView.swift` — if the existing file is a simple list of `Scan` rows, apply these tokens. (If its structure is different, preserve behavior and only swap styles to match the pattern below.)

```swift
import SwiftUI

struct ScanQueueView: View {
    let scans: [Scan]

    var body: some View {
        if scans.isEmpty {
            Text("No scans yet")
                .font(SlabFont.sans(size: 13))
                .foregroundStyle(AppColor.dim)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.md)
        } else {
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(Array(scans.prefix(6).enumerated()), id: \.element.id) { index, scan in
                        row(for: scan)
                        if index < min(scans.count, 6) - 1 {
                            SlabCardDivider()
                        }
                    }
                }
            }
        }
    }

    private func row(for scan: Scan) -> some View {
        HStack(spacing: Spacing.m) {
            Circle()
                .fill(statusColor(for: scan))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(scan.grader.rawValue) · \(scan.certNumber)")
                    .slabRowTitle()
                Text(scan.status.rawValue.replacingOccurrences(of: "_", with: " "))
                    .font(SlabFont.mono(size: 11))
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    private func statusColor(for scan: Scan) -> Color {
        switch scan.status {
        case .validated:          return AppColor.positive
        case .pendingValidation:  return AppColor.gold
        case .validationFailed:   return AppColor.negative
        case .manualEntry:        return AppColor.muted
        }
    }
}
```

If the actual `ScanStatus` enum case names differ from `.pendingValidation/.validated/.validationFailed/.manualEntry`, match whatever the real enum has.

- [ ] **Step 3: Retint BulkScanView**

Modify `ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanView.swift` — change only the presentation; keep all camera-session + Vision-pipeline logic intact. Replace the `body` and the helper views with:

```swift
    var body: some View {
        ZStack(alignment: .bottom) {
            cameraArea
                .ignoresSafeArea(edges: [.top, .horizontal])
                .overlay(alignment: .center) {
                    if lastCaptureFlash {
                        Color.white.opacity(0.35)
                            .allowsHitTesting(false)
                    }
                }

            if let viewModel = controller.viewModel {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    summaryHeader(for: viewModel)
                    ScanQueueView(scans: viewModel.recentScans)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.vertical, Spacing.l)
                .background(AppColor.ink.opacity(0.92))
            }
        }
        .background(AppColor.ink)
        .navigationTitle(lot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            bootstrapViewModel()
            Task { await configureCamera() }
        }
        .onDisappear {
            cameraSession.stop()
        }
    }

    @ViewBuilder
    private var cameraArea: some View {
        switch cameraSession.authorization {
        case .authorized:
            CameraPreview(session: cameraSession.captureSession)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied, .restricted:
            VStack(spacing: Spacing.m) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColor.dim)
                Text("Camera access is required to scan slabs.")
                    .font(SlabFont.sans(size: 15))
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
                PrimaryGoldButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .padding(.horizontal, Spacing.xxl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.ink)
        case .notDetermined:
            ProgressView()
                .tint(AppColor.gold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.ink)
        }
    }

    private func summaryHeader(for viewModel: BulkScanViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            KickerLabel("Queue")
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text("\(viewModel.recentScans.count)").slabMetric()
                Text("scanned")
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.muted)
            }
        }
    }
```

Leave the existing `bootstrapViewModel()` and `configureCamera()` methods untouched. Only imports + the `body` / `cameraArea` / `summaryLine → summaryHeader` rename change.

- [ ] **Step 4: Build**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanView.swift \
        ios/slabbist/slabbist/Features/Scanning/BulkScan/ScanQueueView.swift
git commit -m "$(cat <<'EOF'
feat(ios): tokens-only retint for BulkScanView + ScanQueueView

Camera session + OCR pipeline untouched. Bottom sheet moves onto the
dark ink surface with a kicker/metric summary header. Camera-denied
empty state uses PrimaryGoldButton. Nav bar becomes ultraThinMaterial.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 21: Remove legacy AppColor aliases

**Files:**
- Modify: `ios/slabbist/slabbist/Core/DesignSystem/Tokens.swift`
- Any residual call sites still using the aliases.

- [ ] **Step 1: Find remaining alias usages**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist/slabbist
grep -rn "AppColor\.(accent\|success\|warning\|danger\|surfaceAlt)" --include="*.swift" .
```
Expected: matches only in `Core/DesignSystem/Tokens.swift` (the alias definitions themselves). If any other file still uses an alias, rewrite the call site to the canonical token:

| Old alias | Replace with |
|---|---|
| `AppColor.accent` | `AppColor.gold` |
| `AppColor.success` | `AppColor.positive` |
| `AppColor.warning` | `AppColor.gold` (or `AppColor.negative` depending on context) |
| `AppColor.danger` | `AppColor.negative` |
| `AppColor.surfaceAlt` | `AppColor.elev` |

- [ ] **Step 2: Remove the alias block from Tokens.swift**

Open `ios/slabbist/slabbist/Core/DesignSystem/Tokens.swift` and delete the `// --- Legacy aliases ---` block (5 lines). The file ends at `static let negative = Color(hex: 0xE0795B)` plus the closing `}`.

- [ ] **Step 3: Build — must still pass**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0. If any "cannot find 'AppColor.X'" error appears, a call site was missed in Step 1 — fix it.

- [ ] **Step 4: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/DesignSystem/Tokens.swift
# If Step 1 required touching other files, add those too.
git commit -m "$(cat <<'EOF'
chore(ios): drop legacy AppColor aliases

Every call site now uses the canonical tokens (gold/positive/negative/elev).
Aliases existed only to keep the refresh in one consistent branch.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 22: Final verification

**Files:** none modified.

- [ ] **Step 1: Run the full test suite**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild test \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -quiet 2>&1 | tail -40
```
Expected: all tests pass, including:

- `slabbistTests/Core/*` (Currency, Reachability, OutboxItem)
- `slabbistTests/Features/BulkScanViewModelTests`
- `slabbistTests/Features/LotsViewModelTests`
- `slabbistTests/Features/CertOCRRecognizerTests` / `CertOCRRecognizerStabilityTests`
- `slabbistTests/Core/DesignSystem/PrimitiveSmokeTests` (font + 6 primitives)
- `slabbistTests/Features/Auth/SessionStoreSignOutTests`
- `slabbistUITests/*`

- [ ] **Step 2: Clean build for good measure**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcodebuild clean -scheme slabbist -quiet
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```
Expected: exit code 0. Warnings should match the preflight baseline (two pre-existing main-actor / nonisolated-unsafe warnings) — no new warnings introduced.

- [ ] **Step 3: Manual simulator walkthrough**

Install and launch the app in the iPhone 17 simulator:

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
xcrun simctl boot 'iPhone 17' 2>/dev/null || true
open -a Simulator
xcodebuild -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build -quiet build
APP=$(find build/Build/Products/Debug-iphonesimulator -maxdepth 2 -name 'slabbist.app' | head -1)
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.yourorg.slabbist 2>/dev/null || \
  xcrun simctl launch booted $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
```

Then walk through the 11 steps from the spec:

1. App lands on AuthView (dark, gold blob top-right, serif "Slabbist" title).
2. Tap "Create one" — flips to signup with store-name field.
3. Enter email/password/store name. Tap "Create account". (Supabase may return an error in the dev environment — that's okay for the UI check; the error renders in `.negative` color. If the signup succeeds, continue. Otherwise manually set `session.userId` via debugger OR ensure a test account exists.)
4. Signed-in root shows three tabs: Lots | Scan | More. Lots is selected, tint is gold. Header reads kicker + serif "0 open lots" or "No open lots".
5. Tap **New bulk scan** — sheet presents with kicker + serif + gold CTA.
6. Tap **Start scanning** — pushes `BulkScanView`. Camera permission prompt appears.
7. Tap **Don't Allow** — renders dark empty state with gold "Open Settings" button.
8. Back → LotsListView now shows one SlabCard row.
9. Tap **Scan** tab — ScanShortcutView resolves the lot; tap Resume to push BulkScanView.
10. Tap **More** tab — kicker + serif "Settings" + sign-out + version/build rows.
11. Tap **Sign out** — returns to AuthView.

Every step must succeed. If any step fails, fix and re-run.

- [ ] **Step 4: Final commit (if any fixes from Step 3)**

Only if manual walkthrough surfaced fixes:

```bash
cd /Users/dixoncider/slabbist
git add <files>
git commit -m "$(cat <<'EOF'
fix(ios): <specific fix from manual walkthrough>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Report completion**

Summarize to the user:
- Build status (exit 0 / warnings count vs baseline)
- Test results (count passing, new tests added)
- Manual walkthrough outcome (step-by-step result)
- Commit range (first + last SHA of the refresh)

---

## Self-review

**Spec coverage:**

| Spec section | Covered by task |
|---|---|
| §Architecture → module layout | Tasks 1, 5, 6, 7–12, 14, 15, 16 |
| §Architecture → dependency flow | Task 16 |
| §Data flow (SessionStore.signOut) | Task 13 |
| §Design tokens | Task 1 |
| §Typography | Tasks 2, 3, 4, 5 |
| §Theme | Task 6 |
| §Primitives (6) | Tasks 7–12 |
| §App shell (RootTabView, ScanShortcutView, SettingsView) | Tasks 14, 15, 16 |
| §Screen repaints (Auth, Lots, NewLot, BulkScan tokens) | Tasks 17–20 |
| §Testing (existing green + PrimitiveSmokeTests) | Tasks 4, 7–13, 22 |
| §Definition of done → legacy alias removal | Task 21 |
| §Definition of done → simulator walkthrough | Task 22 Step 3 |

No spec requirement missing a task.

**Placeholder scan:** No "TBD"/"TODO"/"similar to Task N"/"add appropriate error handling". Two places defer fine-tuning to the implementer ("match whatever the real enum has" for `Scan.status`, "swap that for the appropriate accessor" for `lot.scans` if the relationship differs) — those are labeled as inspection steps inside the affected tasks rather than as plan-level placeholders; the surrounding code is otherwise complete.

**Type consistency:** `SlabFont.serif(size:)`, `.slab*` modifiers, `AppColor.*`, `Spacing.*`, `Radius.*`, `SlabCard`, `SlabCardDivider`, `KickerLabel`, `PrimaryGoldButton`, `SecondaryIconButton`, `PillToggle`, `StatStrip` are used consistently across later tasks matching the signatures defined in their creating tasks. Verified.

**Simulator target:** All xcodebuild commands use `name=iPhone 17` consistently.
