# Grade Gains Page — Design

**Status:** Draft
**Author:** phil + Claude (brainstorming)
**Date:** 2026-06-01
**Predecessors:** `2026-05-08-poketrace-comp-design.md`, `2026-05-13-poketrace-first-class-fanout-design.md`

## Summary

A new iOS top-level page that ranks raw Pokémon cards by **how much profit a dealer
would make by grading them**: `profit = PSA 10 value − raw market price − grading fee`.
It replicates the Movers tab's filtering and navigation — the same price-band rail
(raw `<$5`, `$5–$25`, `$25–$50`, `$50–$100`, `$100–$200`, `$200+`), the same set
search + rail, the same row/detail flow — but the ranking metric is the **grade-up
spread** instead of price movement.

Graded comps come from **poketrace.com**, resolved in bulk by a new scraper job and
materialized into a new `tcg_grade_comp` table keyed by raw `product_id`. The backfill
prioritizes the **most modern English sets first** (newest `published_on`) and is
resumable across days to respect the ~10k requests/day Poketrace budget.

## Goals

- Surface the highest-margin "raw → PSA 10" grading opportunities across the catalog.
- Match the Movers tab UX 1:1 for filtering (price bands, sets) and navigation.
- Let the dealer adjust the grading fee in-UI; profit recomputes live.
- Bulk-resolve Poketrace PSA 10 comps for modern English cards within a fixed daily
  request budget, resuming where the previous run stopped.
- Honor the raw/graded decoupling rule: the raw↔graded join is materialized in a
  derived table keyed by the raw product, not a FK into the graded identity model.

## Non-Goals

- Japanese cards (English category 3 only for v1; the pipeline is language-agnostic and
  can extend later).
- Expected-value-across-grades modeling (gem-rate weighting) — v1 targets PSA 10 only.
- Graded (PSA 10) **price history** in the detail view — deferred to v2 (budget). v1
  detail shows the **raw** card's existing price history plus the static PSA 10 comp.
- Reusing/altering `graded_card_identities` / `graded_market` — this feature stores its
  comp data independently (see Architecture rationale).
- Real-time pricing, watchlist promotion, or offer-flow integration.

## Background — Poketrace API (confirmed from existing `price-comp/poketrace/`)

- **Base URL:** `https://api.poketrace.com/v1`. **Auth:** `x-api-key: <key>` header.
- **Resolve UUID:** `GET /cards?tcgplayer_ids=<id>&limit=20` → `{ data: [{ id }] }`.
  `tcg_products.product_id` **is** the TCGPlayer id, so resolution needs no prior scan
  or PPT cross-walk. `tcgplayer_ids` is plural — batching multiple ids per call is a
  budget optimization to verify against the live API (see Open Questions).
- **Get price:** `GET /cards/{id}` → `{ data: { prices: { <source>: { <tier>: TierPrice } } } }`.
  `extractPoketraceLadder()` / `extractTierPrice(card, "PSA_10")` already pull the PSA 10
  `avg` in cents. `TierPrice` also carries `trend` (`up|down|stable`), `confidence`
  (`high|medium|low`), `saleCount`. Currency is decimal dollars.
- **Rate limit:** `x-ratelimit-daily-remaining` response header drives the budget guard.
- **Negative-match sentinel:** the existing integration persists `''` when a search
  returns zero results, and re-attempts after 7 days. This pipeline reuses that pattern.

## Architecture

```
  scraper CLI: bun run cli run graded poketrace-comp [--max-requests N]
        │  walk tcg_groups (category 3, English) ORDER BY published_on DESC
        │  → products, skip those resolved < 7d ago
        ▼
  poketrace search (uuid)  →  poketrace detail (PSA_10 avg)
        │  budget guard on x-ratelimit-daily-remaining
        ▼
  UPSERT public.tcg_grade_comp (keyed by product_id)      ← the raw↔graded join
        │
        ▼
  RPCs: get_grade_gain_sets() / get_set_grade_gains(group_id, price_tier)
        │  JOIN tcg_products ⨝ tcg_prices(highest market subtype) ⨝ tcg_grade_comp
        ▼
  iOS: GradeGainsListView (reuses Movers filter components)
        │  fee control → profit = psa10 − raw − fee (client-side)
        ▼
  GradeGainDetailView (raw price history via existing RPC + PSA 10 comp)
```

### Why a new table, not `graded_market` (Approach A)

`tcg_*` and `graded_*` are intentionally decoupled — no FKs, no shared identities;
matching is a consumer-side concern (CLAUDE.md rule 2). This page is fundamentally
**raw-product-centric**: it iterates `tcg_products` and asks "what's the graded comp?".
Materializing that answer in a table keyed by `product_id` *is* the consumer-side join.
Forcing these products into `graded_card_identities` (whose unique key is
`game/language/set_name/card_number/variant`) would be a fuzzy, lossy mapping with more
failure surface, and would couple two subsystems the architecture keeps apart.

## Data Model

New table `public.tcg_grade_comp` — global reference data alongside `tcg_*`
(not tenant-scoped, **no RLS**, matching `tcg_prices`):

| column | type | notes |
|---|---|---|
| `product_id` | `int` PK | references `tcg_products.product_id` conceptually; **no FK** (decoupling) |
| `poketrace_card_id` | `text not null default ''` | resolved UUID; `''` = looked-up, no match |
| `psa10_price_cents` | `int` null | PSA 10 `avg`, the comp headline; null when card has no PSA 10 tier |
| `pt_trend` | `text` null | `check (pt_trend in ('up','down','stable'))` |
| `pt_confidence` | `text` null | `check (pt_confidence in ('high','medium','low'))` |
| `pt_sale_count` | `int` null | Poketrace sale count |
| `resolved_at` | `timestamptz not null default now()` | drives 7-day re-attempt + staleness |

Indexes:
- PK on `product_id`.
- `tcg_grade_comp_psa10_idx` on `(psa10_price_cents)` `where psa10_price_cents is not null`
  — supports spread sorting / set-has-gains checks.

Run bookkeeping reuses `graded_ingest_runs` with `source = 'poketrace-comp'`.

## RPCs (mirror the Movers RPC shapes)

`get_grade_gain_sets()` → `[{ group_id, group_name, movers_count, published_on }]`
(reuses the `MoversSetDTO` wire shape). Returns English (`category_id = 3`) `tcg_groups`
that have **≥1 product with a positive spread** (`psa10_price_cents > raw market price`),
with the count of such products, ordered by `published_on DESC`.

`get_set_grade_gains(group_id int, price_tier text)` →
`[{ product_id, product_name, group_name, image_url, sub_type_name, raw_price_cents,
psa10_price_cents, spread_cents, pt_trend, pt_confidence, pt_sale_count }]`.

- **One row per product.** Raw price = the **highest** `market_price` across the product's
  `tcg_prices` subtypes (the gradeable chase printing); `sub_type_name` is that subtype.
- `spread_cents = psa10_price_cents − raw_price_cents`, sorted **DESC**.
- `price_tier` filters on **raw** price using the same band boundaries as `MoversPriceTier`
  (`under_5` … `tier_200_plus`).
- Only rows with `psa10_price_cents is not null` and `spread_cents > 0`.

The grading fee is **not** applied server-side: subtracting a constant from every row
doesn't change the ranking, so the server sorts by gross spread and the client subtracts
the fee for display and to hide rows that go non-profitable after the fee.

## Backfill Pipeline (scraper)

New CLI job: `bun run cli run graded poketrace-comp [--max-requests N] [--daily-floor N]`.
Pattern follows existing `scraper/src/graded/` sources/ingest; add
`scraper/src/graded/sources/poketrace-comp.ts` and an ingest entry.

Algorithm:
1. Query English `tcg_groups` `ORDER BY published_on DESC NULLS LAST`.
2. For each group, query its `tcg_products` joined to `tcg_grade_comp`, **skipping
   products whose `resolved_at` is < 7 days old** (resume-for-free; oldest-stale first).
3. Per product: `GET /cards?tcgplayer_ids=<product_id>`.
   - 0 results → upsert `(product_id, poketrace_card_id='', psa10_price_cents=null, resolved_at=now())`.
   - else → `GET /cards/{uuid}`, `extractTierPrice(card,"PSA_10")` → upsert avg cents +
     trend/confidence/sale_count + uuid + `resolved_at`.
4. **Budget guard:** after each call read `x-ratelimit-daily-remaining`; stop when it
   drops below `--daily-floor` (default 200) or the `--max-requests` cap is reached.
5. **Fail loud (rule 12):** log products covered / skipped-fresh / no-match / remaining
   budget. Record a `graded_ingest_runs` row with these stats. No silent truncation.

Transient (non-200, non-empty) failures do **not** write the sentinel — they're retried
next run, matching the existing `resolvePoketraceCardId` discipline.

## iOS Page

New top-level page `GradeGainsListView` under `Features/GradeGains/`, reusing Movers
components verbatim where possible:

- **Filter rail:** reuse `MoversPriceTier` (same bands, same chip rail), default `under_5`.
- **Set rail + search:** same component pattern as Movers; bootstraps to newest set when
  `setFilter == nil`.
- **Fee control:** a stepper/field in the header, default `$25`, persisted (AppStorage).
  `profit = psa10 − raw − fee`, computed client-side.
- **Rows:** rank, product name + variant badge, set name; show **profit**, raw price, and
  PSA 10 comp. Rows that are non-profitable after the fee are hidden (an optional
  "show all" toggle may surface them; v1 default hides).
- **State/caching:** new `GradeGainViewModel` (`@Observable @MainActor`) mirroring
  `MoversViewModel`'s set/tier caching, filter fingerprint, and inflight-drop guards —
  but single-language, no tab snapshots.
- **Repository/DTOs:** `GradeGainRepository` calling the two RPCs; DTOs mirroring
  `MoverDTO` / `MoversSetDTO`. Per CLAUDE.md rule 6, do a live `Decodable` round-trip
  against the deployed RPCs before declaring the wire contract done.

**Detail view** `GradeGainDetailView` (tap a row): hero image, the profit breakdown
(raw / PSA 10 / fee / profit), and the **raw** card's 90-day price history via the
existing `get_product_price_history(product_id, sub_type, days)` RPC. Graded (PSA 10)
history is **deferred to v2**.

## Testing

- **Scraper:** unit-test the budget guard (stops at floor), the 7-day skip, the
  empty-search sentinel write, and `PSA_10` extraction from a fixture card-detail payload
  (reuse `price-comp` fixtures). Live-decode a real Poketrace response once before cutover.
- **RPCs:** SQL tests asserting (a) sort by spread DESC, (b) raw-price tier banding, (c)
  highest-subtype selection, (d) only positive-spread rows, (e) `get_grade_gain_sets`
  count matches `get_set_grade_gains` row counts per set. No RLS test needed (global data),
  but assert the table is readable by the app role.
- **iOS:** view-model tests for fee recompute + unprofitable hiding (rule 9: a test that
  fails if the fee math changes), set/tier fingerprint reload, and inflight-drop. A
  `Decodable` round-trip test against a captured RPC response.

## Open Questions / To Verify During Implementation

1. **Batched search:** does `GET /cards?tcgplayer_ids=a,b,c` return all matches (and does
   the payload already include `prices`, letting us skip the per-card detail call)? If so,
   the budget stretches from ~5k to nearly ~10k cards/day. Verify against the live API
   before finalizing the per-card request count.
2. **Set rail naming:** the RPC reuses `movers_count` for "products with gains" — confirm
   the column name in the shared DTO or introduce a `gains_count` alias.
3. **Final page name** ("Grade Gains" placeholder) and its slot in the tab bar / IA.

## Rollout

1. Migration: `tcg_grade_comp` + indexes (schema only, `supabase/migrations/`).
2. Scraper job + tests; run one budgeted backfill pass over the newest English sets.
3. RPCs + SQL tests; deploy.
4. iOS page + detail + tests, wired to the deployed RPCs after a live decode round-trip.
