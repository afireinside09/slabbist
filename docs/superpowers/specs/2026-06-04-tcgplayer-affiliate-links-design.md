# TCGplayer Affiliate Links on Card Detail Pages

**Date:** 2026-06-04
**Status:** Approved design, pre-implementation
**Worktree/branch:** `worktree-tcgplayer-affiliate-links` (off `origin/main`)

## Goal

Every card detail surface gains a "View on TCGplayer" button that opens the
card's TCGplayer product page through Slabbist's impact.com affiliate link, so
Slabbist earns commission on resulting purchases.

## Background: how impact.com affiliate links work

impact.com does **not** require a separate registered link per card. Once the
account is approved for the TCGplayer campaign, the dashboard's **Get Tracking
Link** (Ads → the TCGplayer "API Link" / Text Link) yields **one** base
tracking URL on TCGplayer's vanity domain, of the form
`https://partner.tcgplayer.com/c/{accountId}/{adId}/{campaignId}`. The account's
actual value is:

```
https://partner.tcgplayer.com/c/6098165/1830156/21018
```

The dashboard's separate **Vanity Links** screen (short links like
`partner.tcgplayer.com/zzN6BM`) is NOT used — each is bound to one fixed landing
page. Leave the tracking link's "Landing Page (Optional)" field blank; the app
supplies the destination per card via `u=`.

Any specific product is reached by appending a percent-encoded destination in
the `u=` parameter (and the surface tag in `subId1`):

```
https://partner.tcgplayer.com/c/6098165/1830156/21018?subId1=graded&u=https%3A%2F%2Fwww.tcgplayer.com%2Fproduct%2F517812
```

The IDs are constant; only the `u=` value changes per card. The link can be
built entirely client-side — no impact.com API call is needed (confirmed by
impact.com docs: *"If you already have the full tracking URL for the ad, you
can create the deep link without logging into impact.com."*). `tcgplayer.com`
is an allowed destination domain by default since it is TCGplayer's own
program. Optional `subId1`/`subId2` params carry partner-side reporting tags.

This mirrors the existing eBay Partner Network integration
(`Core/Utilities/EbayAffiliateLink.swift`), which wraps raw eBay URLs with EPN
query params read from config.

## Surfaces in scope

| Surface | View | Product id source | Server work? |
|---|---|---|---|
| Graded slab comp | `Features/Comp/CompCardView.swift` (inside `ScanDetailView`) | `price-comp` response (new field) | Yes — echo `tcgplayer_product_id` |
| Mover detail (raw card) | `Features/Movers/MoverDetailView.swift` | `mover.productId` (already on-device) | No |
| Grade Gain detail (raw card) | `Features/GradeGains/GradeGainDetailView.swift` | grade-gain model `productId` (already on-device) | No |

**Caveat on the graded surface:** `tcgplayer_product_id` maps to the *raw
single*, not the graded slab, so "View on TCGplayer" on a PSA 10 comp opens the
ungraded card's product page. Accepted: the copy says "View", not "Buy", and
raw market context is useful for a buy-side comp. No grade-specific TCGplayer
product exists to link instead.

## Design

### 1. `Core/Utilities/TCGPlayerAffiliateLink.swift` (new)

Mirrors `EbayAffiliateLink`. Pure, `nonisolated`, no I/O.

```
enum TCGPlayerAffiliateLink {
    /// Wrap a TCGplayer product id in the impact affiliate deep link.
    /// Returns the raw tcgplayer.com product URL (un-attributed) when no
    /// impact base URL is configured, so the button always works.
    /// Returns nil only for a non-positive product id.
    static func link(productId: Int, subId: String) -> URL?
}
```

Behavior:
- Guard `productId > 0` → else `nil`.
- Destination = `https://www.tcgplayer.com/product/{productId}`.
- If `AppEnvironment.tcgplayerImpactBaseURL` is empty → return the destination
  URL unchanged (raw fallback — same philosophy as eBay's missing-campaign
  fallback). **[Decided: show button + raw link when unconfigured.]**
- Else parse the base URL, append query items `subId1={subId}` and
  `u={destination}`. `URLComponents` percent-encodes the `u` value correctly.

`subId` is the surface name: `"graded"`, `"mover"`, or `"gradegain"`, so impact
reports attribute clicks by screen.

### 2. Config — `Core/Config/AppEnvironment.swift`

Add, following the `epnCustomID` pattern (real default, env-overridable).
Affiliate tracking links are public (embedded in every outbound tap), so the
account's tracking link is baked in as the default — buttons monetize with zero
setup. `TCGPLAYER_IMPACT_BASE_URL` overrides it (e.g. campaign rotation); an
explicitly empty value falls back to raw tcgplayer.com links.

```
/// impact.com base tracking URL for the TCGplayer campaign,
/// "https://partner.tcgplayer.com/c/{account}/{ad}/{campaign}". The app
/// appends ?subId1=<surface>&u=<encoded product url> per card. Defaults to
/// the account's live tracking link; override via env for campaign rotation.
static let tcgplayerImpactBaseURL: String = {
    if let value = lookup("TCGPLAYER_IMPACT_BASE_URL") { return value }
    return "https://partner.tcgplayer.com/c/6098165/1830156/21018"
}()
```

Note: `lookup` returns nil only when the var is unset/empty, so an explicitly
empty env value cannot reach here — to force the raw fallback in a build, the
config simply uses a value the wrapper treats as "no base" (handled in
`TCGPlayerAffiliateLink`, which checks for a parseable `/c/` tracking URL).
Document `TCGPLAYER_IMPACT_BASE_URL` in
`ios/slabbist/Config/Secrets.xcconfig.example` and `.envrc` as an optional
override (commented; the default already carries the live link).

### 3. Server plumbing (graded surface only)

`supabase/functions/price-comp/`:
- `types.ts`: add `tcgplayer_product_id: string | null` to `PriceCompResponse`.
- `index.ts`: set it from the already-loaded `identity.tcgplayer_product_id`
  (one line — the identity is fetched today, the value is simply not returned).

iOS `Core/Data/Repositories/CompRepository.swift`:
- Add `tcgplayer_product_id: Int?` to `Wire` (decode the string id to Int; it is
  a numeric TCGplayer product id) — note source is a JSON string, so decode as
  `String?` then `Int(...)`, OR change server to emit a number. **Decision:
  server emits the raw column value (string); iOS decodes `String?` and converts
  to `Int?`** to avoid changing the column's wire type elsewhere.
- Add `tcgplayerProductId: Int?` to `Decoded`.
- Persist into the comp snapshot model (`GradedMarketSnapshot`) so the button
  works offline from cached comps.

Per CLAUDE.md Rule 6 and the "live decode round-trip" memory: before declaring
done, fire the real deployed `price-comp` and confirm the new field decodes into
`Decoded` — curl alone does not catch shape mismatches.

### 4. UI — shared button view

A small reusable SwiftUI view (e.g. `Features/Comp/TCGPlayerLinkButton.swift`
or a shared `Core/UI` location matching codebase convention):

```
TCGPlayerLinkButton(productId: Int, subId: String)
```

- Renders `Link(destination:)` → label "View on TCGplayer".
- Styled per `.impeccable.md`: dark + gold OKLCH palette, Inter Tight / SF type,
  4pt spacing, 14/18 radii, WCAG 2.2 AA contrast and ≥44pt touch target.
- Renders nothing if `TCGPlayerAffiliateLink.link(...)` returns `nil`.

Placement:
- **Graded:** inside `CompCardView`, below the sold-listings section. Shown only
  when the decoded comp carries a non-nil `tcgplayerProductId`. `subId: "graded"`.
- **Mover:** in `MoverDetailView`, near the existing eBay listings affordance.
  `subId: "mover"`, `productId: mover.productId`.
- **Grade Gain:** in `GradeGainDetailView`. `subId: "gradegain"`.

SwiftUI work invokes `swiftui-expert-skill` per project convention.

### 5. Tests

- `TCGPlayerAffiliateLinkTests` (unit, intent-encoding):
  - With a base URL configured → output host is the impact vanity domain, `u=`
    is the percent-encoded `https://www.tcgplayer.com/product/{id}`, and
    `subId1` equals the passed surface tag. (Fails if wrapping logic regresses.)
  - With empty base URL → output equals the raw tcgplayer.com product URL.
  - `productId <= 0` → `nil`.
- `CompRepository` decode test: a `price-comp` fixture including
  `tcgplayer_product_id` round-trips into `Decoded.tcgplayerProductId`; a fixture
  omitting it decodes to `nil` (back-compat with pre-field responses).

## Out of scope

- No impact.com API integration — links are pure string construction from one
  config value.
- No backfill of `graded_card_identities.tcgplayer_product_id`; on graded cards
  lacking a mapping the button simply does not render.
- No new analytics beyond the `subId1` surface tag impact records server-side.
- Marketing/dashboard surfaces — iOS only.

## Verification criteria

1. `TCGPlayerAffiliateLink` unit tests pass (wrapping, raw fallback, guard).
2. `CompRepository` decode test passes (field present + absent).
3. Live `price-comp` round-trip returns and decodes `tcgplayer_product_id`.
4. Button appears and opens the correct affiliate URL on all three surfaces in
   a simulator run; hidden on graded cards with no mapped product id.
5. Existing iOS test suite stays green.
