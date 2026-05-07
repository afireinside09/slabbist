# Pokemon Price Tracker Comp — Design Spec

**Sub-project:** #4 (Comp engine v1) — replatform
**Date:** 2026-05-06
**Status:** Design draft, revised; awaiting user review
**Supersedes:** [`2026-05-05-pricecharting-comp-design.md`](./2026-05-05-pricecharting-comp-design.md) for the scan-time comp path

## Update history

- **2026-05-07 r3** — Reconciled with live API probe (fixture: `supabase/functions/price-comp/__fixtures__/ppt/charizard-base-set.json`). Changed: (1) response is a wrapper object `{ data: [...], metadata: {...} }`, not a bare array; (2) graded-price path is `ebay.salesByGrade.{key}`, not `ebay.grades.{key}`; (3) grade keys are compact camelCase-ish (`psa10`, `psa9`, `bgs10`, `cgc10`, `sgc10`, `ungraded`) not snake_case — `raw` is `ungraded`; `psa9_5` not observed on this card; (4) per-grade value is a rich object — use `salesByGrade[key].smartMarketPrice.price` (float USD) as the headline price; (5) `priceHistory` is a nested dict, not a flat `{date, price}` array — graded history lives at `ebay.priceHistory.{gradeKey}` as a date-keyed dict of daily aggregates; TCGPlayer history at `priceHistory.conditions.{condition}.history[]` as `{date, market, volume}` items; (6) canonical URL field is `tcgPlayerUrl` (a TCGPlayer link, not a PPT page) — no `ppt_url` field exists on the card; `ppt_url` column will store `tcgPlayerUrl`; (7) `X-API-Calls-Consumed` header absent — actual credit header is `x-ratelimit-daily-remaining`; (8) token on probe is free-plan (100 calls/day, 3-day history) — production plan ($9.99/mo, 20k/day, 6-month history) must be activated before launch.
- **2026-05-06 r2** — Original draft scoped the ladder to PSA-only based on a partial reading of PPT's docs. PPT in fact publishes cross-grader eBay sales averages under `ebay.grades.{psa_10, psa_9_5, bgs_10, cgc_10, sgc_10, raw, …}`. Spec revised to restore BGS/CGC/SGC headline support and the cross-grader ladder rail; "non-PSA → null headline + caveat" plumbing removed throughout.

## Summary

Replaces the PriceCharting-backed `/price-comp` Edge Function with a Pokemon Price Tracker (PPT) backed equivalent. PriceCharting just landed (2026-05-05) but is being ripped out: PPT's API is significantly cheaper at our scan volume, exposes a Pokémon-native data model (PSA / BGS / CGC / SGC tiers + a TCGPlayer raw price, all sourced from real eBay sales), and ships a 6-month price history in the same call we use for the headline. Everything PriceCharting-specific in the function, the database, and the iOS client is removed; no compatibility shims. The `/price-comp` URL, the iOS outbox kind, and the overall hybrid match-then-cache architecture are preserved.

v1 ships the same ladder shape we already display: Raw + PSA 7/8/9/9.5/10 + BGS 10 + CGC 10 + SGC 10 (9 cells). The only behavioral upgrade is a 6-month sparkline drawn from PPT's `priceHistory` payload, which is inlined in the same call as the prices.

## Goals

1. A scan of a graded Pokémon card returns a defensible comp in one round-trip using PPT as the source of truth.
2. The iOS-facing endpoint URL (`/price-comp`) and outbox kind stay unchanged so iOS routing is reused.
3. The headline for any of `(PSA, "7"|"8"|"9"|"9.5"|"10")`, `(BGS, "10")`, `(CGC, "10")`, `(SGC, "10")` resolves from `ebay.salesByGrade.{gradeKey}.smartMarketPrice.price`. Grade key format: `psa7`, `psa8`, `psa9`, `psa9_5`, `psa10`, `bgs10`, `cgc10`, `sgc10`. Raw/loose comes from `prices.market` (fallback: `ebay.salesByGrade.ungraded.smartMarketPrice.price`).
4. A price history sparkline renders in the comp card from PPT's `ebay.priceHistory.{gradeKey}` payload (date-keyed dict, converted to sorted array). Window length depends on plan tier (3 days free; 6 months on paid plan — **paid plan must be active at launch**).
5. A real-listings escape hatch — every comp deep-links to the TCGPlayer product page (`tcgPlayerUrl` field) so users can verify against actual sales. (No PPT-native product page URL is available from the card object.)
6. First-scan latency is amortized by caching the resolved PPT card identifier on the identity row (one search per identity, ever).
7. PriceCharting scaffolding installed yesterday (Edge Function code, secrets, schema columns, identity-row columns, iOS model fields) is removed cleanly.

## Non-goals

- TAG headline values in v1. The probe showed PPT does publish TAG sales (`tag7`, `tag8`, `tag9` keys in `salesByGrade`) but v1 does not map those to headline/ladder cells. A `(TAG, *)` request returns `headline_price_cents: null` with the rest of the ladder populated; iOS shows the caveat row. TAG support can be added in v1.1 by extending the grade-key mapping.
- Sub-PSA-7 tiers in v1 (PSA 1–6). Persist + display Raw + PSA 7/8/9/9.5/10 + BGS 10 + CGC 10 + SGC 10 — the same nine-cell shape today's UI already supports.
- Non-PSA half-grades (BGS 9.5, CGC 9.5, SGC 9.5) in v1, even though PPT may publish them. Reserved for v1.1 once we know the data is reliably populated.
- Sparkline pre-warm via the scraper. v1 fetches history on demand inside the existing live-fetch path.
- A "force-rematch" UX for correcting a wrong cached PPT card id. Reserved as a follow-up.
- Bulk pre-warming the popular-watchlist via `POST /api/v2/cards/bulk-price`. Reserved for v1.1 if cost telemetry justifies it.
- Non-Pokémon catalogs.
- Dev / sandbox PPT environment wiring — production only for MVP.

## API surface (Pokemon Price Tracker)

Authoritative reference: <https://www.pokemonpricetracker.com/docs#model/ebaydata>. All field names quoted in this spec are best-effort from public documentation pages and search results; the implementation plan **must** include a probe step that hits the live API with the issued token and fixes any field-name drift in this spec before code lands.

- Base URL: `https://www.pokemonpricetracker.com`
- Auth: `Authorization: Bearer <token>`. Header `X-API-Version: v1` (per docs).
- Plan: API tier ($9.99/mo, 20k credits/day, 60 calls/min, 6-month history).
- Endpoint we use: `GET /api/v2/cards`
  - Two query modes:
    - **Cold path (no cached id):** `?search=<built query>&limit=1&includeEbay=true&includeHistory=true&days=180&maxDataPoints=30`
    - **Warm path (cached id):** `?tcgPlayerId=<id>&includeEbay=true&includeHistory=true&days=180&maxDataPoints=30`
  - Response is a wrapper object `{ data: [card, …], metadata: { total, count, limit, … } }`. The parser takes `data[0]`. Each card carries:
    - `tcgPlayerId` — the stable identifier we cache on the identity row
    - `name`, `setName`, `cardNumber`
    - `tcgPlayerUrl` — TCGPlayer product page URL (e.g. `https://www.tcgplayer.com/product/42479`); this is the canonical URL we store in the `ppt_url` column (no PPT-native product page URL exists on the card object)
    - `prices.market` — TCGPlayer market in dollars (float); primary source for `loose_price_cents` (raw)
    - `ebay` — graded eBay sales aggregate with shape:
      ```jsonc
      "ebay": {
        "salesByGrade": {
          "ungraded": { "count": 56, "averagePrice": 418.44, "smartMarketPrice": { "price": 288.24, "confidence": "medium", … } },
          "psa7":     { "count": 14, "averagePrice": 390.86, "smartMarketPrice": { "price": 420.38, "confidence": "low",    … } },
          "psa8":     { "count": 10, "averagePrice": 704.17, "smartMarketPrice": { "price": 600.00, "confidence": "medium", … } },
          "psa9":     { "count":  2, "averagePrice": 818.19, "smartMarketPrice": { "price": 1190.00,"confidence": "low",    … } },
          // "psa9_5", "psa10", "bgs10", "cgc10", "sgc10" appear when PPT has sales for those tiers
          // key names are compact: psa10 not psa_10, bgs10 not bgs_10, ungraded not raw
          // additional keys may appear: psa1..psa6, bgs4..bgs8, cgc2..cgc8, sgc8, tag7..tag9 — ignored in v1
        },
        "priceHistory": {
          // keyed by grade string (same keys as salesByGrade)
          // each value is a date-keyed dict of daily aggregates (may be empty {} when no data in window)
          "psa9": {
            "2026-05-05": { "average": 1190.0, "count": 1, "totalValue": 1190.0, … }
          },
          "psa8": { /* … */ }
        },
        "totalSales": 139,
        "gradesTracked": ["psa7", "psa8", "psa9", "ungraded", …]
      }
      ```
      The price to use for each tier is `salesByGrade[key].smartMarketPrice.price` (float USD).
    - `priceHistory` (top-level, TCGPlayer) — object with `conditions.{condition}.history[]` entries of `{date, market, volume}`; limited to the plan's history window. For the graded sparkline we use `ebay.priceHistory.{gradeKey}` instead (date-keyed dict → convert to sorted `{date, price_cents}[]`).
- Rate-limit headers: `x-ratelimit-daily-remaining` and `x-ratelimit-daily-limit` (confirmed in probe). No `X-API-Calls-Consumed` header — the observability log field `credits_consumed` should be derived from the plan tier (3 credits per call) rather than read from headers.
- Plan requirements: the live probe confirmed the token is currently on the **free plan** (100 calls/day, 3-day history window). The $9.99/mo API plan (20k calls/day, 6-month history) **must be activated** before production launch. Credit cost per fresh fetch on the paid plan: **3 credits** (1 base + 1 `includeHistory` + 1 `includeEbay`). At 20k/day → ~6,600 fresh fetches/day; with the 24h cache TTL, vastly more scans.
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
                 ├─ extract (from data[0]):
                 │     ├─ loose_price_cents          ← prices.market * 100  (fallback: ebay.salesByGrade.ungraded.smartMarketPrice.price * 100)
                 │     ├─ psa_7..psa_9_price_cents   ← ebay.salesByGrade.psa{n}.smartMarketPrice.price * 100
                 │     ├─ psa_9_5_price_cents        ← ebay.salesByGrade.psa9_5.smartMarketPrice.price * 100  (if key present)
                 │     ├─ psa_10_price_cents         ← ebay.salesByGrade.psa10.smartMarketPrice.price * 100
                 │     ├─ bgs_10_price_cents         ← ebay.salesByGrade.bgs10.smartMarketPrice.price * 100
                 │     ├─ cgc_10_price_cents         ← ebay.salesByGrade.cgc10.smartMarketPrice.price * 100
                 │     ├─ sgc_10_price_cents         ← ebay.salesByGrade.sgc10.smartMarketPrice.price * 100
                 │     ├─ price_history              ← sortedEntries(ebay.priceHistory[gradeKey]).map({date, cents})
                 │     ├─ headline_price_cents       ← pickTier(ebay.salesByGrade, grading_service, grade)
                 │     └─ ppt_url                    ← tcgPlayerUrl (TCGPlayer product page; no PPT-native URL)
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

PPT publishes per-(grader, grade) eBay-sales averages under `ebay.grades.{key}`. The v1 ladder mirrors the nine-cell shape the current iOS UI already supports: Raw + PSA 7/8/9/9.5/10 + BGS 10 + CGC 10 + SGC 10. The PriceCharting-era generic `grade_7/8/9/9_5_price` columns (which were "any grader at this grade") are replaced by PSA-specific columns; `bgs_10_price`, `cgc_10_price`, `sgc_10_price` carry over with their existing semantics. PSA 1–6 and non-PSA half-grades are lost data we can re-introduce in v1.1 by a column-addition migration if signal warrants.

```sql
alter table public.graded_market
  drop column if exists pricecharting_product_id,
  drop column if exists pricecharting_url,
  drop column if exists grade_7_price,
  drop column if exists grade_8_price,
  drop column if exists grade_9_price,
  drop column if exists grade_9_5_price;

alter table public.graded_market
  add column if not exists ppt_tcgplayer_id text,
  add column if not exists ppt_url          text,
  add column if not exists psa_7_price      numeric(12,2),
  add column if not exists psa_8_price      numeric(12,2),
  add column if not exists psa_9_price      numeric(12,2),
  add column if not exists psa_9_5_price    numeric(12,2),
  add column if not exists price_history    jsonb;

-- Source column already exists from the PriceCharting migration; flip default
-- and existing rows. After this migration there are no PriceCharting rows.
update public.graded_market set source = 'pokemonpricetracker' where source = 'pricecharting';
alter table public.graded_market alter column source set default 'pokemonpricetracker';
```

The implementation plan must verify whether any non-comp consumer reads `low_price` / `median_price` / `high_price`. If nothing else reads them, drop them in this migration as well; if a consumer remains, leave them and have the new code write `low_price = high_price = median_price = headline_price`. Default is to drop, mirroring the previous spec's stance.

`psa_10_price`, `bgs_10_price`, `cgc_10_price`, `sgc_10_price`, and `loose_price` already exist from yesterday's PriceCharting migration; this migration leaves them in place and only swaps their write-source from PriceCharting product fields to PPT `ebay.grades.{key}` fields.

### Migration: drop PriceCharting secret variables (handled outside SQL)

Not a SQL migration — listed in the secrets section below.

### iOS SwiftData

`GradedMarketSnapshot` reshape:

- Remove: `grade7PriceCents`, `grade8PriceCents`, `grade9PriceCents`, `grade9_5PriceCents`, `pricechartingProductId`, `pricechartingURL`.
- Add: `psa7PriceCents`, `psa8PriceCents`, `psa9PriceCents`, `psa9_5PriceCents` (Int64?); `pptTCGPlayerId` (String?), `pptURL` (URL?), `priceHistoryJSON` (String?).
- Keep: `id`, `identityId`, `gradingService`, `grade`, `headlinePriceCents`, `loosePriceCents`, `psa10PriceCents`, `bgs10PriceCents`, `cgc10PriceCents`, `sgc10PriceCents`, `fetchedAt`, `cacheHit`, `isStaleFallback`.

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
  "headline_price_cents":  18500,    // tier price for the requested (grader, grade); null only if PPT has no value for that exact tier
  "grading_service":       "PSA",
  "grade":                 "10",

  "loose_price_cents":      400,
  "psa_7_price_cents":     2400,
  "psa_8_price_cents":     3400,
  "psa_9_price_cents":     6800,
  "psa_9_5_price_cents":  11200,
  "psa_10_price_cents":   18500,
  "bgs_10_price_cents":   21500,
  "cgc_10_price_cents":   16800,
  "sgc_10_price_cents":   16500,

  "price_history": [
    { "ts": "2025-11-08T00:00:00Z", "price_cents": 16200 },
    { "ts": "2025-11-15T00:00:00Z", "price_cents": 16850 },
    /* up to ~30 points across 180 days */
  ],

  "ppt_tcgplayer_id":     "243172",
  "ppt_url":              "https://www.tcgplayer.com/product/243172",  // tcgPlayerUrl from PPT response (no PPT-native product page URL)

  "fetched_at":           "2026-05-06T15:14:03Z",
  "cache_hit":            false,
  "is_stale_fallback":    false
}
```

A null `headline_price_cents` does **not** put iOS into the empty-state branch — the snapshot is still resolved (`compFetchState = .resolved`) and the ladder still renders any non-null tiers. The hero number renders `—` with a small caveat row ("Pokemon Price Tracker has no PSA 10 sales for this card yet — showing the rest of the ladder."). The empty-state branch fires only when every tier and `loose_price` are null, which the Edge Function returns as `404 NO_MARKET_DATA`.

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
3. Single `GET /api/v2/cards?...&includeEbay=true&includeHistory=true`. Response is `{ data: [card], metadata: {...} }`; take `data[0]`. Parse:
   - `prices.market` (dollars, float) → `loose_price_cents` (cents, int). Fallback to `ebay.salesByGrade.ungraded.smartMarketPrice.price` if `prices.market` is missing.
   - `ebay.salesByGrade.{psa7|psa8|psa9|psa9_5|psa10|bgs10|cgc10|sgc10}.smartMarketPrice.price` (dollars, float) → matching `*_price_cents` columns. Key is absent when PPT has no sales for that tier.
   - `ebay.priceHistory.{gradeKey}` (date-keyed dict) → sorted `{ts, price_cents}` array for the requested grade. Empty dict or absent key → empty array (not an error).
   - `headline_price_cents = pickTier(ebay.salesByGrade, grading_service, grade)` — picks the entry matching `(grader, grade)`. Grade key mapping: PSA → `psa{n}`, BGS 10 → `bgs10`, CGC 10 → `cgc10`, SGC 10 → `sgc10`. Returns null only when the key is absent (no sales for that tier) or when the requested `(grader, grade)` is outside the v1 column set (TAG, sub-PSA-7, non-PSA half-grades).
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
| Top hit returns a card with no `ebay.salesByGrade` keys and no `prices.market` | `404 NO_MARKET_DATA`. Identity is updated with the resolved id (so a future refresh can work without a re-search). |
| Requested tier key present in `ebay.salesByGrade` but `smartMarketPrice.price` is null/zero | Treated as missing. Respond 200 with `headline_price_cents: null` and the ladder populated. iOS renders the headline cell as `—` with a caveat row. |
| Requested `(grader, grade)` outside the v1 column set (TAG, PSA 1–6, non-PSA half-grades) | `headline_price_cents: null`; the rest of the ladder still renders. iOS caveat row says "Pokemon Price Tracker hasn't logged sales for `<grader> <grade>` yet — showing the rest of the ladder." |
| Every tier missing AND `loose_price` missing | `404 NO_MARKET_DATA`. iOS empty-state branch renders. |
| Cached id refers to a deleted PPT card | Live fetch returns 404 / empty array → return `404 NO_MARKET_DATA` and clear the cached id on the identity row so the next scan re-runs search. |
| `priceHistory` empty / missing for a card we have prices for | Sparkline section hides; rest of the card renders normally. Not an error. |

## iOS changes

### `CompCardView`

- **Hero row** — headline price (`headlinePriceCents`) + a small kicker showing `<grader> <grade>`. The kicker no longer mentions the data source explicitly; it's referenced once in the footer. Cleaner card.
- **Sparkline rail** — new SwiftUI `Path`-based mini-chart between the hero and the ladder, drawn from `priceHistory`. ~32pt tall, no axis labels, accent stroke in `AppColor.gold`. Hides when `priceHistory` is empty / missing.
- **Grade ladder rail** — horizontal scroll of cells (in this order): Raw / PSA 7 / PSA 8 / PSA 9 / PSA 9.5 / PSA 10 / BGS 10 / CGC 10 / SGC 10. Cells render only for non-null tiers. The cell matching `(grading_service, grade)` gets a gold border (works for any of the supported `(grader, grade)` pairs). Empty list (every tier null) hides the rail entirely.
- **Caveat row** — surfaces in three cases: (a) `isStaleFallback`, (b) requested `(grader, grade)` is outside the v1 column set (TAG / PSA 1–6 / non-PSA half-grade) so headline is `null` but the ladder is otherwise populated, (c) requested tier is in the column set but PPT had no value for it. Copy variants handle each case with one-liners; no PSA-only language.
- **Footer** — "Powered by Pokemon Price Tracker · View card →" deep-links to `pptURL`. Source attribution lives here, not in the hero kicker.

### `ScanDetailView`

- Empty/loading/error copy updates:
  - `fetchingState`: "Fetching Pokemon Price Tracker comp…"
  - `noDataState`: "Pokemon Price Tracker has no comp for this slab yet."
  - `productNotResolvedState`: "We couldn't find this card on Pokemon Price Tracker."
  - `failedState`: "Pokemon Price Tracker lookup unavailable."
- `valueSection` and the `fallbackContent` state machine are unchanged.

### `CompRepository`

- `Wire` / `Decoded` reshape to match the new payload: drop `pricecharting_*`, drop the generic `grade_7_*` / `grade_8_*` / `grade_9_*` / `grade_9_5_*` slots, add per-PSA fields `psa_7_price_cents`, `psa_8_price_cents`, `psa_9_price_cents`, `psa_9_5_price_cents`, add `ppt_tcgplayer_id`, `ppt_url`, `price_history` array. Keep `psa_10_price_cents`, `bgs_10_price_cents`, `cgc_10_price_cents`, `sgc_10_price_cents`, `loose_price_cents`.
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
- `supabase/functions/price-comp/lib/grade-key.ts` is **rewritten** (maps `(grader, grade)` to a column key in the new PSA + BGS/CGC/SGC set), not deleted

### Rewrite

- `supabase/functions/price-comp/index.ts` — new orchestrator (single live-fetch path, no two-call dance)
- `supabase/functions/price-comp/types.ts` — new request/response/internal types (`ppt_*`, the cross-grader tier set, `price_history`)
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
  - Missing `ebay.grades.{key}` entry → `null`.
  - `401` triggers single retry then surfaces as `AUTH_INVALID`.
  - `429` triggers in-isolate pause flag.
- **Hybrid match**:
  - Cached `tcgPlayerId` path skips search (uses `?tcgPlayerId=`).
  - Missing id path uses `?search=`.
  - Zero-hit search returns `PRODUCT_NOT_RESOLVED`, no persistence.
  - First-time match persists `ppt_tcgplayer_id` + `ppt_url` onto identity.
- **Grade → tier mapping**:
  - `(PSA, "10")` → `psa_10_price`
  - `(PSA, "9.5")` → `psa_9_5_price`
  - `(PSA, "9")` → `psa_9_price`
  - `(PSA, "8")` → `psa_8_price`
  - `(PSA, "7")` → `psa_7_price`
  - `(BGS, "10")` → `bgs_10_price`
  - `(CGC, "10")` → `cgc_10_price`
  - `(SGC, "10")` → `sgc_10_price`
  - `(TAG, *)` → headline null, ladder still populated
  - `(PSA, "6")` and below → headline null, ladder still populated
  - `(BGS|CGC|SGC, "9.5")` → headline null in v1 (deferred to v1.1)
- **Cache freshness**: fresh / stale / missing branches; stale + upstream-up → live; stale + upstream-down → cached + `is_stale_fallback`.
- **History parsing**: well-formed array → cents-int points, malformed entries dropped, empty array → empty array (not null).

### Edge Function integration

- Local mock PPT server (Deno `serve` returning canned fixtures from `__fixtures__/ppt/`).
- Seeded `graded_card_identities`; assert one `graded_market` row with full ladder + history JSONB.
- Cache-hit path: second call within TTL returns `cache_hit: true` without hitting the mock.
- Stale-fallback path: mock 500; assert `is_stale_fallback: true` and stale payload returned.
- Identity-tcgplayer-id stickiness: first call persists id; second call uses `?tcgPlayerId=` not `?search=`.

### iOS (Swift Testing)

- Decode tests for the full new payload (all tiers populated, partial tiers, headline-null for `(TAG, *)`, missing `priceHistory`, missing `ppt_url`).
- `CompFetchService.persistSnapshot` writes the right tier columns + `priceHistoryJSON`.
- `CompFetchService` flip-matching unchanged — same in-flight de-dup behavior.
- `CompCardView` snapshot tests: full ladder, partial ladder, sparkline-present, sparkline-empty, headline-null caveat row, gold-border placement on each of `(PSA, 7..10/9.5)`, `(BGS, 10)`, `(CGC, 10)`, `(SGC, 10)`.
- Migration test: existing SwiftData store with old `GradedMarketSnapshot` rows opens cleanly under the new schema (destructive seed if lightweight migration not feasible).

### Manual end-to-end

- One simulator flow on a known PSA 10 (e.g., Charizard Base Set) to verify live path → full ladder → sparkline → deep-link.
- One simulator flow on a known PSA 9 to verify the PSA 9 tier mapping.
- One simulator flow on a known PSA 9.5 to verify the half-grade column.
- One simulator flow on a known BGS 10 to verify the BGS tier mapping (headline pulls from `bgs_10_price`).
- One simulator flow on a known CGC 10 to verify the CGC tier mapping.
- One simulator flow on a never-seen identity to verify search → tcgPlayerId persistence → second scan uses `?tcgPlayerId=`.
- One simulator flow on a TAG-graded slab to verify headline-null + caveat row + ladder still renders.
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

Plus targeted error markers: `ppt.auth_invalid`, `ppt.upstream_5xx`, `ppt.match.first_resolved`, `ppt.match.zero_hits`, `ppt.product.no_prices`, `ppt.history.parse_failed`. The `credits_consumed` field is hard-coded to 3 (1 base + 1 `includeEbay` + 1 `includeHistory`) — PPT does not return an `X-API-Calls-Consumed` header (probe confirmed). Use `x-ratelimit-daily-remaining` from the response headers for daily-budget monitoring if needed.

## Security

- The PPT API token is server-only via `POKEMONPRICETRACKER_API_TOKEN`. Never returned to iOS, never logged, never embedded in error responses.
- Rotate via the PPT account dashboard + `supabase secrets set` — no redeploy.
- No end-user credentials are involved; PPT access is application-scoped.

## Open follow-ups (for implementation plan or post-launch)

- Plan probe step (mandatory): hit `GET /api/v2/cards?search=charizard&limit=1&includeEbay=true&includeHistory=true&days=180&maxDataPoints=30` against production PPT, capture the response, and reconcile this spec's field names against the live shape before coding. Save the capture as the first `__fixtures__/ppt/` fixture. Specifically verify: (a) the `ebay.grades` key naming (`psa_10` vs `psa10` vs `PSA10`), (b) whether `ebay.grades.psa_9_5` is published for cards with PSA 9.5 sales, (c) the `priceHistory` element shape, (d) the canonical product URL field.
- A "force-rematch" UX so a user can correct a wrong cached `ppt_tcgplayer_id` without DB access.
- Pre-warm cron in the scraper for the highest-scanned identities — drops cold-path latency to zero. Reserved.
- Tune `POKEMONPRICETRACKER_FRESHNESS_TTL_SECONDS` against observed re-scan cadence and credit telemetry.
- v1.1: add columns for non-PSA half-grades (`bgs_9_5_price`, `cgc_9_5_price`, `sgc_9_5_price`) and sub-PSA-7 tiers if signal demands.
- Decide whether to persist a JSONB `ebay_grades_full` blob alongside the enumerated columns to future-proof against schema additions without further migrations.
- Decide whether to drop `low_price` / `median_price` / `high_price` from `graded_market` entirely (depends on remaining consumers — verify in plan).

## Cross-cutting references

- Superseded PriceCharting comp spec: [`2026-05-05-pricecharting-comp-design.md`](./2026-05-05-pricecharting-comp-design.md)
- Superseded eBay comp spec: [`2026-04-23-ebay-sold-listings-comp-design.md`](./2026-04-23-ebay-sold-listings-comp-design.md)
- Parent comp spec (still authoritative for outbox, cert lookup, and overall comp lifecycle): [`2026-04-22-bulk-scan-comp-design.md`](./2026-04-22-bulk-scan-comp-design.md)
- Pokemon Price Tracker API documentation: <https://www.pokemonpricetracker.com/docs>
- Raw/graded decoupling memory note — this feature stays fully inside the graded domain.
- Movers feature (separate eBay surface, unaffected by this change): `Features/Movers/`, `mover_ebay_listings`, `ebay-account-deletion` webhook.
