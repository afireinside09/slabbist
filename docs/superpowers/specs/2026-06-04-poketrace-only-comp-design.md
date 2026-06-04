# Poketrace-only comp + richer eBay sold data — Design

**Date:** 2026-06-04
**Status:** Approved (brainstorm) → pending implementation plan
**Supersedes:** `2026-05-06-pokemonpricetracker-comp-design.md`, `2026-05-08-poketrace-comp-design.md` (the dual-provider reconciliation model)

## Goal

Remove **PokemonPriceTracker (PPT)** from every surface of the project and move forward with **Poketrace** as the sole graded-pricing provider. Simultaneously, surface **more eBay sold-listing data** in the iOS comp UI by adopting Poketrace's newer API (v1.7.0): native card search, individual sold listings, and marketplace deep-links.

This is a **clean break**, not a deprecation. PPT code, columns, config, fixtures, tests, and the two-provider `reconcile()` averaging logic are deleted.

## Why now / context

- PPT was the **primary identity resolver** (card_name/set/number → TCGplayer `product_id`) *and* a co-equal price source reconciled against Poketrace. Removing it requires Poketrace to resolve identities on its own.
- The original Poketrace integration spec (2026-05-08) documented only three endpoints and **no** native search or sold-listings endpoint. A live probe of the OpenAPI spec (`https://api.poketrace.com/v1/openapi.json`, **v1.7.0**) on 2026-06-04 showed the API has since grown:
  - `GET /cards?search=&set=&card_number=&variant=&rarity=&has_graded=` — native search returning card UUIDs directly (no TCGplayer id needed).
  - `GET /cards/{id}/listings` — **individual sold eBay listings** (`title, price, soldAt, grader, grade, condition, listingUrl, anomalyFlag, anomalyReason`), filterable by grader/grade/price, sortable by sold date. **Requires the Scale plan** (rate-limited 30 req/30s).
  - `GET /cards/{id}` — prices by source (`ebay` all tiers, `tcgplayer` raw) and tier, **plus `marketplaceUrls`** deep-links.
  - `GET /cards/{id}/prices/{tier}/history` — per-tier daily history (unchanged).

## Decisions (locked during brainstorm)

1. **Resolution:** Tier A (local `tcg_products` → `tcgplayer_ids` cross-walk) primary + **Poketrace native `search` fallback** (replaces PPT fuzzy tiers B/C/D).
2. **Sold listings:** Build the sold-comps UI against `GET /cards/{id}/listings` with **graceful-degrade** — lights up on Scale plan, falls back to ebay-source aggregates + a "View sold on eBay" deep-link otherwise.
3. **DB columns:** **Drop** the PPT columns (destructive migration).
4. **`ppt_tcgplayer_id` is renamed, not dropped** — it stores a TCGplayer `product_id` still needed for the Tier A cross-walk → `tcgplayer_product_id`.
5. **Reuse `graded_market_sales`** (existing base table) for persisting sold comps.
6. **Coordinated breaking cutover** — edge function + iOS land together; the response contract is a clean v3 with no PPT fields. Acceptable because the product is pre-release.

## Architecture

### A. Edge Function `price-comp`

**Deleted:**
- `ppt/` (`cards.ts`, `client.ts`, `match.ts`, `parse.ts`), `__fixtures__/ppt/`, and all PPT tests (`index.test.ts`, `index-fanout.test.ts`, `match.test.ts`, `match-property.test.ts`, `parse.test.ts`, `cards.test.ts`, `client.test.ts`, `aliases-property.test.ts` where PPT-specific, `regression.test.ts` baseline rebuild).
- `persistIdentityPPTId` / `clearIdentityPPTId` (in `persistence/identity-product-id.ts`).
- `reconcile()`, `PPTData`, `Phase1Result`, `Phase1ShortCircuit`, the two-provider `Promise.allSettled` fan-out, and the `ReconciledBlock` type.
- Config: `pptBaseUrl`, `pptToken`, env `POKEMONPRICETRACKER_API_TOKEN`, `POKEMONPRICETRACKER_FRESHNESS_TTL_SECONDS`.

**Kept:** `lib/tcg-products.ts`, `lib/psa-aliases.ts`, `lib/grade-key.ts`, `lib/poketrace-tier-key.ts`, `poketrace/client.ts`, `poketrace/prices.ts`, `poketrace/history.ts`, `cache/freshness.ts`.

**New — `poketrace/resolve.ts`** (single resolver, replaces `ppt/match.ts` + `poketrace/match.ts`):
- **Tier A (primary):** `aliasForPsaSet(set_name)` → `findTcgProductByGroupAndCard` → `product_id` → `GET /cards?tcgplayer_ids=<product_id>&limit=20` → first UUID. Walk primary + alt group ids as today.
- **Tier B (fallback):** `GET /cards?search=<card_name>&card_number=<n>&limit=20` (omit `set` to avoid set-slug mapping); re-rank with a ported `scoreCard` (name substring + card-number exact/prefix + distinctive set-token overlap against `Card.set`); accept top scorer above threshold. Final attempt: bare `search=<card_name>&limit=20`.
- Cache resolved UUID on `graded_card_identities.poketrace_card_id`; keep `''` negative-cache sentinel + 7-day re-attempt.
- Returns `{ cardId, attemptLog, tierMatched }` for observability.

**New — `poketrace/listings.ts`:**
- `GET /cards/{id}/listings?grader=<svc>&grade=<grade>&sort=sold_at_desc&limit=20`.
- Parse `ListingsResponse.data` → app-shaped sold listings.
- Graceful: non-200 (incl. `403 UPGRADE_REQUIRED`) or empty → `[]`. Never throws into the comp happy path.

**New flow (`handle`):**
1. Identity lookup.
2. Cache read (`readMarketLadder` source `'poketrace'` only) + freshness.
3. On miss: `resolve.ts` → UUID. If none → `404 { code: 'PRODUCT_NOT_RESOLVED', attempt_log }`.
4. Parallel: `fetchPoketracePrices` + `fetchPoketraceHistory` + `fetchPoketraceListings`.
5. Persist: `upsertMarketLadder` (poketrace block) + upsert sold listings into `graded_market_sales`.
6. Assemble **v3 response**.

**Response contract (v3, `PriceCompResponse`):**
```
{
  grading_service, grade,
  headline_price_cents,          // = poketrace avg
  poketrace: {                   // null when no graded data for the tier
    avg/low/high_cents, avg_1d/7d/30d_cents,
    median_3d/7d/30d_cents, trend, confidence, sale_count,
    tier_prices_cents,           // iOS ladder map
    price_history: [{ ts, price_cents }]
  },
  sold_listings: [{ source_listing_id, title, price_cents, sold_at,
                    grader, grade, condition, url, anomaly_flag }],
  marketplace_url,               // ebay sold-results deep link, nullable
  fetched_at, cache_hit
}
```
No `ppt_*`, no `reconciled`, no `loose/psa_*_price_cents` ladder fields (the ladder is `poketrace.tier_prices_cents`).

**Persistence changes:** `persistence/market.ts` writes only the poketrace columns (no PPT branch). `persistence/identity-product-id.ts` keeps the poketrace-card-id helpers (renamed column), drops the PPT helpers.

### B. Database (one new timestamped migration)

> Exact column list to be confirmed by introspecting the live DB before finalizing (per the migration-ledger lesson — schema may have drifted from migration history).

- **`graded_market`** — drop: `ppt_tcgplayer_id, ppt_url, psa_7_price, psa_8_price, psa_9_price, psa_9_5_price, price_history`. Keep `pt_*` and base columns (`low_price, median_price, high_price, last_sale_price, last_sale_at, sample_count_30d, sample_count_90d, updated_at`).
- Delete rows `where source = 'pokemonpricetracker'`; set `source` default `'poketrace'`. (Keep `source` in the PK for now; collapsing it is out of scope.)
- **`graded_card_identities`** — drop `ppt_url`; **rename `ppt_tcgplayer_id` → `tcgplayer_product_id`**; rename index `graded_card_identities_ppt_tcgplayer_idx` → `graded_card_identities_tcgplayer_product_idx`.
- **`graded_market_sales`** — add `grader text null` and `anomaly_flag text null` (`grade` already exists). Edge function upserts on conflict `(source, source_listing_id)`. `source = 'ebay'`.
- RLS: any new/changed table access re-verified in `supabase/tests/rls_*.sql`.

### C. iOS

- **`Core/Models/GradedMarketSnapshot.swift`** — remove `ppt*` fields; `pt*` fields become the sole source; add `marketplaceURL: URL?` and `soldListings: [SoldListing]`. New `SoldListing` value type (title, priceCents, soldAt, grader, grade, condition, url, anomalyFlag).
- **`Features/Comp/CompFetchService.swift` + `Core/Data/Repositories/CompRepository.swift`** — decode the v3 contract. **Live `Decodable` round-trip against the deployed function required before cutover.**
- **`Features/Comp/CompCardView.swift`** — remove the PPT/Poketrace source toggle and PPT ladder; render the Poketrace ladder + aggregates (sale_count, trend, confidence, medians) as the single source; add a **sold-comps section**: scrollable list (title, grade, price, sold date; tap → `listingUrl`) + "View all sold on eBay" deep-link; graceful empty state when listings unavailable.
- Clean `ppt` references in `Scan.swift`, `ScanDetailView.swift`, `ScanRowTrailingState.swift`, `OutboxPayloads.swift`, `UITestEnvironment.swift`.
- Update/regenerate Comp snapshot tests (`CompCardViewSnapshotTests`, `CompCardViewTests`, `CompRepositoryTests`, `CompFetchServiceTests`, `CompFetchE2ETests`). Invoke `swiftui-expert-skill` for the view work.

### D. Scraper & scripts

- Scraper graded path is already Poketrace-only — confirm no stray PPT refs.
- `scripts/probe-resolver.ts` (PPT-resolver hit-rate probe) → delete, or rewrite against `poketrace/resolve.ts`.

### E. Docs / memory

- Mark superseded specs/plans. Update `slabbist-product` skill `glossary.md` / `value-loops.md` PPT mentions. Record the Poketrace v1.7.0 API surface.

## Error handling

- Resolution miss → `404 { code: 'PRODUCT_NOT_RESOLVED', attempt_log }`.
- Poketrace upstream 5xx/429 → serve stale cache when present (existing freshness fallback); otherwise `502`/empty block. Sold-listings failures degrade to `[]` and never block prices.
- Non-Scale plan → `/cards/{id}/listings` 403 → empty list; UI shows aggregates + deep-link only.

## Testing / success criteria

- Edge unit tests: `resolve.ts` (Tier A hit, Tier A miss → Tier B search hit, total miss), `listings.ts` (parse, 403 → [], empty → []), `market.ts` poketrace-only persistence. New regression baseline.
- **Live decode round-trip:** deployed function response decodes into the iOS v3 model with no shape mismatch.
- RLS tests pass for `graded_market_sales` writes.
- iOS builds; Comp snapshot tests updated and passing.
- Repo-wide: zero remaining references to `pokemonpricetracker` / `ppt` (outside this dated spec and superseded docs).

## Out of scope

- Collapsing `source` out of the `graded_market` PK.
- EU/CardMarket data, websocket, or `has_graded` filtering.
- Backfilling historical sold listings for existing slabs (only fetched on the next live comp).
