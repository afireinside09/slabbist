# PriceCharting Comp — Design Spec

**Sub-project:** #4 (Comp engine v1) — replatform
**Date:** 2026-05-05
**Status:** Design approved; awaiting implementation plan
**Supersedes:** [`2026-04-23-ebay-sold-listings-comp-design.md`](./2026-04-23-ebay-sold-listings-comp-design.md) for the scan-time comp path

## Summary

Replaces the eBay-backed `/price-comp` Edge Function with a PriceCharting-backed equivalent. When a scan validates and the iOS app requests a comp, the Edge Function resolves the slab to a PriceCharting product (cached or live-searched), fetches the product's full per-grade price ladder, and returns a headline price plus the ladder for the iOS detail screen. eBay OAuth, Marketplace Insights cascade, sold-listing mirroring, the per-listing UI, the confidence/sample/velocity surface, and the watchlist-promotion event stream all go away from this code path. The Movers/eBay-listings feature is unaffected.

## Goals

1. A scan of any graded Pokémon card returns a defensible comp in one round-trip using PriceCharting as the source of truth.
2. The iOS-facing endpoint URL (`/price-comp`) and outbox kind stay the same so most app-side wiring is reused.
3. Per-tier prices (Ungraded, 7, 8, 9, 9.5, PSA 10, BGS 10, CGC 10, SGC 10) are exposed to iOS so the detail screen can show a grade ladder useful for crack-and-resub decisions.
4. A real-listings escape hatch — every comp deep-links to its PriceCharting product page so users can verify against actual sales when they need to.
5. First-scan latency is amortized by caching the resolved PriceCharting product id on the identity row (one search per identity, ever).
6. eBay scaffolding that only existed for the comp path is removed cleanly; eBay surfaces that serve other features (Movers, account-deletion webhook) are untouched.

## Non-goals

- Replacing or extending the Movers / eBay-listings tab (separate feature, separate eBay credentials).
- Per-listing sold-comps with confidence scores, MAD outlier detection, sample-window tuning, or velocity counters — none of these have a PriceCharting equivalent in v1.
- Pre-warming PriceCharting prices via the scraper. Reserved as a follow-up optimization for popular identities; v1 is on-demand.
- A "force-rematch" UX for correcting a wrong cached `pricecharting_product_id`. Surfaced as a follow-up.
- Cross-grader arbitrage views beyond the basic ladder rail — UI affordance only, no analytics.
- Non-Pokémon catalogs.
- Sandbox / dev PriceCharting environment wiring — production only for MVP.

## Architecture

```
iOS  ──────►  /price-comp (Edge Function, Deno)
                 │
                 ├─ load graded_card_identity (validates existence)
                 │
                 ├─ resolve PriceCharting product id (HYBRID)
                 │     ├─ identity.pricecharting_product_id present? → use it
                 │     └─ else: GET /api/products?q=<built query>
                 │             → take top hit, persist id back on identity
                 │             → if zero hits: 404 PRODUCT_NOT_RESOLVED
                 │
                 ├─ read graded_market for (identity, grader, grade)
                 │     ├─ row + updated_at within TTL → return cached
                 │     └─ stale or miss → live fetch
                 │
                 ├─ LIVE: GET /api/product?t=<token>&id=<pc_product_id>
                 │     ├─ extract per-grade prices
                 │         (loose, 7, 8, 9, 9.5, psa-10, bgs-10, cgc-10, sgc-10)
                 │     ├─ pick headline from (grading_service, grade) → tier price
                 │     └─ upsert graded_market with the full ladder
                 │
                 └─ return payload (headline + ladder + deep-link URL + cache flags)
```

### Boundaries

- iOS never calls PriceCharting directly. The two-endpoint contract from the parent comp spec (`/cert-lookup`, `/price-comp`) holds.
- PriceCharting access is server-only via `PRICECHARTING_API_TOKEN`. Token rotation is a Supabase secret rotation, not a redeploy.
- Live fetch writes only to `graded_market` and the new `graded_card_identities.pricecharting_product_id` column with the service-role client. No new tables.

## Data model

### Migration: `pricecharting_product_id` on identities

```sql
alter table public.graded_card_identities
  add column if not exists pricecharting_product_id text;

create index if not exists graded_card_identities_pc_product_idx
  on public.graded_card_identities (pricecharting_product_id)
  where pricecharting_product_id is not null;
```

Nullable. Persisted once after the first successful match; subsequent scans skip search. No backfill required — existing rows get an id on first scan.

### Migration: `graded_market` reshape

Drops the eBay-specific aggregate columns added in `20260424000001_ebay_comp_columns_and_scan_events.sql` and earlier:

```sql
alter table public.graded_market
  drop column if exists mean_price,
  drop column if exists trimmed_mean_price,
  drop column if exists sample_window_days,
  drop column if exists confidence,
  drop column if exists velocity_7d,
  drop column if exists velocity_30d,
  drop column if exists velocity_90d,
  drop column if exists sample_count_30d,
  drop column if exists sample_count_90d;

alter table public.graded_market
  add column if not exists source                   text,
  add column if not exists pricecharting_product_id text,
  add column if not exists pricecharting_url        text,
  add column if not exists loose_price              numeric(12,2),
  add column if not exists grade_7_price            numeric(12,2),
  add column if not exists grade_8_price            numeric(12,2),
  add column if not exists grade_9_price            numeric(12,2),
  add column if not exists grade_9_5_price          numeric(12,2),
  add column if not exists psa_10_price             numeric(12,2),
  add column if not exists bgs_10_price             numeric(12,2),
  add column if not exists cgc_10_price             numeric(12,2),
  add column if not exists sgc_10_price             numeric(12,2);

update public.graded_market set source = 'pricecharting' where source is null;
alter table public.graded_market alter column source set not null;
alter table public.graded_market alter column source set default 'pricecharting';
```

The implementation plan must verify whether any non-comp consumer reads `low_price` / `median_price` / `high_price` (currently set by tcgcsv, then overwritten by the eBay path). If nothing else reads them, drop in this migration as well; if a consumer remains, leave them and have the new code write `low_price = high_price = median_price = headline_price`. Default is to drop.

### Migration: drop `graded_market_sales`

```sql
drop table if exists public.graded_market_sales cascade;
```

PriceCharting does not return per-listing rows. No other writer remains.

### Migration: drop `slab_scan_events`

```sql
drop table if exists public.slab_scan_events cascade;
```

The eBay-scraper watchlist promotion signal has no consumer once the eBay comp path is gone. Per scope decision, the table is dropped rather than left orphaned.

### iOS SwiftData

`GradedMarketSnapshot` reshape:

- Remove: `meanPriceCents`, `trimmedMeanPriceCents`, `medianPriceCents`, `lowPriceCents`, `highPriceCents`, `confidence`, `sampleCount`, `sampleWindowDays`, `velocity7d`, `velocity30d`, `velocity90d`, `soldListings` relationship.
- Add: `headlinePriceCents` (Int64?), `loosePriceCents`, `grade7PriceCents`, `grade8PriceCents`, `grade9PriceCents`, `grade9_5PriceCents`, `psa10PriceCents`, `bgs10PriceCents`, `cgc10PriceCents`, `sgc10PriceCents` (all Int64?), `pricechartingURL` (URL?), `pricechartingProductId` (String?).
- Keep: `id`, `identityId`, `gradingService`, `grade`, `fetchedAt`, `cacheHit`, `isStaleFallback`.

`SoldListingMirror` model is deleted from the schema and the SwiftData container migration plan.

## `/price-comp` contract

### Request

```
POST /functions/v1/price-comp
Authorization: Bearer <user JWT>
Body: {
  "graded_card_identity_id": "<uuid>",
  "grading_service": "PSA" | "CGC" | "BGS" | "SGC" | "TAG",
  "grade": "10"   // or "9.5", "9", etc.
}
```

### Response 200

```jsonc
{
  "headline_price_cents":     18500,    // tier price for the requested (grader, grade); null if PriceCharting has no value for that exact tier
  "grading_service":          "PSA",
  "grade":                    "10",

  "loose_price_cents":          400,
  "grade_7_price_cents":       2400,
  "grade_8_price_cents":       3400,
  "grade_9_price_cents":       6800,
  "grade_9_5_price_cents":    11200,
  "psa_10_price_cents":       18500,
  "bgs_10_price_cents":       21500,
  "cgc_10_price_cents":       16800,
  "sgc_10_price_cents":       16500,

  "pricecharting_product_id": "12345678",
  "pricecharting_url":        "https://www.pricecharting.com/game/...",

  "fetched_at":               "2026-05-05T22:14:03Z",
  "cache_hit":                false,
  "is_stale_fallback":        false
}
```

Any tier PriceCharting does not publish for the product is `null`. A null `headline_price_cents` does **not** put iOS into the empty-state branch — the snapshot is still resolved (`compFetchState = .resolved`) and the ladder still renders any non-null tiers; the hero number renders as a "—" placeholder with a small "No PriceCharting price for PSA 10 — see related tiers below" caveat. The empty-state branch only fires when all tiers are null, which the Edge Function returns as `404 NO_MARKET_DATA` instead.

### Error responses

| Status | Code | Meaning | iOS copy |
|---|---|---|---|
| 404 | `IDENTITY_NOT_FOUND` | Persisted identity id no longer exists server-side. | "Card identity not on file — re-scan to refresh the cert." |
| 404 | `PRODUCT_NOT_RESOLVED` | `/api/products` search returned zero hits. | "We couldn't find this card on PriceCharting yet." |
| 404 | `NO_MARKET_DATA` | Product resolved but `/api/product` returned no usable prices for any tier. | "PriceCharting has no comp for this slab yet." |
| 502 | `AUTH_INVALID` | PriceCharting returned 401/403. Logged at error level. | "Comp lookup misconfigured — contact support." |
| 503 | `UPSTREAM_UNAVAILABLE` | PriceCharting timeout / 5xx and no cached row. | "Lookup unavailable — try again." Outbox retries with backoff. |

`401` / `403` for the iOS-facing call remains standard Supabase JWT enforcement.

## Hybrid product matching

Inside the Edge Function, ordered:

1. If `identity.pricecharting_product_id` is set, skip search and use it directly.
2. Else build a query string from identity fields:
   `"<card_name>" "<card_number>" <set_name> <year>`
   Quoted name + number bias the match to the exact card; set + year are bias terms. Pokémon is the only catalog in v1, so no game qualifier.
3. `GET https://www.pricecharting.com/api/products?t=<token>&q=<urlencoded query>` — returns up to 20 candidates.
4. Take the top result. Persist `pricecharting_product_id` and `pricecharting_url` onto the identity row via service-role upsert. Log `pc.match.first_resolved` so we can audit drift.
5. If `/api/products` returns zero hits, return `404 { code: "PRODUCT_NOT_RESOLVED" }`. Do not persist anything.

No similarity-score gating in v1. PriceCharting's text match is generally exact on `<name> #<number>` for trading cards; if it returns a poor top hit the `/api/product` follow-up still returns real prices, and a future "force-rematch" flow can correct it.

## Caching, freshness, secrets

- TTL: `PRICECHARTING_FRESHNESS_TTL_SECONDS` default `86400` (24h). PriceCharting data updates roughly daily; tighter is wasted upstream calls.
- `graded_market.updated_at` drives the cache decision. Hit = within TTL → return cached payload (`cache_hit: true`). Stale or miss → live fetch.
- Stale-fallback: PriceCharting 5xx with a row present → return cached payload with `is_stale_fallback: true`. No row + upstream down → `503`.

### Supabase secrets

Set via `supabase secrets set`:

- `PRICECHARTING_API_TOKEN` — 40-character subscription token from the PriceCharting account dashboard.
- `PRICECHARTING_FRESHNESS_TTL_SECONDS` — default `86400`.

Removed:
- `EBAY_APP_ID`
- `EBAY_CERT_ID`
- `EBAY_FRESHNESS_TTL_SECONDS`
- `EBAY_MIN_RESULTS_HEADLINE`
- `EBAY_OAUTH_SCOPE`

The eBay account-deletion webhook stays — Movers feature still uses eBay.

## Persistence (live path)

Order within a single Edge Function invocation:

1. Resolve `pricecharting_product_id` (cached or via search). On a fresh search, upsert the id + url onto `graded_card_identities`.
2. `GET /api/product?t=<token>&id=<pc_product_id>`. Parse pennies-int prices → `numeric(12,2)` dollars for the SQL columns.
3. Upsert one `graded_market` row for `(identity_id, grading_service, grade)` with all per-tier columns + `pricecharting_product_id`, `pricecharting_url`, `source = 'pricecharting'`, `updated_at = now()`.
4. Return response payload built from the upserted row (cache-hit and live-fetch responses are byte-identical in shape).

All writes use the service-role Supabase client.

## Failure modes

| Class | Behavior |
|---|---|
| PriceCharting 5xx / network error | If `graded_market` row exists (even stale), return it with `is_stale_fallback: true` and log. If no cache, `503 UPSTREAM_UNAVAILABLE`. Client outbox retries. |
| PriceCharting 429 rate-limit | Same as 5xx; additionally pause all live fetches in this isolate for 60 seconds (module-scope timestamp). |
| PriceCharting 401 / 403 | `502 AUTH_INVALID`. Log at ERROR (token issue). No retry. |
| Search returns zero hits | `404 PRODUCT_NOT_RESOLVED`. No persistence. |
| Search top hit returns a product with no prices for any tier | `404 NO_MARKET_DATA`. Identity is updated with the resolved id (so a future refresh can work without a re-search). |
| Requested grade tier missing, other tiers present | Respond 200 with `headline_price_cents: null` and the rest of the ladder populated. iOS renders the ladder with the headline cell shown as "—". |
| Every tier missing | `404 NO_MARKET_DATA`. iOS empty-state branch renders. |
| Cached id refers to a deleted PriceCharting product | `/api/product` returns 404 → return `404 NO_MARKET_DATA` and clear the cached id on the identity row so the next scan re-runs search. |

## iOS changes

### `CompCardView`

- **Hero row** — headline price (`headlinePriceCents`) + a small kicker showing `<grader> <grade>`. No confidence chip, no sample-count line.
- **Grade ladder rail** replaces the Low/Median/High strip. Horizontal scroll of cells: Raw / 7 / 8 / 9 / 9.5 / PSA 10 / BGS 10 / CGC 10 / SGC 10. Cells render only for non-null tiers. The cell matching the requested `(grader, grade)` gets a gold border to mark the headline position. Empty list (every tier null) hides the rail entirely.
- **Footer** — "Powered by PriceCharting · View on PriceCharting →" — full-card secondary tap target deep-links to `pricechartingURL`.
- Caveat row removed (no `sampleCount` or `isStaleFallback != true` chrome). The stale chip stays only for `isStaleFallback`.

### `ScanDetailView`

- The "Active listings · N" section is removed.
- `valueSection` and the `fallbackContent` state machine stay. "Refresh comp" still wires to `CompFetchService.fetch`.
- Empty/loading/error copy updates:
  - `fetchingState`: "Fetching PriceCharting comp…"
  - `noDataState`: "PriceCharting has no comp for this slab yet."
  - New `productNotResolvedState`: "We couldn't find this card on PriceCharting."
  - `failedState`: copy generalized from "eBay lookup unavailable" to "PriceCharting lookup unavailable."
- `OtherGradersPanel` (already in the file tree) is unaffected — it reads from a different data path.

### `CompRepository`

- `Wire` / `Decoded` reshape to match the new payload (per-tier fields, no `sold_listings`, no statistics).
- `Error` cases:
  - Keep: `noMarketData`, `upstreamUnavailable`, `identityNotFound`, `httpStatus`, `decoding`.
  - Remove: `notDeployed` (no longer accurate — `404` body always has a `code` now).
  - Add: `productNotResolved`, `authInvalid`.

### `CompFetchService`

- `persistSnapshot` reshapes to write the new tier columns.
- In-flight tracking, `flipMatching`, the absorber pattern, and the state-machine flips are unchanged. The `(identityId, service, grade)` cache key still de-dupes parallel scans of the same slab.
- `classify` updates user-facing copy and error mappings.

### Outbox

`OutboxKind.priceCompJob` and the retry/backoff in the outbox driver are unchanged.

## Files: delete / rewrite / add

### Delete

- `supabase/functions/price-comp/ebay/` (entire directory: `browse.ts`, `cascade.ts`, `marketplace-insights.ts`, `oauth.ts`, `query-builder.ts`)
- `supabase/functions/price-comp/persistence/scan-event.ts`
- `supabase/functions/price-comp/stats/` (`aggregates.ts`, `confidence.ts`, `outliers.ts` — irrelevant for tier prices)
- `supabase/functions/price-comp/lib/grade-normalize.ts` and `graded-title-parse.ts` if no remaining caller (verify in plan; `grade-normalize` is likely still useful for mapping `(grader, grade)` to a tier column key)
- `supabase/functions/price-comp/__fixtures__/ebay/` (entire directory)
- `ios/slabbist/slabbist/Core/Models/SoldListingMirror.swift`

### Rewrite

- `supabase/functions/price-comp/index.ts` — new orchestrator
- `supabase/functions/price-comp/types.ts` — new request/response/internal types
- `supabase/functions/price-comp/persistence/market.ts` — write per-tier columns
- `supabase/functions/price-comp/cache/freshness.ts` — same logic, re-tuned default TTL
- `supabase/functions/price-comp/__tests__/` — updated unit + integration tests
- `ios/slabbist/slabbist/Features/Comp/CompCardView.swift`
- `ios/slabbist/slabbist/Features/Comp/CompRepository.swift`
- `ios/slabbist/slabbist/Features/Comp/CompFetchService.swift` (only `persistSnapshot` + `classify` change)
- `ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift` — listings section removed, copy updated
- `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift` — reshape

### Add

- `supabase/functions/price-comp/pricecharting/client.ts` — fetch helper, shared headers, retry-once-on-401, rate-limit pause
- `supabase/functions/price-comp/pricecharting/search.ts` — `searchProducts(q)` wrapper
- `supabase/functions/price-comp/pricecharting/product.ts` — `getProduct(id)` wrapper
- `supabase/functions/price-comp/pricecharting/parse.ts` — pennies-int → numeric, missing-tier handling, grade key map
- `supabase/functions/price-comp/persistence/identity-product-id.ts` — upsert helper for `graded_card_identities.pricecharting_product_id`
- `supabase/functions/price-comp/__fixtures__/pricecharting/` — canned responses for tests
- `supabase/migrations/2026-05-05_pricecharting_product_id_on_identities.sql`
- `supabase/migrations/2026-05-05_graded_market_pricecharting_columns.sql`
- `supabase/migrations/2026-05-05_drop_graded_market_sales.sql`
- `supabase/migrations/2026-05-05_drop_slab_scan_events.sql`

## Testing strategy

### Edge Function unit (Deno, inside the function's test file)

- **PriceCharting client**:
  - Token sent as `t=` query param.
  - `YYYY-MM-DD` date strings parsed correctly.
  - Pennies integers parsed correctly (e.g., `1732` → `17.32`).
  - Missing tier fields → `null` in our model.
  - `401` triggers single retry then surfaces as `AUTH_INVALID`.
  - `429` triggers in-isolate pause flag.
- **Hybrid match**:
  - Cached id path skips search.
  - Missing id path calls `/api/products`.
  - Zero-hit search returns `PRODUCT_NOT_RESOLVED`, no persistence.
  - First-time match persists id + url onto identity.
- **Grade → tier mapping**:
  - `(PSA, "10") → psa_10_price`
  - `(PSA, "9")` → `grade_9_price` (PriceCharting publishes generic `grade_9_price` only)
  - `(PSA, "9.5") → grade_9_5_price`
  - `(BGS, "10") → bgs_10_price`
  - `(BGS, "9.5") → grade_9_5_price`
  - `(CGC, "10") → cgc_10_price`
  - `(SGC, "10") → sgc_10_price`
  - Unmapped combos → headline `null`, ladder still populated.
- **Cache freshness**: fresh / stale / missing branches; stale + upstream-up → live; stale + upstream-down → cached + `is_stale_fallback`.

### Edge Function integration

- Local mock PriceCharting server (Deno `serve` returning canned fixtures from `__fixtures__/pricecharting/`).
- Seeded `graded_card_identities`; assert one `graded_market` row with full ladder.
- Cache-hit path: second call within TTL returns `cache_hit: true` without hitting the mock.
- Stale-fallback path: mock 500; assert `is_stale_fallback: true` and stale payload returned.
- Identity-product-id stickiness: first call persists id; second call skips search.

### iOS (Swift Testing)

- Decode tests for the full new payload (all tiers populated, partial tiers, headline-null, missing url).
- `CompFetchService.persistSnapshot` writes the right tier columns (no `SoldListingMirror` produced).
- `CompFetchService` flip-matching unchanged — same in-flight de-dup behavior.
- `CompCardView` snapshot tests: full ladder, partial ladder (some tiers null), empty ladder (headline-only), gold-border placement on the requested tier.
- Migration test: an existing SwiftData store with old `GradedMarketSnapshot` rows opens cleanly under the new schema (lightweight migration if possible; destructive seed if not — TBD by the implementation plan).

### Manual end-to-end

- One simulator flow on a known PSA 10 (e.g., a real cert) to verify live path → ladder → deep-link.
- One simulator flow on a known BGS 9.5 to verify the BGS tier mapping.
- One simulator flow on a never-seen identity to verify search → product-id persistence → second scan skips search.
- Airplane-mode flow to verify outbox retry on `503`.

## Observability

Structured logs via the Edge Function's stdout (Supabase Logs), one log line per fetch:

```json
{
  "fn": "price-comp",
  "identity_id": "…",
  "grading_service": "PSA",
  "grade": "10",
  "cache_state": "hit" | "miss" | "stale",
  "live_fetch": true | false,
  "matched": "cached" | "searched" | "unresolved",
  "pricecharting_product_id": "12345678",
  "headline_present": true,
  "is_stale_fallback": false,
  "response_time_ms": 412
}
```

Plus targeted error markers: `pc.auth_invalid`, `pc.upstream_5xx`, `pc.match.first_resolved`, `pc.match.zero_hits`, `pc.product.no_prices`.

## Security

- The PriceCharting subscription token (40-char) is server-only via `PRICECHARTING_API_TOKEN`. Never returned to iOS, never logged, never embedded in error responses.
- Rotate via the PriceCharting account dashboard + `supabase secrets set` — no redeploy.
- No end-user credentials are involved; PriceCharting access is application-scoped.

## Open follow-ups (for implementation plan or post-launch)

- A "force-rematch" UX so a user can correct a wrong cached `pricecharting_product_id` without DB access.
- Pre-warm cron in the scraper for the highest-scanned identities — drops cold-path latency to zero, optional v1.
- Surface a price-history sparkline if PriceCharting exposes one in the API (verify in plan; sparkline data may require the `/api/sales` endpoint or be paid-tier-only).
- Tune `PRICECHARTING_FRESHNESS_TTL_SECONDS` against observed re-scan cadence.
- Decide whether to drop `low_price` / `median_price` / `high_price` from `graded_market` entirely (depends on remaining consumers — verify in plan).
- Verify whether `lib/grade-normalize.ts` still has callers after the rewrite; delete if not.

## Cross-cutting references

- Superseded eBay comp spec: [`2026-04-23-ebay-sold-listings-comp-design.md`](./2026-04-23-ebay-sold-listings-comp-design.md)
- Parent comp spec (still authoritative for outbox, cert lookup, and overall comp lifecycle): [`2026-04-22-bulk-scan-comp-design.md`](./2026-04-22-bulk-scan-comp-design.md)
- PriceCharting API documentation: <https://www.pricecharting.com/api-documentation>
- Raw/graded decoupling memory note — this feature stays fully inside the graded domain.
- Movers feature (separate eBay surface, unaffected by this change): `Features/Movers/`, `mover_ebay_listings`, `ebay-account-deletion` webhook.
