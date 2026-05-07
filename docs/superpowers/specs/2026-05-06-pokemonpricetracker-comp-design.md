# Pokemon Price Tracker Comp — Design Spec

**Sub-project:** #4 (Comp engine v1) — replatform
**Date:** 2026-05-06
**Status:** Design draft; awaiting user review
**Supersedes:** [`2026-05-05-pricecharting-comp-design.md`](./2026-05-05-pricecharting-comp-design.md) for the scan-time comp path

## Summary

Replaces the PriceCharting-backed `/price-comp` Edge Function with a Pokemon Price Tracker (PPT) backed equivalent. PriceCharting just landed (2026-05-05) but is being ripped out: PPT's API is significantly cheaper at our scan volume, exposes a Pokémon-native data model (PSA 1–10 + a TCGPlayer raw price), and ships a 6-month price history in the same call we use for the headline. Everything PriceCharting-specific in the function, the database, and the iOS client is removed; no compatibility shims. The `/price-comp` URL, the iOS outbox kind, and the overall hybrid match-then-cache architecture are preserved.

A v1.1 follow-up may broaden the ladder beyond Raw + PSA 7/8/9/10 if signal demands; v1 ships the curated rail plus a 6-month sparkline driven by PPT's `priceHistory` payload.

## Goals

1. A scan of a graded Pokémon card returns a defensible comp in one round-trip using PPT as the source of truth.
2. The iOS-facing endpoint URL (`/price-comp`) and outbox kind stay unchanged so iOS routing is reused.
3. The headline number for `(PSA, "10")`, `(PSA, "9")`, etc. comes from PPT's `ebay.{tier}.avg` graded prices; raw/loose comes from PPT's TCGPlayer `prices.market`.
4. A 6-month price history sparkline renders in the comp card from PPT's `priceHistory` payload.
5. A real-listings escape hatch — every comp deep-links to the PPT product page so users can verify against actual sales.
6. First-scan latency is amortized by caching the resolved PPT card identifier on the identity row (one search per identity, ever).
7. PriceCharting scaffolding installed yesterday (Edge Function code, secrets, schema columns, identity-row columns, iOS model fields) is removed cleanly.

## Non-goals

- BGS, CGC, SGC, TAG headline values. PPT does not publish them. A request for `(BGS, "10")` returns `headline_price_cents: null` with the ladder still populated; iOS shows the same caveat row used today for missing-tier responses.
- Sparkline pre-warm via the scraper. v1 fetches history on demand inside the existing live-fetch path.
- A "force-rematch" UX for correcting a wrong cached PPT card id. Reserved as a follow-up.
- Bulk pre-warming the popular-watchlist via `POST /api/v2/cards/bulk-price`. Reserved for v1.1 if cost telemetry justifies it.
- Non-Pokémon catalogs.
- Dev / sandbox PPT environment wiring — production only for MVP.

## API surface (Pokemon Price Tracker)

Authoritative reference: <https://www.pokemonpricetracker.com/docs>. All field names quoted in this spec are best-effort from public documentation pages and search results; the implementation plan **must** include a probe step that hits the live API with the issued token and fixes any field-name drift in this spec before code lands.

- Base URL: `https://www.pokemonpricetracker.com`
- Auth: `Authorization: Bearer <token>`. Header `X-API-Version: v1` (per docs).
- Plan: API tier ($9.99/mo, 20k credits/day, 60 calls/min, 6-month history).
- Endpoint we use: `GET /api/v2/cards`
  - Two query modes:
    - **Cold path (no cached id):** `?search=<built query>&limit=1&includeEbay=true&includeHistory=true&days=180&maxDataPoints=30`
    - **Warm path (cached id):** `?tcgPlayerId=<id>&includeEbay=true&includeHistory=true&days=180&maxDataPoints=30`
  - Response is a card array (or single object — verify in plan probe). Each card carries:
    - `tcgPlayerId` — the stable identifier we cache on the identity row
    - `name`, `set`, `number`
    - `prices.market` — TCGPlayer market in dollars; this maps to `loose_price_cents` (raw)
    - `ebay.{psa1..psa10}.avg` — PSA-graded eBay averages in dollars; maps to `psa_{n}_price_cents`
    - `priceHistory` — series of `{date, price}` points; we persist exactly the entries returned (PPT decimates to ~30 points over 180 days when `maxDataPoints=30`)
    - A canonical product page URL — verify the field name in the probe (`url`, `productUrl`, or derivable from `tcgPlayerId`)
- Credit cost per fresh fetch: **3 credits** (1 base + 1 `includeHistory` + 1 `includeEbay`). At 20k/day → ~6,600 fresh fetches/day; with the 24h cache TTL, vastly more scans.
- Rate-limit response: `429`. We treat it the same way the current PriceCharting client does — 60 second module-scope pause, surface 429 to caller.

The collapse-to-one-call-per-fetch model is a meaningful simplification over PriceCharting's two-call (`/api/products` then `/api/product`) flow. There is no separate "search" step in steady state — the same endpoint resolves a card by query string or by id.

## Architecture

```
iOS  ──────►  /price-comp (Edge Function, Deno)
                 │
                 ├─ load graded_card_identity (validates existence)
                 │
                 ├─ cache read on graded_market for (identity, grader, grade)
                 │     ├─ row + updated_at within TTL → return cached
                 │     └─ stale or miss → live fetch
                 │
                 ├─ LIVE fetch — single PPT call:
                 │     ├─ identity.ppt_tcgplayer_id present?
                 │     │     → GET /api/v2/cards?tcgPlayerId=<id>&includeEbay&includeHistory
                 │     └─ else:
                 │           → GET /api/v2/cards?search=<built query>&limit=1&includeEbay&includeHistory
                 │           → take first hit, persist tcgPlayerId + url onto identity
                 │           → if zero hits: 404 PRODUCT_NOT_RESOLVED (no persistence)
                 │
                 ├─ extract:
                 │     ├─ loose_price_cents      ← prices.market * 100
                 │     ├─ psa_7..psa_10_price_cents ← ebay.psa{n}.avg * 100
                 │     ├─ price_history          ← priceHistory.map({date, cents})
                 │     ├─ headline_price_cents   ← pickTier(ebay, grading_service, grade)
                 │     └─ ppt_url                ← canonical product page
                 │
                 ├─ upsert graded_market with the full row
                 │
                 └─ return payload (headline + ladder + sparkline + deep-link + cache flags)
```

### Boundaries

- iOS never calls PPT directly. The two-endpoint contract from the parent comp spec (`/cert-lookup`, `/price-comp`) holds.
- PPT access is server-only via `POKEMONPRICETRACKER_API_TOKEN`. Token rotation is a Supabase secret rotation, not a redeploy.
- Live fetch writes only to `graded_market` and the new identity columns with the service-role client. No new tables.

## Data model

### Migration: drop PriceCharting columns from identities, add PPT columns

```sql
alter table public.graded_card_identities
  drop column if exists pricecharting_product_id,
  drop column if exists pricecharting_url;

alter table public.graded_card_identities
  add column if not exists ppt_tcgplayer_id text,
  add column if not exists ppt_url          text;

create index if not exists graded_card_identities_ppt_tcgplayer_idx
  on public.graded_card_identities (ppt_tcgplayer_id)
  where ppt_tcgplayer_id is not null;
```

Both new columns are nullable. Persisted once after the first successful match; subsequent scans skip the search round-trip. No backfill — existing rows pick up an id on first scan.

The PriceCharting index `graded_card_identities_pc_product_idx` is dropped automatically when its column is dropped.

### Migration: reshape `graded_market` for PPT

PPT publishes PSA 1–10 (whole grades, no half-grade) plus a TCGPlayer raw price. The v1 ladder displays Raw + PSA 7/8/9/10, so we persist exactly those columns. PSA 1–6 are lost data we can re-introduce in v1.1 by a column-addition migration if signal warrants.

```sql
alter table public.graded_market
  drop column if exists pricecharting_product_id,
  drop column if exists pricecharting_url,
  drop column if exists grade_7_price,
  drop column if exists grade_8_price,
  drop column if exists grade_9_price,
  drop column if exists grade_9_5_price,
  drop column if exists bgs_10_price,
  drop column if exists cgc_10_price,
  drop column if exists sgc_10_price;

alter table public.graded_market
  add column if not exists ppt_tcgplayer_id text,
  add column if not exists ppt_url          text,
  add column if not exists psa_7_price      numeric(12,2),
  add column if not exists psa_8_price      numeric(12,2),
  add column if not exists psa_9_price      numeric(12,2),
  add column if not exists price_history    jsonb;

-- Source column already exists from the PriceCharting migration; flip default
-- and existing rows. After this migration there are no PriceCharting rows.
update public.graded_market set source = 'pokemonpricetracker' where source = 'pricecharting';
alter table public.graded_market alter column source set default 'pokemonpricetracker';
```

The implementation plan must verify whether any non-comp consumer reads `low_price` / `median_price` / `high_price`. If nothing else reads them, drop them in this migration as well; if a consumer remains, leave them and have the new code write `low_price = high_price = median_price = headline_price`. Default is to drop, mirroring the previous spec's stance.

The `psa_10_price` column already exists from yesterday's PriceCharting migration; this migration leaves it in place.

### Migration: drop PriceCharting secret variables (handled outside SQL)

Not a SQL migration — listed in the secrets section below.

### iOS SwiftData

`GradedMarketSnapshot` reshape:

- Remove: `grade7PriceCents`, `grade8PriceCents`, `grade9PriceCents`, `grade9_5PriceCents`, `bgs10PriceCents`, `cgc10PriceCents`, `sgc10PriceCents`, `pricechartingProductId`, `pricechartingURL`.
- Add: `psa7PriceCents`, `psa8PriceCents`, `psa9PriceCents` (Int64?); `pptTCGPlayerId` (String?), `pptURL` (URL?), `priceHistoryJSON` (String?).
- Keep: `id`, `identityId`, `gradingService`, `grade`, `headlinePriceCents`, `loosePriceCents`, `psa10PriceCents`, `fetchedAt`, `cacheHit`, `isStaleFallback`.

`priceHistoryJSON` is a SwiftData-friendly JSON-string blob, decoded on demand to `[PriceHistoryPoint]` for the sparkline view. We store as String rather than `[Data]` because SwiftData is fussy about heterogeneous arrays and the points are read-only render input.

Migration strategy: a SwiftData lightweight migration cannot rename / drop / add columns simultaneously here. The implementation plan should default to a destructive seed (clear `GradedMarketSnapshot` rows on first launch under the new schema) — these snapshots are server-derivable cache, not user data, so the cost is one re-fetch per user per active slab. If the plan finds a clean lightweight path, take it.

## `/price-comp` contract

### Request

```
POST /functions/v1/price-comp
Authorization: Bearer <user JWT>
Body: {
  "graded_card_identity_id": "<uuid>",
  "grading_service": "PSA" | "CGC" | "BGS" | "SGC" | "TAG",
  "grade": "10"   // or "9", "8", etc.
}
```

### Response 200

```jsonc
{
  "headline_price_cents":  18500,    // tier price for the requested (grader, grade); null if unsupported (e.g. BGS) or absent
  "grading_service":       "PSA",
  "grade":                 "10",

  "loose_price_cents":      400,
  "psa_7_price_cents":     2400,
  "psa_8_price_cents":     3400,
  "psa_9_price_cents":     6800,
  "psa_10_price_cents":   18500,

  "price_history": [
    { "ts": "2025-11-08T00:00:00Z", "price_cents": 16200 },
    { "ts": "2025-11-15T00:00:00Z", "price_cents": 16850 },
    /* up to ~30 points across 180 days */
  ],

  "ppt_tcgplayer_id":     "243172",
  "ppt_url":              "https://www.pokemonpricetracker.com/card/...",

  "fetched_at":           "2026-05-06T15:14:03Z",
  "cache_hit":            false,
  "is_stale_fallback":    false
}
```

A null `headline_price_cents` does **not** put iOS into the empty-state branch — the snapshot is still resolved (`compFetchState = .resolved`) and the ladder still renders any non-null tiers. The hero number renders `—` with a small caveat row ("No Pokemon Price Tracker headline for BGS 10 — see PSA tiers below"). The empty-state branch fires only when every PSA tier and `loose_price` are null, which the Edge Function returns as `404 NO_MARKET_DATA`.

### Error responses

| Status | Code | Meaning | iOS copy |
|---|---|---|---|
| 404 | `IDENTITY_NOT_FOUND` | Persisted identity id no longer exists server-side. | "Card identity not on file — re-scan to refresh the cert." |
| 404 | `PRODUCT_NOT_RESOLVED` | Search returned zero hits. | "We couldn't find this card on Pokemon Price Tracker yet." |
| 404 | `NO_MARKET_DATA` | Card resolved but PPT returned no usable prices for any tier. | "Pokemon Price Tracker has no comp for this slab yet." |
| 502 | `AUTH_INVALID` | PPT returned 401/403. Logged at error level. | "Comp lookup misconfigured — contact support." |
| 503 | `UPSTREAM_UNAVAILABLE` | PPT timeout / 5xx and no cached row. | "Lookup unavailable — try again." Outbox retries with backoff. |

The error codes themselves are stable across the PC → PPT swap. iOS-facing copy updates wherever the source name appeared.

## Hybrid product matching

Inside the Edge Function, ordered:

1. If `identity.ppt_tcgplayer_id` is set: live fetch with `?tcgPlayerId=<id>&...`.
2. Else build a search query from identity fields:
   `<card_name> <card_number> <set_name> <year>`
   Unquoted, space-joined. PPT's search is fuzzy (the `parse-title` endpoint exists for cases where strict parsing matters; `/api/v2/cards?search=` is documented as natural-language). The implementation plan probe should validate this assumption against a few real identities before locking it in. If precision is lacking, fall back to `parse-title` as the search step.
3. Live fetch with `?search=<urlencoded query>&limit=1&...`.
4. If the response array is empty: return `404 { code: "PRODUCT_NOT_RESOLVED" }`. Do not persist anything. Log `ppt.match.zero_hits`.
5. Take the first card. Persist `ppt_tcgplayer_id` and `ppt_url` onto the identity row via service-role upsert. Log `ppt.match.first_resolved`.

No similarity-score gating in v1. A future "force-rematch" flow can correct mismatches.

## Caching, freshness, secrets

- TTL: `POKEMONPRICETRACKER_FRESHNESS_TTL_SECONDS` default `86400` (24h). PPT data updates roughly daily; tighter is wasted upstream calls and wasted credits.
- `graded_market.updated_at` drives the cache decision. Hit = within TTL → return cached payload (`cache_hit: true`). Stale or miss → live fetch.
- Stale-fallback: PPT 5xx with a row present → return cached payload with `is_stale_fallback: true`. No row + upstream down → `503`.

### Supabase secrets

Set via `supabase secrets set`:

- `POKEMONPRICETRACKER_API_TOKEN` — Bearer token from the PPT account dashboard.
- `POKEMONPRICETRACKER_FRESHNESS_TTL_SECONDS` — default `86400`.

Removed (yesterday's PriceCharting secrets):
- `PRICECHARTING_API_TOKEN`
- `PRICECHARTING_FRESHNESS_TTL_SECONDS`

The eBay account-deletion webhook stays — Movers feature still uses eBay independently.

## Persistence (live path)

Order within a single Edge Function invocation:

1. Cache-read: `readMarketLadder(identity_id, grader, grade)`. Hit-within-TTL short-circuits.
2. Resolve fetch URL — by `tcgPlayerId` if cached on identity; otherwise by `search`.
3. Single `GET /api/v2/cards?...&includeEbay=true&includeHistory=true`. Parse:
   - `prices.market` (dollars, float) → `loose_price_cents` (cents, int).
   - `ebay.psa{7,8,9,10}.avg` (dollars, float) → `psa_{7,8,9,10}_price_cents`.
   - `priceHistory[]` → array of `{ts, price_cents}`. Verify field names in plan probe (`date` vs `ts`, `price` vs `value`).
   - `headline_price_cents = pickTier(ebay, grading_service, grade)` — returns null for BGS/CGC/SGC.
4. If first-time match (we used `search`): upsert `ppt_tcgplayer_id` + `ppt_url` onto `graded_card_identities`.
5. Upsert one `graded_market` row for `(identity_id, grading_service, grade)` with all per-tier columns + `ppt_tcgplayer_id`, `ppt_url`, `price_history` (JSONB), `source = 'pokemonpricetracker'`, `updated_at = now()`.
6. Return response payload built from the upserted row (cache-hit and live-fetch responses are byte-identical in shape).

All writes use the service-role Supabase client.

## Failure modes

| Class | Behavior |
|---|---|
| PPT 5xx / network error | If `graded_market` row exists (even stale), return it with `is_stale_fallback: true` and log. If no cache, `503 UPSTREAM_UNAVAILABLE`. Client outbox retries. |
| PPT 429 rate-limit | Same as 5xx; additionally pause all live fetches in this isolate for 60 seconds (module-scope timestamp). |
| PPT 401 / 403 | `502 AUTH_INVALID`. Log at ERROR (token issue). No retry beyond one. |
| Search returns zero hits | `404 PRODUCT_NOT_RESOLVED`. No persistence. |
| Top hit returns a card with no PSA-tier averages and no `prices.market` | `404 NO_MARKET_DATA`. Identity is updated with the resolved id (so a future refresh can work without a re-search). |
| Requested grade tier missing, others present | Respond 200 with `headline_price_cents: null` and the ladder populated. iOS renders the headline cell as `—` with a caveat row. |
| Every tier missing AND `loose_price` missing | `404 NO_MARKET_DATA`. iOS empty-state branch renders. |
| Requested grader is BGS/CGC/SGC/TAG | `headline_price_cents: null`. The ladder still renders Raw + PSA 7/8/9/10 if available. iOS caveat row says "Pokemon Price Tracker doesn't publish BGS/CGC/SGC prices — showing the PSA ladder for cross-reference." |
| Cached id refers to a deleted PPT card | Live fetch returns 404 / empty array → return `404 NO_MARKET_DATA` and clear the cached id on the identity row so the next scan re-runs search. |
| `priceHistory` empty / missing for a card we have prices for | Sparkline section hides; rest of the card renders normally. Not an error. |

## iOS changes

### `CompCardView`

- **Hero row** — headline price (`headlinePriceCents`) + a small kicker showing `<grader> <grade>`. The kicker no longer mentions the data source explicitly; it's referenced once in the footer. Cleaner card.
- **Sparkline rail** — new SwiftUI `Path`-based mini-chart between the hero and the ladder, drawn from `priceHistory`. ~32pt tall, no axis labels, accent stroke in `AppColor.gold`. Hides when `priceHistory` is empty / missing.
- **Grade ladder rail** — horizontal scroll of cells: Raw / PSA 7 / PSA 8 / PSA 9 / PSA 10. Cells render only for non-null tiers. The cell matching `(grading_service, grade)` (only for PSA) gets a gold border. Empty list (every tier null) hides the rail entirely.
- **Caveat row** — handles two cases: `isStaleFallback` (existing) and "non-PSA grader requested" (new copy: "Showing PSA tiers — Pokemon Price Tracker doesn't publish BGS/CGC/SGC prices.").
- **Footer** — "Powered by Pokemon Price Tracker · View card →" deep-links to `pptURL`. Source attribution lives here, not in the hero kicker.

### `ScanDetailView`

- Empty/loading/error copy updates:
  - `fetchingState`: "Fetching Pokemon Price Tracker comp…"
  - `noDataState`: "Pokemon Price Tracker has no comp for this slab yet."
  - `productNotResolvedState`: "We couldn't find this card on Pokemon Price Tracker."
  - `failedState`: "Pokemon Price Tracker lookup unavailable."
- `valueSection` and the `fallbackContent` state machine are unchanged.

### `CompRepository`

- `Wire` / `Decoded` reshape to match the new payload (PSA-only tiers, `ppt_*` fields, `price_history` array, no `pricecharting_*`, no `bgs_10_*` / `cgc_10_*` / `sgc_10_*`, no `grade_9_5_*`, no `grade_7_*` / `grade_8_*` / `grade_9_*`).
- `Error` cases unchanged in shape (`noMarketData`, `productNotResolved`, `identityNotFound`, `authInvalid`, `upstreamUnavailable`, `httpStatus`, `decoding`). Only the internal source-name semantics shift.

### `CompFetchService`

- `persistSnapshot` reshapes to write the new tier columns + `priceHistoryJSON`.
- In-flight tracking, `flipMatching`, the absorber pattern, and the state-machine flips are unchanged. The `(identityId, service, grade)` cache key still de-dupes parallel scans.
- `classify` updates user-facing copy strings (s/PriceCharting/Pokemon Price Tracker/g).

### `LotDetailView`

- Already reads `headlinePriceCents` and totals across scans — no changes needed beyond a type-check after `GradedMarketSnapshot` reshape.

### Outbox

`OutboxKind.priceCompJob` and the retry/backoff in the outbox driver are unchanged.

## Files: delete / rewrite / add

### Delete

- `supabase/functions/price-comp/pricecharting/` (entire directory: `client.ts`, `parse.ts`, `product.ts`, `search.ts`)
- `supabase/functions/price-comp/__fixtures__/` PriceCharting fixture subdirectory (if present)
- `supabase/functions/price-comp/lib/grade-key.ts` is **rewritten** (PSA-only mapping), not deleted

### Rewrite

- `supabase/functions/price-comp/index.ts` — new orchestrator (single live-fetch path, no two-call dance)
- `supabase/functions/price-comp/types.ts` — new request/response/internal types (`ppt_*`, PSA-only tiers, `price_history`)
- `supabase/functions/price-comp/persistence/market.ts` — write per-tier columns + JSONB price_history
- `supabase/functions/price-comp/persistence/identity-product-id.ts` — rename helpers `persistIdentity{TCGPlayerId,Url}` / `clearIdentity{TCGPlayerId,Url}`; column rename
- `supabase/functions/price-comp/cache/freshness.ts` — same logic, no behavioral change
- `supabase/functions/price-comp/lib/grade-key.ts` — map `(GradingService, grade)` to `psa_{n}_price` only; non-PSA returns null
- `supabase/functions/price-comp/__tests__/` — updated unit + integration tests
- `ios/slabbist/slabbist/Features/Comp/CompCardView.swift` — sparkline + ladder reshape + footer copy
- `ios/slabbist/slabbist/Features/Comp/CompRepository.swift` — Wire / Decoded reshape
- `ios/slabbist/slabbist/Features/Comp/CompFetchService.swift` — `persistSnapshot` + `classify`
- `ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift` — copy updates only
- `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift` — model reshape
- `ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift` — assertions against new payload
- `ios/slabbist/slabbistTests/Features/Comp/CompFetchServiceTests.swift` — Decoded shape; in-flight de-dup test stays

### Add

- `supabase/functions/price-comp/ppt/client.ts` — fetch helper, Bearer auth, `X-API-Version: v1`, retry-once-on-401, rate-limit pause
- `supabase/functions/price-comp/ppt/cards.ts` — `fetchCard({ search?, tcgPlayerId? })` wrapper
- `supabase/functions/price-comp/ppt/parse.ts` — dollars-float → cents-int, ebay-tier extraction, history-array normalization, headline-tier picker, deep-link URL derivation
- `supabase/functions/price-comp/__fixtures__/ppt/` — canned responses for tests (live capture during the plan probe)
- `supabase/migrations/20260506120000_drop_pricecharting_columns_from_identities.sql`
- `supabase/migrations/20260506120100_drop_pricecharting_columns_from_market.sql`
- `supabase/migrations/20260506120200_add_ppt_columns_to_identities.sql`
- `supabase/migrations/20260506120300_add_ppt_columns_to_market.sql`
- `ios/slabbist/slabbist/Features/Comp/CompSparklineView.swift` — small Path-based sparkline component
- `ios/slabbist/slabbist/Core/Models/PriceHistoryPoint.swift` — value type, JSON-decodable

Migration filenames are split per-concern so the implementation plan can sequence the drop / add cleanly and roll back independently if needed. Memory note `feedback_supabase_migration_ledger`: when `supabase db push` errors with `relation already exists`, INSERT into `supabase_migrations.schema_migrations` rather than re-running DDL.

## Testing strategy

### Edge Function unit (Deno, inside the function's test file)

- **PPT client**:
  - `Authorization: Bearer <token>` and `X-API-Version: v1` headers attached.
  - Dollar-float prices parsed correctly (e.g., `17.32` → `1732`).
  - Missing `ebay.psaN.avg` field → `null`.
  - `401` triggers single retry then surfaces as `AUTH_INVALID`.
  - `429` triggers in-isolate pause flag.
- **Hybrid match**:
  - Cached `tcgPlayerId` path skips search (uses `?tcgPlayerId=`).
  - Missing id path uses `?search=`.
  - Zero-hit search returns `PRODUCT_NOT_RESOLVED`, no persistence.
  - First-time match persists `ppt_tcgplayer_id` + `ppt_url` onto identity.
- **Grade → tier mapping**:
  - `(PSA, "10")` → `psa_10_price`
  - `(PSA, "9")` → `psa_9_price`
  - `(PSA, "8")` → `psa_8_price`
  - `(PSA, "7")` → `psa_7_price`
  - `(BGS, "10")` → headline null, ladder populated
  - `(CGC, "10")` → headline null
  - `(SGC, "10")` → headline null
  - `(PSA, "9.5")` → headline null in v1 (PPT does not publish a `psa_9_5` field) — verify in plan probe; if PPT does publish it, fold into the column set before code lands
- **Cache freshness**: fresh / stale / missing branches; stale + upstream-up → live; stale + upstream-down → cached + `is_stale_fallback`.
- **History parsing**: well-formed array → cents-int points, malformed entries dropped, empty array → empty array (not null).

### Edge Function integration

- Local mock PPT server (Deno `serve` returning canned fixtures from `__fixtures__/ppt/`).
- Seeded `graded_card_identities`; assert one `graded_market` row with full ladder + history JSONB.
- Cache-hit path: second call within TTL returns `cache_hit: true` without hitting the mock.
- Stale-fallback path: mock 500; assert `is_stale_fallback: true` and stale payload returned.
- Identity-tcgplayer-id stickiness: first call persists id; second call uses `?tcgPlayerId=` not `?search=`.

### iOS (Swift Testing)

- Decode tests for the full new payload (all PSA tiers populated, partial tiers, headline-null for BGS, missing `priceHistory`, missing `ppt_url`).
- `CompFetchService.persistSnapshot` writes the right tier columns + `priceHistoryJSON`.
- `CompFetchService` flip-matching unchanged — same in-flight de-dup behavior.
- `CompCardView` snapshot tests: full ladder, partial ladder, sparkline-present, sparkline-empty, headline-null caveat row, gold-border placement on PSA tier.
- Migration test: existing SwiftData store with old `GradedMarketSnapshot` rows opens cleanly under the new schema (destructive seed if lightweight migration not feasible).

### Manual end-to-end

- One simulator flow on a known PSA 10 (e.g., Charizard Base Set) to verify live path → ladder → sparkline → deep-link.
- One simulator flow on a known PSA 9 to verify the PSA 9 tier mapping.
- One simulator flow on a known BGS 10 to verify headline-null + caveat row + ladder still renders.
- One simulator flow on a never-seen identity to verify search → tcgPlayerId persistence → second scan uses `?tcgPlayerId=`.
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
  "matched": "cached_id" | "searched" | "unresolved",
  "ppt_tcgplayer_id": "243172",
  "headline_present": true,
  "history_points": 28,
  "is_stale_fallback": false,
  "credits_consumed": 3,
  "response_time_ms": 412
}
```

Plus targeted error markers: `ppt.auth_invalid`, `ppt.upstream_5xx`, `ppt.match.first_resolved`, `ppt.match.zero_hits`, `ppt.product.no_prices`, `ppt.history.parse_failed`. The `credits_consumed` field reads from PPT's `X-API-Calls-Consumed` response header so we can graph daily spend without leaving Supabase Logs.

## Security

- The PPT API token is server-only via `POKEMONPRICETRACKER_API_TOKEN`. Never returned to iOS, never logged, never embedded in error responses.
- Rotate via the PPT account dashboard + `supabase secrets set` — no redeploy.
- No end-user credentials are involved; PPT access is application-scoped.

## Open follow-ups (for implementation plan or post-launch)

- Plan probe step (mandatory): hit `GET /api/v2/cards?search=charizard&limit=1&includeEbay=true&includeHistory=true&days=180&maxDataPoints=30` against production PPT, capture the response, and reconcile this spec's field names against the live shape before coding. Save the capture as the first `__fixtures__/ppt/` fixture.
- A "force-rematch" UX so a user can correct a wrong cached `ppt_tcgplayer_id` without DB access.
- Pre-warm cron in the scraper for the highest-scanned identities — drops cold-path latency to zero. Reserved.
- Tune `POKEMONPRICETRACKER_FRESHNESS_TTL_SECONDS` against observed re-scan cadence and credit telemetry.
- Verify PSA 9.5 availability on PPT; if present, fold `psa_9_5_price` back into the column set in v1.1.
- Decide whether to persist PSA 1–6 columns for future ladder expansion or to keep YAGNI scope.
- Decide whether to drop `low_price` / `median_price` / `high_price` from `graded_market` entirely (depends on remaining consumers — verify in plan).

## Cross-cutting references

- Superseded PriceCharting comp spec: [`2026-05-05-pricecharting-comp-design.md`](./2026-05-05-pricecharting-comp-design.md)
- Superseded eBay comp spec: [`2026-04-23-ebay-sold-listings-comp-design.md`](./2026-04-23-ebay-sold-listings-comp-design.md)
- Parent comp spec (still authoritative for outbox, cert lookup, and overall comp lifecycle): [`2026-04-22-bulk-scan-comp-design.md`](./2026-04-22-bulk-scan-comp-design.md)
- Pokemon Price Tracker API documentation: <https://www.pokemonpricetracker.com/docs>
- Raw/graded decoupling memory note — this feature stays fully inside the graded domain.
- Movers feature (separate eBay surface, unaffected by this change): `Features/Movers/`, `mover_ebay_listings`, `ebay-account-deletion` webhook.
