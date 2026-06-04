# TCGplayer Affiliate Links Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "View on TCGplayer" affiliate button to the graded comp, mover, and grade-gain card-detail screens, opening each card's TCGplayer product page through the account's impact.com deep link.

**Architecture:** A pure helper (`TCGPlayerAffiliateLink`) wraps a TCGplayer product id in the impact base tracking URL (`https://partner.tcgplayer.com/c/6098165/1830156/21018?subId1=<surface>&u=<encoded product url>`), mirroring the existing `EbayAffiliateLink`. Raw-card screens already hold `productId` on-device. The graded comp screen needs `tcgplayer_product_id` echoed from the `price-comp` Edge Function, decoded in `CompRepository`, persisted on `GradedMarketSnapshot`, and read by `CompCardView`. A shared `TCGPlayerLinkButton` renders on all three surfaces.

**Tech Stack:** SwiftUI + SwiftData (iOS), Swift Testing; Deno/TypeScript (Supabase Edge Function).

**Reference spec:** `docs/superpowers/specs/2026-06-04-tcgplayer-affiliate-links-design.md`

---

## File Structure

**iOS — create:**
- `ios/slabbist/slabbist/Core/Utilities/TCGPlayerAffiliateLink.swift` — pure link builder.
- `ios/slabbist/slabbist/Core/DesignSystem/Components/TCGPlayerLinkButton.swift` — shared button view.
- `ios/slabbist/slabbistTests/Core/TCGPlayerAffiliateLinkTests.swift` — helper tests.

**iOS — modify:**
- `ios/slabbist/slabbist/Core/Config/AppEnvironment.swift` — add `tcgplayerImpactBaseURL`.
- `ios/slabbist/slabbist/Features/Movers/MoverDetailView.swift` — add button.
- `ios/slabbist/slabbist/Features/GradeGains/GradeGainDetailView.swift` — add button.
- `ios/slabbist/slabbist/Core/Data/Repositories/CompRepository.swift` — decode new field.
- `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift` — persist new field.
- `ios/slabbist/slabbist/Features/Comp/CompFetchService.swift` — pass field into snapshot.
- `ios/slabbist/slabbist/Features/Comp/CompCardView.swift` — render button.
- `ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift` — decode test.
- `ios/slabbist/Config/Secrets.xcconfig.example` — document override var.

**Server — modify:**
- `supabase/functions/price-comp/types.ts` — add response field.
- `supabase/functions/price-comp/index.ts` — echo `identity.tcgplayer_product_id`.
- `supabase/functions/price-comp/__tests__/index.test.ts` — assert echo.

---

## Task 1: Config value for the impact base URL

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Config/AppEnvironment.swift`

- [ ] **Step 1: Add the config accessor**

In `AppEnvironment`, immediately after the `epnCustomID` block (the `private static func lookup` must remain the last member), insert:

```swift
    /// impact.com base tracking URL for the TCGplayer campaign,
    /// "https://partner.tcgplayer.com/c/{account}/{ad}/{campaign}". The app
    /// appends `?subId1=<surface>&u=<encoded product url>` per card. Affiliate
    /// links are public (embedded in every outbound tap), so the account's
    /// live tracking link is baked in as the default — the buttons monetize
    /// with zero setup. Override via `TCGPLAYER_IMPACT_BASE_URL` (e.g. campaign
    /// rotation). An empty value makes `TCGPlayerAffiliateLink` open raw
    /// tcgplayer.com links instead.
    static let tcgplayerImpactBaseURL: String = {
        if let value = lookup("TCGPLAYER_IMPACT_BASE_URL") { return value }
        return "https://partner.tcgplayer.com/c/6098165/1830156/21018"
    }()
```

- [ ] **Step 2: Document the override var**

In `ios/slabbist/Config/Secrets.xcconfig.example`, after the `EPN_CUSTOM_ID` line, add:

```
// TCGplayer impact.com tracking link — public affiliate value. Optional:
// AppEnvironment already defaults to the live link; set this only to override
// (e.g. a rotated campaign). Format: https://partner.tcgplayer.com/c/{a}/{ad}/{c}
// TCGPLAYER_IMPACT_BASE_URL = https://partner.tcgplayer.com/c/6098165/1830156/21018
```

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Core/Config/AppEnvironment.swift ios/slabbist/Config/Secrets.xcconfig.example
git commit -m "feat(ios): add TCGPLAYER_IMPACT_BASE_URL config with baked-in default"
```

---

## Task 2: `TCGPlayerAffiliateLink` helper (TDD)

**Files:**
- Create: `ios/slabbist/slabbist/Core/Utilities/TCGPlayerAffiliateLink.swift`
- Test: `ios/slabbist/slabbistTests/Core/TCGPlayerAffiliateLinkTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/slabbist/slabbistTests/Core/TCGPlayerAffiliateLinkTests.swift`:

```swift
import Foundation
import Testing
@testable import slabbist

@Suite("TCGPlayerAffiliateLink")
struct TCGPlayerAffiliateLinkTests {
    let base = "https://partner.tcgplayer.com/c/6098165/1830156/21018"

    @Test("wraps product id as percent-encoded u= with subId1 surface tag")
    func wraps() throws {
        let url = try #require(
            TCGPlayerAffiliateLink.link(productId: 517812, subId: "graded", baseURL: base)
        )
        #expect(url.absoluteString ==
            "https://partner.tcgplayer.com/c/6098165/1830156/21018?subId1=graded&u=https%3A%2F%2Fwww.tcgplayer.com%2Fproduct%2F517812")
    }

    @Test("empty base URL falls back to the raw tcgplayer.com product URL")
    func rawFallback() throws {
        let url = try #require(
            TCGPlayerAffiliateLink.link(productId: 517812, subId: "mover", baseURL: "")
        )
        #expect(url.absoluteString == "https://www.tcgplayer.com/product/517812")
    }

    @Test("non-positive product id returns nil so the button hides")
    func guardsProductId() {
        #expect(TCGPlayerAffiliateLink.link(productId: 0, subId: "graded", baseURL: base) == nil)
        #expect(TCGPlayerAffiliateLink.link(productId: -5, subId: "graded", baseURL: base) == nil)
    }
}
```

These tests encode intent: the wrapping must produce the exact impact deep link the affiliate program expects (verified to resolve to a product page), the helper must degrade gracefully when unconfigured, and it must never emit a meaningless `/product/0` link.

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd ios/slabbist && xcodebuild test -project slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:slabbistTests/TCGPlayerAffiliateLinkTests 2>&1 | tail -20
```
Expected: FAIL — `cannot find 'TCGPlayerAffiliateLink' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `ios/slabbist/slabbist/Core/Utilities/TCGPlayerAffiliateLink.swift`:

```swift
import Foundation

/// Builds an impact.com affiliate deep link to a TCGplayer product page so
/// Slabbist earns commission on resulting sales. Mirrors `EbayAffiliateLink`.
///
/// The destination is always `https://www.tcgplayer.com/product/{id}`. When an
/// impact base tracking URL is configured (the `AppEnvironment` default, or a
/// `TCGPLAYER_IMPACT_BASE_URL` override) the destination is percent-encoded
/// into that link's `u=` parameter, with the originating surface in `subId1`
/// for impact-side click reporting. When no base URL is configured the raw
/// tcgplayer.com URL is returned so the button still works (un-attributed) —
/// the same graceful fallback as the eBay integration's missing-campaign path.
///
/// `baseURL` is injectable so tests are deterministic regardless of the build's
/// resolved config; production call sites omit it.
enum TCGPlayerAffiliateLink {
    static func link(
        productId: Int,
        subId: String,
        baseURL: String = AppEnvironment.tcgplayerImpactBaseURL
    ) -> URL? {
        guard productId > 0 else { return nil }
        let destination = "https://www.tcgplayer.com/product/\(productId)"
        guard !baseURL.isEmpty else { return URL(string: destination) }

        // RFC 3986 unreserved set — encodes ":" and "/" so the destination is a
        // valid single query value (URLComponents would leave them bare).
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: unreserved) ?? destination
        return URL(string: "\(baseURL)?subId1=\(subId)&u=\(encoded)")
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd ios/slabbist && xcodebuild test -project slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:slabbistTests/TCGPlayerAffiliateLinkTests 2>&1 | tail -20
```
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Utilities/TCGPlayerAffiliateLink.swift \
        ios/slabbist/slabbistTests/Core/TCGPlayerAffiliateLinkTests.swift
git commit -m "feat(ios): TCGPlayerAffiliateLink impact deep-link builder + tests"
```

---

## Task 3: Shared `TCGPlayerLinkButton` view

**Files:**
- Create: `ios/slabbist/slabbist/Core/DesignSystem/Components/TCGPlayerLinkButton.swift`

Invoke `swiftui-expert-skill` and apply its rules while writing this view.

- [ ] **Step 1: Create the button**

Create `ios/slabbist/slabbist/Core/DesignSystem/Components/TCGPlayerLinkButton.swift`:

```swift
import SwiftUI

/// "View on TCGplayer" affiliate button shown on card-detail surfaces. Renders
/// nothing when no link can be built (non-positive product id), so callers can
/// place it unconditionally. `subId` is the originating surface
/// ("graded" | "mover" | "gradegain"), recorded as impact's subId1.
struct TCGPlayerLinkButton: View {
    let productId: Int
    let subId: String

    var body: some View {
        if let url = TCGPlayerAffiliateLink.link(productId: productId, subId: subId) {
            Link(destination: url) {
                HStack(spacing: Spacing.xs) {
                    Text("View on TCGplayer")
                    Image(systemName: "arrow.up.right")
                        .font(SlabFont.sans(size: 13, weight: .semibold))
                }
            }
            .buttonStyle(TCGPlayerLinkButtonStyle())
            .accessibilityLabel("View on TCGplayer")
            .accessibilityHint("Opens this card's page on TCGplayer")
        }
    }
}

/// Gold-outlined CTA — distinct from the muted `SecondaryButtonStyle` so the
/// affiliate action reads as a deliberate call to action, while staying within
/// the dark+gold system and meeting the 44pt touch target / AA contrast.
private struct TCGPlayerLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SlabFont.sans(size: 15, weight: .semibold))
            .foregroundStyle(AppColor.gold)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .stroke(AppColor.gold, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

#Preview("TCGPlayerLinkButton") {
    VStack(spacing: Spacing.l) {
        TCGPlayerLinkButton(productId: 517812, subId: "graded")
        TCGPlayerLinkButton(productId: 0, subId: "graded") // renders nothing
    }
    .padding()
    .background(AppColor.ink)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd ios/slabbist && xcodebuild build -project slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Core/DesignSystem/Components/TCGPlayerLinkButton.swift
git commit -m "feat(ios): shared TCGPlayerLinkButton (gold CTA, hides when no link)"
```

---

## Task 4: Button on the Mover detail screen

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Movers/MoverDetailView.swift:22`

- [ ] **Step 1: Insert the button in the body stack**

In `MoverDetailView.body`, the main `VStack` (currently lines 18–24) reads:

```swift
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    hero
                    statsCard
                    historyCard
                    listingsSection
                    Spacer(minLength: Spacing.xxxl)
                }
```

Change it to add the button after `listingsSection`:

```swift
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    hero
                    statsCard
                    historyCard
                    listingsSection
                    TCGPlayerLinkButton(productId: viewModel.mover.productId, subId: "mover")
                    Spacer(minLength: Spacing.xxxl)
                }
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd ios/slabbist && xcodebuild build -project slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/Movers/MoverDetailView.swift
git commit -m "feat(ios): View on TCGplayer button on mover detail"
```

---

## Task 5: Button on the Grade Gain detail screen

**Files:**
- Modify: `ios/slabbist/slabbist/Features/GradeGains/GradeGainDetailView.swift:35`

- [ ] **Step 1: Insert the button in the body stack**

In `GradeGainDetailView.body`, the main `VStack` (currently lines 32–37) reads:

```swift
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    hero
                    breakdownCard
                    historyCard
                    Spacer(minLength: Spacing.xxxl)
                }
```

Change it to add the button after `historyCard`:

```swift
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    hero
                    breakdownCard
                    historyCard
                    TCGPlayerLinkButton(productId: gain.productId, subId: "gradegain")
                    Spacer(minLength: Spacing.xxxl)
                }
```

(`gain` is the `GradeGainDTO` property on the view; `gain.productId` is already used at `GradeGainDetailView.swift:281`.)

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd ios/slabbist && xcodebuild build -project slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/GradeGains/GradeGainDetailView.swift
git commit -m "feat(ios): View on TCGplayer button on grade-gain detail"
```

---

## Task 6: Echo `tcgplayer_product_id` from `price-comp` (TDD)

**Files:**
- Modify: `supabase/functions/price-comp/types.ts:81-90`
- Modify: `supabase/functions/price-comp/index.ts` (`blockToResponse` + its two call sites)
- Test: `supabase/functions/price-comp/__tests__/index.test.ts`

- [ ] **Step 1: Write the failing test assertions**

In `__tests__/index.test.ts`, test "(b) cache-hit…" builds its identity as
`const identity = { ...baseIdentity, poketrace_card_id: "pt-uuid-1" };`. Change
that line to set a product id:

```javascript
  const identity = { ...baseIdentity, poketrace_card_id: "pt-uuid-1", tcgplayer_product_id: "517812" };
```

Then, in that test's assertion block (right after `assertEquals(body.cache_hit, true);`), add:

```javascript
    assertEquals(body.tcgplayer_product_id, "517812");
```

In test "(c) cold path…" (whose identity uses the default `baseIdentity`, where
`tcgplayer_product_id` is `null`), after `assertEquals(body.cache_hit, false);` add:

```javascript
    assertEquals(body.tcgplayer_product_id, null);
```

These pin the contract: the field is echoed when present (cache-hit path) and is
explicitly `null` rather than missing when the identity has no mapping (cold path).

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
cd supabase/functions/price-comp && deno test --allow-all __tests__/index.test.ts 2>&1 | tail -25
```
Expected: FAIL — both new `assertEquals` fail because `body.tcgplayer_product_id` is `undefined`.

- [ ] **Step 3: Add the field to the response type**

In `types.ts`, the `PriceCompResponse` interface (lines 81–90) — add the field
after `marketplace_url`:

```typescript
export interface PriceCompResponse {
  grading_service: GradingService;
  grade: string;
  headline_price_cents: number | null;   // = poketrace avg
  poketrace: PoketraceBlock | null;       // null when no graded tier data
  sold_listings: SoldListingWire[];       // [] off the Scale plan
  marketplace_url: string | null;         // ebay sold-results deep link
  tcgplayer_product_id: string | null;    // raw-single id for the affiliate link
  fetched_at: string;
  cache_hit: boolean;
}
```

- [ ] **Step 4: Thread the value through `blockToResponse`**

In `index.ts`, change `blockToResponse` (lines 46–64) to accept and emit the id:

```typescript
function blockToResponse(
  service: GradingService,
  grade: string,
  block: PoketraceBlock | null,
  soldListings: PriceCompResponse["sold_listings"],
  marketplaceUrl: string | null,
  cacheHit: boolean,
  tcgplayerProductId: string | null,
): PriceCompResponse {
  return {
    grading_service: service,
    grade,
    headline_price_cents: block?.avg_cents ?? null,
    poketrace: block,
    sold_listings: soldListings,
    marketplace_url: marketplaceUrl,
    tcgplayer_product_id: tcgplayerProductId,
    fetched_at: new Date().toISOString(),
    cache_hit: cacheHit,
  };
}
```

- [ ] **Step 5: Pass the id at both call sites**

`blockToResponse` is called twice; `identity` is in scope at both. Add the
argument `identity.tcgplayer_product_id ?? null` to each.

Cache-hit path (currently `blockToResponse(body.grading_service, body.grade, block, sold, null, true)`):

```typescript
    return json(
      200,
      blockToResponse(
        body.grading_service, body.grade, block, sold, null, true,
        identity.tcgplayer_product_id ?? null,
      ),
    );
```

Final cold path (currently `blockToResponse(body.grading_service, body.grade, block, sold, null, false)`):

```typescript
  return json(
    200,
    blockToResponse(
      body.grading_service, body.grade, block, sold, null, false,
      identity.tcgplayer_product_id ?? null,
    ),
  );
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
cd supabase/functions/price-comp && deno test --allow-all __tests__/index.test.ts 2>&1 | tail -25
```
Expected: PASS — all tests, including the two new assertions.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/price-comp/types.ts supabase/functions/price-comp/index.ts \
        supabase/functions/price-comp/__tests__/index.test.ts
git commit -m "feat(price-comp): echo tcgplayer_product_id for affiliate links"
```

- [ ] **Step 8: Deploy the Edge Function**

```bash
supabase functions deploy price-comp
```
Expected: deploy succeeds. (Required before the iOS live round-trip in Task 9.)

---

## Task 7: Decode `tcgplayer_product_id` in `CompRepository` (TDD)

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Data/Repositories/CompRepository.swift`
- Test: `ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift`

- [ ] **Step 1: Write the failing test**

In `CompRepositoryTests.swift`, add a test. It decodes a minimal v3 payload that
carries `tcgplayer_product_id` as a JSON string and asserts it lands as an `Int`,
plus a payload omitting the field decodes to `nil` (back-compat):

```swift
    @Test("decodes tcgplayer_product_id string into Int; absent → nil")
    func decodesTcgplayerProductId() throws {
        let withId = #"""
        {
          "grading_service": "PSA", "grade": "10",
          "headline_price_cents": null, "poketrace": null,
          "sold_listings": [], "marketplace_url": null,
          "tcgplayer_product_id": "517812",
          "fetched_at": "2026-06-04T00:00:00Z", "cache_hit": false
        }
        """#
        let a = try CompRepository.decode(data: Data(withId.utf8))
        #expect(a.tcgplayerProductId == 517812)

        let withoutId = #"""
        {
          "grading_service": "PSA", "grade": "10",
          "headline_price_cents": null, "poketrace": null,
          "sold_listings": [], "marketplace_url": null,
          "fetched_at": "2026-06-04T00:00:00Z", "cache_hit": false
        }
        """#
        let b = try CompRepository.decode(data: Data(withoutId.utf8))
        #expect(b.tcgplayerProductId == nil)
    }
```

This guards the wire contract on the consumer side: the server sends a string id,
the app needs an `Int` for the product URL, and older responses without the field
must still decode (so a deploy-order mismatch can't crash the comp screen).

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd ios/slabbist && xcodebuild test -project slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:slabbistTests/CompRepositoryTests/decodesTcgplayerProductId 2>&1 | tail -20
```
Expected: FAIL — `value of type 'CompRepository.Decoded' has no member 'tcgplayerProductId'`.

- [ ] **Step 3: Add the field to `Wire`, `Decoded`, and `decode`**

In `CompRepository.swift`:

(a) In `struct Wire` (after `let marketplace_url: String?`, line 23):
```swift
        let tcgplayer_product_id: String?
```

(b) In `struct Decoded` (after `let marketplaceURL: URL?`, line 68):
```swift
        let tcgplayerProductId: Int?
```

(c) In `decode(data:)`, the `return Decoded(...)` (lines 146–155) — add the
mapping after `marketplaceURL:`:
```swift
        return Decoded(
            gradingService: wire.grading_service,
            grade: wire.grade,
            headlinePriceCents: wire.headline_price_cents,
            poketrace: poketrace,
            soldListings: soldListings,
            marketplaceURL: wire.marketplace_url.flatMap(URL.init(string:)),
            tcgplayerProductId: wire.tcgplayer_product_id.flatMap { Int($0) },
            fetchedAt: wire.fetched_at,
            cacheHit: wire.cache_hit
        )
```

Because `Wire.tcgplayer_product_id` is `String?` (optional), a payload omitting
the key decodes to `nil` — no `keyNotFound` error, preserving back-compat.

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd ios/slabbist && xcodebuild test -project slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:slabbistTests/CompRepositoryTests 2>&1 | tail -20
```
Expected: PASS — the whole `CompRepository` suite, including the new test.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Data/Repositories/CompRepository.swift \
        ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift
git commit -m "feat(ios): decode tcgplayer_product_id in CompRepository"
```

---

## Task 8: Persist + render the button on the graded comp screen

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift`
- Modify: `ios/slabbist/slabbist/Features/Comp/CompFetchService.swift:309-356`
- Modify: `ios/slabbist/slabbist/Features/Comp/CompCardView.swift:44-52`

`CompCardView` renders only from the persisted `GradedMarketSnapshot`, so the id
must be stored to appear. A plain `Int?` is the migration-safe kind of field
addition (the model's caveats concern Codable array/dict blobs and column
removal, not primitive optionals).

- [ ] **Step 1: Add the stored property to the model**

In `GradedMarketSnapshot.swift`, add the property after `poketraceCardId` (the
field declared around line 35):

```swift
    /// TCGplayer product id for the raw single backing this slab's identity,
    /// echoed from `price-comp`. Drives the "View on TCGplayer" affiliate
    /// button on the comp card. Nil when the identity has no TCGplayer mapping.
    var tcgplayerProductId: Int?
```

- [ ] **Step 2: Add the init parameter and assignment**

In the same file's `init(...)`, add an init parameter (place it after
`poketraceCardId: String? = nil` in the signature):

```swift
        poketraceCardId: String? = nil,
        tcgplayerProductId: Int? = nil,
```

and the matching assignment in the init body (next to `self.poketraceCardId = poketraceCardId`):

```swift
        self.tcgplayerProductId = tcgplayerProductId
```

The default `= nil` keeps existing call sites (the two `#Preview` snapshots in
`CompCardView.swift:438,481`) compiling untouched.

- [ ] **Step 3: Pass the id when persisting**

In `CompFetchService.swift`, `persistSnapshots(...)` builds two snapshots.

Full snapshot (the `if let pt = decoded.poketrace` branch, lines 313–338) — add
after `poketraceCardId: pt.cardId,` (line 331):
```swift
                poketraceCardId: pt.cardId,
                tcgplayerProductId: decoded.tcgplayerProductId,
```

Minimal snapshot (the `else if !decoded.soldListings.isEmpty` branch, lines
343–354) — add after `headlinePriceCents: nil,` (line 348):
```swift
                headlinePriceCents: nil,
                tcgplayerProductId: decoded.tcgplayerProductId,
```

- [ ] **Step 4: Render the button in `CompCardView`**

In `CompCardView.body`, the section after `CompSoldListingsView` and before the
final `footerRow` (lines 45–53) currently reads:

```swift
                CompSoldListingsView(
                    soldListings: snapshot?.soldListings ?? [],
                    marketplaceURL: snapshot?.marketplaceURL
                )
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
                SlabCardDivider()
                footerRow
```

Insert the gated button between the sold-listings block and the divider before
`footerRow`:

```swift
                CompSoldListingsView(
                    soldListings: snapshot?.soldListings ?? [],
                    marketplaceURL: snapshot?.marketplaceURL
                )
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
                if let pid = snapshot?.tcgplayerProductId {
                    SlabCardDivider()
                    TCGPlayerLinkButton(productId: pid, subId: "graded")
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                SlabCardDivider()
                footerRow
```

Existing `CompCardViewSnapshotTests` fixtures leave `tcgplayerProductId` nil, so
the button is absent and those snapshots are unchanged.

- [ ] **Step 5: Build and run the comp test suites**

Run:
```bash
cd ios/slabbist && xcodebuild test -project slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:slabbistTests/CompFetchServiceTests \
  -only-testing:slabbistTests/CompCardViewSnapshotTests 2>&1 | tail -25
```
Expected: PASS — persistence and snapshot suites green (snapshots unchanged: nil id ⇒ no button).

- [ ] **Step 6: Commit**

```bash
git add ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift \
        ios/slabbist/slabbist/Features/Comp/CompFetchService.swift \
        ios/slabbist/slabbist/Features/Comp/CompCardView.swift
git commit -m "feat(ios): persist + render TCGplayer button on graded comp card"
```

---

## Task 9: Full verification (build, suites, live round-trip, simulator)

**Files:** none (verification only).

- [ ] **Step 1: Full iOS test suite**

Run:
```bash
cd ios/slabbist && xcodebuild test -project slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **`, 0 failures. If any fail, fix before proceeding — do not claim done with a red suite.

- [ ] **Step 2: Full price-comp Deno suite**

Run:
```bash
cd supabase/functions/price-comp && deno test --allow-all 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 3: Live decode round-trip (CLAUDE.md Rule 6 / memory)**

Against the deployed `price-comp` (Task 6 Step 8), fetch a real comp for a graded
identity known to have a `tcgplayer_product_id`, and confirm the field is present
and decodes. Using the simulator/app: open a scan whose identity has a TCGplayer
mapping, trigger a comp fetch, and confirm in logs/UI that the button appears.
Alternatively, curl the function with a valid bearer token and a real
`graded_card_identity_id` and confirm `tcgplayer_product_id` is in the JSON, then
confirm `CompRepository.decode` consumes that exact body (the Task 7 test already
locks the shape). Note explicitly if no mapped identity exists to test against.

- [ ] **Step 4: Simulator visual check on all three surfaces**

Launch the app and verify the gold "View on TCGplayer" button:
- Mover detail → tapping opens `partner.tcgplayer.com/...u=...product/{id}` and lands on the product page.
- Grade Gain detail → same.
- Graded comp (ScanDetailView) → button appears for a card with a mapped product id; **absent** for one without.

Confirm `subId1` differs per surface by inspecting the opened URL.

- [ ] **Step 5: Final commit (if any verification fixes were made)**

```bash
git add -A && git commit -m "test(ios): verify TCGplayer affiliate links across surfaces"
```

---

## Notes for the implementer

- **Deploy ordering:** Task 6 Step 8 deploys `price-comp` before the iOS live
  round-trip. The iOS decode is back-compatible (absent field → nil), so app
  builds running against an un-deployed function simply show no graded button —
  no crash.
- **The affiliate id is not a secret.** It is baked into `AppEnvironment` as the
  default on purpose; `TCGPLAYER_IMPACT_BASE_URL` overrides it. Do not move it to
  a gitignored-only secret — that would silently disable monetization in every
  build that forgets to set it.
- **Raw-vs-graded caveat (accepted in the spec):** on the graded comp card the
  link targets the raw single, not the slab. Copy says "View", not "Buy".
