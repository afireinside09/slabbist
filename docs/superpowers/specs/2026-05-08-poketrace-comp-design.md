# Poketrace Graded-Pricing Integration — Design

**Status:** Draft
**Author:** phil + Claude (brainstorming)
**Date:** 2026-05-08
**Predecessors:** `2026-05-06-pokemonpricetracker-comp-design.md`

## Summary

Add `poketrace.com` as a **second** graded-pricing data source alongside the existing `pokemonpricetracker.com` (PPT) integration. Every scanned slab fans out to both providers in parallel from the existing `price-comp` edge function. The iOS comp screen shows a side-by-side per-source comparison and a **reconciled headline** equal to the average of the two sources. PPT remains the primary source; Poketrace supplements it.

This is purely additive. PPT data, schema, and code paths stay intact.

## Goals

- Capture a second independent valuation for every scanned slab.
- Surface per-source numbers and a reconciled average to the vendor.
- Persist Poketrace's richer dimensions (`avg`/`low`/`high`/`trend`/`confidence`/`saleCount` + rolling windows) without throwing fidelity away.
- Match the existing PPT integration shape so a future third source is cheap to add.

## Non-Goals

- EU / Cardmarket pricing.
- Per-tier history beyond the scanned slab's grade.
- Real-time WebSocket pricing.
- Watchlist-side bulk refresh of Poketrace data (deferred).
- Replacing or deprioritizing PPT.

## Background — Poketrace API

- **Base URL:** `https://api.poketrace.com/v1`
- **Auth:** `X-API-Key: <key>` header (apiKey scheme; OpenAPI 1.7.0).
- **Endpoints used:**
  - `GET /cards?tcgplayer_ids=<id>` — cross-walk a TCGPlayer product id to a Poketrace card UUID.
  - `GET /cards/{id}` — full card detail with `prices: { source: { tier: TierPrice } }`, `gradedOptions`, `topPrice`, `lastUpdated`.
  - `GET /cards/{id}/prices/{tier}/history?period=30d&limit=50` — per-tier price history.
- **Tier keys** are normalized strings: `PSA_10`, `PSA_9_5`, `BGS_10`, `CGC_10`, `SGC_10`, `ACE_10`, `TAG_10`, etc. Format: `<COMPANY>_<GRADE_WITH_DOT_REPLACED_BY_UNDERSCORE>`.
- **`TierPrice` shape:** `avg`, `low`, `high`, `trend` (`up|down|stable`), `confidence` (`high|medium|low`), `saleCount`, `avg1d`, `avg7d`, `avg30d`, `median3d`, `median7d`, `median30d`. Currency is decimal dollars (US market).
- **Rate limits:** documented but not numerically specified at design time. The `x-ratelimit-*` response headers (notably `x-ratelimit-daily-remaining`) drive client-side back-off.

## Architecture

```
                          iOS (CompRepository)
                                  │ POST /price-comp { identity_id, grading_service, grade }
                                  ▼
                        Edge Function: price-comp/index.ts
                                  │
              ┌───────────────────┴───────────────────┐
              ▼                                       ▼
        ppt/ (existing)                       poketrace/ (new)
        client.ts                             client.ts        (X-API-Key)
        cards.ts                              match.ts         (tcgplayer_ids → uuid, cached)
        parse.ts                              prices.ts        (GET /cards/{id})
        match.ts                              history.ts       (30d, scanned tier only)
                                              parse.ts         (TierPrice → DB row)
              │                                       │
              └───────────────► persistence/market.ts ◄──── (extended with `source` arg)
                                          │
                                          ▼
                                    graded_market
                                  (one row per source)
                                          │
                                          ▼
                          Response { ppt, poketrace, reconciled }
                                          │
                                          ▼
                         iOS persists 2 GradedMarketSnapshot rows
                                          │
                                          ▼
                                   CompCardView
                          hero (reconciled avg) + per-source row
```

**Fan-out:** `Promise.allSettled([fetchPPT(), fetchPoketrace()])`. Failures are isolated per source; one provider's error never blocks the other. Per-provider timeout 8s.

**Reconciliation rule:**
- Both succeed → `headline_price_cents = round((ppt.headline + poketrace.avg) / 2)`, `source = 'avg'`.
- Only PPT succeeds → `headline = ppt.headline`, `source = 'ppt-only'`.
- Only Poketrace succeeds → `headline = poketrace.avg`, `source = 'poketrace-only'`.
- Neither succeeds → existing error path (no change).

## Data Model

### Migration

One new file: `supabase/migrations/<ts>_add_poketrace_graded_pricing.sql`.

`graded_card_identities`:
```sql
ALTER TABLE graded_card_identities
  ADD COLUMN poketrace_card_id text NULL;
-- text not uuid: stores '' as a "tried, no match" sentinel; uuid format checked at app layer.
COMMENT ON COLUMN graded_card_identities.poketrace_card_id IS
  'Cached Poketrace card UUID after tcgplayer_ids cross-walk. Empty string = lookup attempted, no match (TTL 7 days).';

ALTER TABLE graded_card_identities
  ADD COLUMN poketrace_card_id_resolved_at timestamptz NULL;
```

`graded_market`:
```sql
-- Source becomes part of the primary key. Today it is (identity_id, grading_service, grade)
-- per the base migration 20260422120000; the system PK constraint is named
-- graded_market_pkey. We drop and recreate.
ALTER TABLE public.graded_market
  DROP CONSTRAINT graded_market_pkey;
ALTER TABLE public.graded_market
  ADD CONSTRAINT graded_market_pkey
  PRIMARY KEY (identity_id, grading_service, grade, source);

-- Poketrace-namespaced columns (only populated for source='poketrace').
ALTER TABLE public.graded_market
  ADD COLUMN pt_avg          numeric(12,2) NULL,
  ADD COLUMN pt_low          numeric(12,2) NULL,
  ADD COLUMN pt_high         numeric(12,2) NULL,
  ADD COLUMN pt_avg_1d       numeric(12,2) NULL,
  ADD COLUMN pt_avg_7d       numeric(12,2) NULL,
  ADD COLUMN pt_avg_30d      numeric(12,2) NULL,
  ADD COLUMN pt_median_3d    numeric(12,2) NULL,
  ADD COLUMN pt_median_7d    numeric(12,2) NULL,
  ADD COLUMN pt_median_30d   numeric(12,2) NULL,
  ADD COLUMN pt_trend        text          NULL CHECK (pt_trend IN ('up','down','stable')),
  ADD COLUMN pt_confidence   text          NULL CHECK (pt_confidence IN ('high','medium','low')),
  ADD COLUMN pt_sale_count   integer       NULL;
```

**Source values:** existing `'pokemonpricetracker'` rows keep their value; new rows use `'poketrace'`. Existing PPT rows are unaffected by the new columns (all nullable).

**Column ownership per source** (all columns nullable; population is by convention):
- `source='pokemonpricetracker'` rows populate: `headline_price`, `loose_price`, `grade_7_price`, `grade_8_price`, `grade_9_price`, `grade_9_5_price`, `psa_7_price`, `psa_8_price`, `psa_9_price`, `psa_9_5_price`, `psa_10_price`, `bgs_10_price`, `cgc_10_price`, `sgc_10_price`, `ppt_tcgplayer_id`, `ppt_url`, `price_history`. The `pt_*` columns stay null.
- `source='poketrace'` rows populate: `headline_price` (= `pt_avg`), all `pt_*` columns, `price_history` (30d for the scanned tier). The PPT-shaped ladder columns and `ppt_*` stay null.

**`headline_price` column** is populated for both sources: PPT writes its headline as before; Poketrace writes `pt_avg` so cross-source aggregation queries stay simple.

**`price_history` (JSONB)** is populated by both sources independently. Poketrace writes the 30d history for the scanned tier in the same `[{ts, price_cents}]` shape PPT uses.

### iOS — `GradedMarketSnapshot` (SwiftData)

Add the same Poketrace columns as optional Swift properties:
```swift
var ptAvgCents: Int64?
var ptLowCents: Int64?
var ptHighCents: Int64?
var ptAvg1dCents, ptAvg7dCents, ptAvg30dCents: Int64?
var ptMedian3dCents, ptMedian7dCents, ptMedian30dCents: Int64?
var ptTrend: String?      // "up" | "down" | "stable"
var ptConfidence: String? // "high" | "medium" | "low"
var ptSaleCount: Int?
var source: String        // "pokemonpricetracker" | "poketrace"
```

The composite uniqueness (now including `source`) needs the SwiftData model's `@Attribute(.unique)` macro updated; one scan persists two snapshots.

## Edge Function Changes

New module tree under `supabase/functions/price-comp/poketrace/`:

- **`client.ts`** — fetch wrapper that injects `X-API-Key`, surfaces rate-limit headers, retries idempotent GETs once on 5xx with 250ms back-off.
- **`match.ts`** — `resolvePoketraceCardId(identity)`:
  1. Read `poketrace_card_id`/`poketrace_card_id_resolved_at` from `graded_card_identities`.
  2. If non-empty → return it. If empty-string sentinel and resolved within 7 days → return `null` (don't re-try).
  3. Otherwise call `GET /cards?tcgplayer_ids=<identity.ppt_tcgplayer_id>&limit=20`. If exactly one result → persist + return. If zero → persist `''` sentinel + return `null`. If multiple → log warning, take first, persist + return.
- **`prices.ts`** — `fetchPoketracePrices(cardId, tierKey)`:
  1. `GET /cards/{cardId}`.
  2. Walk `data.prices` looking for any source object containing `tierKey` (US market data lives under `ebay`).
  3. Return the matched `TierPrice` or `null`.
- **`history.ts`** — `fetchPoketraceHistory(cardId, tierKey, period='30d')`:
  1. `GET /cards/{cardId}/prices/{tierKey}/history?period=30d&limit=50`.
  2. Map each entry's `date` + `avg` → `{ ts: ISO8601, price_cents: round(avg * 100) }`.
- **`parse.ts`** — `tierPriceToMarketRow(tp)` mapping `TierPrice` → DB columns. Dollars→cents conversion at the boundary; missing fields → `null` not `0`.

**Tier key construction** (grade arrives as a string, matching the DB column type):
```ts
const tierKey = `${gradingService.toUpperCase()}_${grade.replace('.', '_')}`;
// 'PSA' + '10'  → 'PSA_10'
// 'PSA' + '9.5' → 'PSA_9_5'
// 'BGS' + '10'  → 'BGS_10'
```

`index.ts` orchestration delta:
```ts
const [pptRes, ptRes] = await Promise.allSettled([
  withTimeout(fetchPPT(identity, gradingService, grade), 8000),
  withTimeout(fetchPoketrace(identity, gradingService, grade), 8000),
]);
const ppt = pptRes.status === 'fulfilled' ? pptRes.value : null;
const pt  = ptRes.status  === 'fulfilled' ? ptRes.value  : null;
const reconciled = reconcile(ppt, pt);
return new Response(JSON.stringify({ ppt, poketrace: pt, reconciled }), ...);
```

`persistence/market.ts` extends `upsertMarketLadder()` to take a `source: 'pokemonpricetracker' | 'poketrace'` argument; one call per provider.

### Response Envelope (new)

```jsonc
{
  "ppt": {
    "headline_price_cents": 12500,
    "psa_7_price_cents": 4200,
    // ...existing PPT shape unchanged...
    "price_history": [{ "ts": "...", "price_cents": 12000 }]
  },
  "poketrace": {
    "card_id": "uuid-...",
    "tier": "PSA_10",
    "avg_cents": 12700,
    "low_cents": 11500,
    "high_cents": 14000,
    "avg_1d_cents": 12700,
    "avg_7d_cents": 12550,
    "avg_30d_cents": 12100,
    "median_3d_cents": 12500,
    "median_7d_cents": 12400,
    "median_30d_cents": 12000,
    "trend": "stable",
    "confidence": "high",
    "sale_count": 42,
    "price_history": [{ "ts": "...", "price_cents": 12100 }]
  },
  "reconciled": {
    "headline_price_cents": 12600,
    "source": "avg"
  },
  "fetched_at": "2026-05-08T12:34:56Z"
}
```

Either `ppt` or `poketrace` may be `null` on partial failure. `reconciled.source` reflects which branches contributed.

## iOS Changes

### `CompRepository.swift`

`Wire`/`Decoded` grow a `poketrace` block + a `reconciled` block:
```swift
struct Wire: Decodable {
  let ppt: PPTBlock?
  let poketrace: PoketraceBlock?
  let reconciled: ReconciledBlock
  let fetched_at: String
}
struct PoketraceBlock: Decodable { /* fields above, snake_case */ }
struct ReconciledBlock: Decodable {
  let headline_price_cents: Int64
  let source: String  // "avg" | "ppt-only" | "poketrace-only"
}
```

`Decoded` adds:
```swift
struct SourceComp {
  let avgCents: Int64?
  let lowCents: Int64?
  let highCents: Int64?
  let saleCount: Int?
  let trend: Trend?       // .up / .down / .stable
  let confidence: Confidence?  // .high / .medium / .low
}
let pptHeadlineCents: Int64?
let poketrace: SourceComp?
let reconciledHeadlineCents: Int64
let reconciledSource: ReconciledSource  // .avg / .pptOnly / .poketraceOnly
```

### `CompFetchService`

No orchestration change — same single call. Splits the response into two `GradedMarketSnapshot` rows (one per source) and writes the reconciled headline onto the `Scan` for fast list rendering.

### `CompCardView.swift`

- **Hero:** reconciled headline (currency-formatted), small caption "avg of 2 sources" / "PPT only" / "Poketrace only".
- **Sources row** (below hero, side-by-side):
  - Left cell: "PPT" header, `$X.XX`, no extra metadata.
  - Right cell: "Poketrace" header, `$Y.YY`, second line `($low–$high)`, third line `n=saleCount` + trend chevron (▲/▼/–), tinted by confidence (high=normal, medium=secondary, low=tertiary).
- **Sparkline:** segmented control "PPT | Poketrace" toggles which history powers the chart. Default: PPT.
- **Missing source:** show the cell with em-dash and "no data" subtitle. Don't hide.

## Error Handling

| Scenario | Behavior |
|---|---|
| Poketrace 401 (bad key) | PPT-only response. Debug builds show a yellow banner; production silently falls back. Logged via existing edge logger. |
| Poketrace 429 / `x-ratelimit-daily-remaining: 0` | Short-circuit Poketrace branch for the rest of the UTC day; PPT-only thereafter. Logged. |
| Poketrace 5xx (after 1 retry) | PPT-only response for this scan. No persistent state change. |
| Cross-walk: 0 results | Persist `poketrace_card_id=''` + `resolved_at=now()`. Re-attempt after 7 days. |
| Cross-walk: >1 result | Take first, log warning. (Tightening rule deferred.) |
| Tier key not present in card detail | `poketrace` block returned with all numeric fields `null`. UI shows "no data" cell. |
| Both providers fail | Existing 502 error path — unchanged. |
| Stale data (TTL exceeded) | Configurable per-source TTL via secrets (`POKETRACE_FRESHNESS_TTL_SECONDS`, default 86400). Same `is_stale_fallback` flag pattern as PPT. |

## Configuration

New Supabase secrets:
- `POKETRACE_API_KEY` — required.
- `POKETRACE_FRESHNESS_TTL_SECONDS` — optional, default `86400`.

Set via `supabase secrets set POKETRACE_API_KEY=...`.

## Testing

### Edge function — Deno tests under `supabase/functions/price-comp/__tests__/poketrace.test.ts`

- Tier-key construction: `('PSA', '9.5')` → `'PSA_9_5'`, `('BGS', '10')` → `'BGS_10'`.
- `parse.ts` rounds `12.34` → `1234` cents; `null`/`undefined` fields → `null`.
- `match.ts`:
  - First call hits the API and persists the UUID.
  - Second call reads from cache, no HTTP.
  - Empty-string sentinel respected within 7 days, re-tried after.
- Reconciliation:
  - Both branches → average + `source='avg'`.
  - PPT only → PPT headline + `source='ppt-only'`.
  - Poketrace only → `pt.avg` + `source='poketrace-only'`.
- Partial failure: one provider throws → other still returns; envelope marks the failed branch `null`.

### iOS — extend `CompRepositoryTests`

- Fixture with both blocks → two snapshots persisted, `reconciled` populated.
- Fixture with `poketrace: null` → only PPT snapshot, hero shows PPT with "PPT only" caption.
- Fixture with `ppt: null` → only Poketrace snapshot, hero shows Poketrace with "Poketrace only" caption.
- `CompCardView` snapshot test (light + dark) for the side-by-side row.

### Manual smoke

Before merge: in dev build, scan a real PSA 10 slab. Verify:
1. Both source cells render with realistic numbers.
2. The hero is exactly the average of the two.
3. Sparkline toggle swaps history sources.
4. Force a Poketrace 401 (bad key) → PPT-only path renders cleanly.

## Rollout

1. Land migration on a dev branch, verify locally with `supabase db push` (consult migration-ledger memory if "already exists" errors appear).
2. Set `POKETRACE_API_KEY` in dev project.
3. Ship edge function. Smoke test on dev project.
4. iOS work on a feature branch — opt-in via existing dev-build flag if any UI risk.
5. Promote to prod project after manual smoke passes.

No feature flag is required: PPT continues working untouched; Poketrace simply appears when the key is configured.

## Open Questions

None blocking. (Confirm with user during planning: should we expose Poketrace `confidence` as a visible badge in v1, or only use it to tint the price text? Current design uses tinting only. Trivial to flip.)
