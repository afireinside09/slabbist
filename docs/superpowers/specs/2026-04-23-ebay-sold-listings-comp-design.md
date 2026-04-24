# eBay Sold-Listings Live Comp — Design Spec

**Sub-project:** #4 (Comp engine v1) + #5 (Bulk scan) + #11 (Integrations) delta
**Date:** 2026-04-23
**Status:** Design approved; awaiting implementation plan
**Parent spec:** [`2026-04-22-bulk-scan-comp-design.md`](./2026-04-22-bulk-scan-comp-design.md)

## Summary

Lights up the `/price-comp` Edge Function's live-fetch path so that when a scan validates and the app requests a comp, the function returns the latest 10 eBay sold listings — with outlier-aware mean, trimmed mean, median, and a confidence score — and persists them as a warm cache for subsequent requests. A hybrid cache-read + on-demand-fallback design that keeps the iOS contract from the parent spec unchanged.

Per the project's scraper-strategy decision (watchlist-based, not full-catalog), the scraper repo runs a scheduled job only over a curated watchlist of popular slabs; it does **not** pre-warm the entire catalog. Everything outside the watchlist is on-demand, owned by this feature. This feature also emits a per-scan signal that the scraper's future promotion logic consumes to decide which identities earn watchlist membership — so a store owner scanning a card the system has never seen before gets a useful comp inside ~1.5 seconds, and frequently-scanned identities naturally graduate to scheduled tracking over time.

## Goals

1. A scan of any graded Pokémon card returns a defensible comp in one round-trip, even if the catalog has never seen it before.
2. The iOS contract defined in the parent spec (`/price-comp` request/response shape) is extended, not replaced — existing wiring stays valid.
3. One official eBay API is the only source of truth; HTML scraping is not used in the live path.
4. eBay Marketplace Insights API quota (5,000 calls/day default) holds comfortably for a card-show workload with cache-driven amortization.
5. Results are resilient to one or two bad listings (signed/1-of-1/mislabeled auctions) without manual curation.
6. Every `/price-comp` invocation emits a scan signal the scraper can consume to promote popular identities into its watchlist for scheduled tracking.

## Non-goals

- Cross-grade or cross-grader arbitrage comps — deferred.
- Non-Pokémon catalogs — everything identity-driven uses eBay category `183454` (Pokémon Individual Cards).
- Sandbox / dev eBay environment wiring — production only for MVP.
- Per-request user-level rate-limiting — the Edge Function runs service-role; quota is app-level.
- New observability / alerting infrastructure beyond structured logs — dedicated observability sub-project later.
- Changes to the existing `ebay-account-deletion` webhook — already shipped.
- Changes to the scraper's scheduled ingest — the scraper owns its own watchlist strategy; this spec neither defines nor modifies it.
- Defining the `tracked_slabs` watchlist schema or the promotion/demotion logic — those belong to the scraper sub-project's next spec. This feature only *emits* the scan signal it will need.

## Architecture

```
iOS  ───────►  /price-comp (Edge Function, Deno)
                  │
                  ├─ read graded_market where (identity_id, grading_service, grade)
                  │     │
                  │     ├─ row exists AND updated_at within EBAY_FRESHNESS_TTL_SECONDS
                  │     │       └─ load graded_market_sales rows, return cached payload
                  │     │          (cache_hit: true)
                  │     │
                  │     └─ miss OR stale
                  │           └─ LIVE path (below)
                  │
                  └─ LIVE path
                        ├─ OAuth2 client_credentials  → bearer token (cached ~2h in-process)
                        ├─ cascading Marketplace Insights queries (see Query Cascade)
                        ├─ title-parse validation (reuse scraper/src/graded/cert-parser.ts)
                        ├─ outlier detection (MAD), compute aggregates
                        ├─ upsert graded_market_sales (one row per listing)
                        ├─ upsert graded_market (aggregate row with fresh updated_at)
                        └─ return payload (cache_hit: false)
```

### Boundaries

- iOS never calls eBay directly. The two-endpoint contract from the parent spec (`/cert-lookup`, `/price-comp`) holds.
- The Edge Function imports `parseGradedTitle` from the `scraper/` workspace (the parent spec already establishes workspace imports from tcgcsv as the pattern for `/cert-lookup`).
- Live fetch writes `graded_market` and `graded_market_sales` with the service-role client, same as the hourly scraper.

## Data model

### Schema additions (new migration)

Extends the existing `graded_market` table (owned by tcgcsv, shared via the monorepo):

```sql
alter table graded_market
  add column if not exists mean_price_cents           bigint,
  add column if not exists trimmed_mean_price_cents   bigint,
  add column if not exists sample_window_days         smallint,
  add column if not exists confidence                 real;
```

New table: `slab_scan_events` (defined under *Scan signal for watchlist promotion* below). Append-only; consumed by the scraper sub-project.

No changes to `graded_market_sales`; its shape already supports per-listing rows. No changes to any tenant-owned table (`stores`, `store_members`, `lots`, `scans`).

## `/price-comp` Edge Function contract

### Request
```
POST /price-comp
Authorization: Bearer <user JWT>
Body: { graded_card_identity_id, grading_service, grade }
```

### Response 200
```jsonc
{
  "blended_price_cents": 12845,          // = trimmed_mean_price_cents (UI headline)
  "mean_price_cents": 13210,
  "trimmed_mean_price_cents": 12845,
  "median_price_cents": 12990,
  "low_price_cents": 9800,
  "high_price_cents": 24500,
  "confidence": 0.82,                    // 0.0 – 1.0
  "sample_count": 10,
  "sample_window_days": 90,              // which cascade bucket produced the sample
  "velocity_7d": 4,
  "velocity_30d": 14,
  "velocity_90d": 38,
  "sold_listings": [
    { "sold_price_cents": 12500,
      "sold_at": "2026-04-21T14:22:11Z",
      "title": "2024 Pokemon SV Surging Sparks Pikachu ex 247/191 PSA 10",
      "url": "https://www.ebay.com/itm/...",
      "source": "ebay",
      "is_outlier": false,
      "outlier_reason": null },
    { "sold_price_cents": 24500,
      "sold_at": "2026-04-19T01:05:00Z",
      "title": "...signed by artist...",
      "url": "https://www.ebay.com/itm/...",
      "source": "ebay",
      "is_outlier": true,
      "outlier_reason": "price_high" }
    // … up to 10 most-recent rows
  ],
  "fetched_at": "2026-04-23T22:14:03Z",
  "cache_hit": false,                    // true iff served from graded_market without live fetch
  "is_stale_fallback": false             // true iff eBay was down and stale cache was served
}
```

### Error responses
- `404 { "code": "NO_MARKET_DATA" }` — cascade exhausted, zero matching sold listings. Client shows "No recent comps."
- `503 { "code": "UPSTREAM_UNAVAILABLE" }` — eBay down AND no cached `graded_market` row. Outbox retries with backoff (30s → 2m → 10m → 1h cap).
- `401` / `403` — auth missing/invalid; standard Supabase JWT enforcement.

## Query cascade

Given identity fields `{ game, language, set_name, card_number, card_name, variant, year, grading_service, grade }`, attempt buckets in order, stop at the first yielding **≥ `EBAY_MIN_RESULTS_HEADLINE` (default 10)** matches after title-parse validation:

| # | Window | Query shape | Category |
|---|--------|-------------|----------|
| 1 | 90d | `"{card_name} {card_number}" "{grading_service} {grade}"` | `183454` |
| 2 | 90d | `{card_name} {set_name} {card_number} {grading_service} {grade}` | `183454` |
| 3 | 365d | same as bucket 1 | `183454` |
| 4 | 365d | same as bucket 2 | `183454` |

`sample_window_days` on the response is `90` for buckets 1–2 and `365` for buckets 3–4.

If all four buckets yield fewer than the threshold, use the bucket with the most results (still ≥ 1); confidence scales down. If all four yield zero, respond `404 NO_MARKET_DATA`.

Every eBay result is passed through `parseGradedTitle` (existing library) to verify the parsed `(grading_service, grade)` matches the requested values; non-matching rows are dropped before any statistic is computed.

## Aggregate statistics

On the selected sample of `N` validated listings (capped at 10 most recent by `lastSoldDate`):

```
prices  = validated listings sorted by sold_at desc, capped at 10 most-recent
mean    = arithmetic mean of prices
median  = median of prices
low     = min of prices
high    = max of prices

// outlier detection
med     = median(prices)
mad     = median(|p_i − med|)
is_outlier(p_i) = |p_i − med| > 3 × 1.4826 × mad
outlier_reason  = "price_high" if p_i > med, else "price_low"

trimmed_mean = arithmetic mean of { p_i ∈ prices : NOT is_outlier(p_i) }
               (falls back to mean if all listings would be trimmed; never returns null)
```

The 1.4826 constant scales MAD to a σ-equivalent under normal-distribution assumptions. `3 × σ` is conservative for a sample as small as N=10 — keeps most legitimate price variation in the non-outlier set while catching truly anomalous listings.

Outliers are **excluded** from `trimmed_mean_price_cents` but **included** in `mean_price_cents`, and always present in `sold_listings[]` with the flag so the UI can surface the full picture.

## Confidence score

```
confidence = sample_factor × freshness_factor

sample_factor(n):
  0.0           if n == 0
  n / 10.0      if 1 ≤ n ≤ 10
  1.0           if n ≥ 10

freshness_factor(window):
  1.00  if window == 90
  0.50  if window == 365
```

The 180d intermediate band is reserved for tuning (not in the initial cascade). Both factors are env-tunable so we can re-calibrate post-launch without code change.

## OAuth + secrets

### Token flow
```
POST https://api.ebay.com/identity/v1/oauth2/token
Authorization: Basic base64(EBAY_APP_ID:EBAY_CERT_ID)
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&scope=https://api.ebay.com/oauth/api_scope/buy.marketplace.insights
```

Response carries `access_token` and `expires_in` (~7200 seconds). Cache in module-scope inside the Edge Function:

```ts
let cachedToken: { value: string; expiresAt: number } | null = null;
// refresh when Date.now() > expiresAt - 300_000  (5 min safety window)
```

On a `401 Unauthorized` from Marketplace Insights, invalidate the cache and retry once.

### Supabase secrets
Set via `supabase secrets set`:
- `EBAY_APP_ID` — App ID (Client ID) from the eBay developer console.
- `EBAY_CERT_ID` — **rotated** Cert ID. The value visible in the onboarding screenshot must be rotated via the eBay console before being set here.
- `EBAY_FRESHNESS_TTL_SECONDS` — default `21600` (6 hours).
- `EBAY_MIN_RESULTS_HEADLINE` — default `10`.
- `EBAY_OAUTH_SCOPE` — default `https://api.ebay.com/oauth/api_scope/buy.marketplace.insights`.

## Persistence (live path)

Order within a single Edge Function invocation:

1. Upsert each validated listing into `graded_market_sales`, keyed on `(source, source_listing_id)`. `source = 'ebay'`, `source_listing_id` from the MI `itemId` suffix after the `|` (same derivation as the scraper).
2. Upsert one `graded_market` row for `(identity_id, grading_service, grade)` with `low_price_cents`, `median_price_cents`, `high_price_cents`, `mean_price_cents`, `trimmed_mean_price_cents`, `sample_count_30d`, `sample_count_90d`, `sample_window_days`, `confidence`, `updated_at = now()`.
3. Return response payload; listings read back from the upserted rows (so cache-hit and live-fetch responses are byte-identical in shape).

All writes use the service-role Supabase client. RLS for these tables is set by tcgcsv (public SELECT for authenticated users; INSERT/UPDATE service-role only).

## Scan signal for watchlist promotion

Per the `Scraper strategy — watchlist, not full catalog` architectural decision, the eBay scraper tracks a bounded watchlist of popular slabs on a scheduled cadence and does not scrape the full catalog. The promotion signal is iOS scan activity — frequently-scanned identities earn watchlist membership; stale ones are demoted.

This feature is the emission point for that signal. Every `/price-comp` invocation (cache hit, cache miss, or stale fallback) appends a single row to a new append-only table:

```sql
create table if not exists slab_scan_events (
  id                uuid primary key default gen_random_uuid(),
  identity_id      uuid not null references graded_card_identities(id),
  grading_service  grader not null,
  grade            text not null,
  store_id         uuid references stores(id),
  cache_state      text not null check (cache_state in ('hit','miss','stale')),
  scanned_at       timestamptz not null default now()
);

create index slab_scan_events_identity_time
  on slab_scan_events (identity_id, grading_service, grade, scanned_at desc);
create index slab_scan_events_scanned_at
  on slab_scan_events (scanned_at desc);
```

Write happens after the response has been computed (never blocks the response — best-effort; a write failure is logged and swallowed so the user always gets their comp). The row carries `store_id` for future store-scoped analytics but the scraper's promotion logic will aggregate across stores.

The `tracked_slabs` watchlist table and the specifics of the promotion/demotion algorithm (window, scan-count thresholds, max watchlist size) belong to the scraper sub-project's own spec. This feature only guarantees that the event stream exists and is structured correctly for that future consumer.

## Failure modes

| Class | Behavior |
|---|---|
| eBay 5xx / network error | If `graded_market` row exists (even stale), return it with `is_stale_fallback: true` and log. If no cache, `503 UPSTREAM_UNAVAILABLE`. Client outbox retries. |
| eBay 429 rate-limit | Same as 5xx; additionally pause all live fetches in this isolate for 60 seconds (module-scope timestamp). |
| OAuth failure (cred invalid / token endpoint down) | Treat as upstream down; log at ERROR (credentials issue) and emit a structured marker for alerting. |
| Zero results across all four buckets | `404 NO_MARKET_DATA`. Client shows "No recent comps." |
| < 10 validated results in best bucket | Return all found, `sample_count < 10`, `confidence` scaled down. UI shows low-confidence chip. |
| Title-parse validation drops all results | Treated as zero results for that bucket; proceed to next. If final bucket also drops everything, `404 NO_MARKET_DATA`. |
| MI API returns duplicate listings | Upsert dedups via `(source, source_listing_id)` unique key; harmless. |

## iOS changes

The app-side contract is already wired via the parent spec's `priceCompJob` outbox kind. This feature fills in:

### SwiftData model additions
- `GradedMarketSnapshot` gains: `meanPriceCents`, `trimmedMeanPriceCents`, `sampleCount`, `sampleWindowDays`, `cacheHit`, `isStaleFallback`.
- New `@Model SoldListingMirror`: `soldPriceCents`, `soldAt`, `title`, `url`, `isOutlier`, `outlierReason`. Related to `GradedMarketSnapshot` as `@Relationship(deleteRule: .cascade)`.

### UI additions
Per the parent spec's approved UI layout, this feature populates:

- `BulkScanView`'s horizontal queue row → `PriceBadge` bound to `trimmedMeanPriceCents`.
- `ScanDetailView`:
  - Headline block: `trimmedMeanPriceCents` (large), `ConfidenceMeter` for `confidence`, an amber chip when `sampleCount < 10` or `isStaleFallback == true` reading "Low confidence — N comps" or "Cached — live data unavailable."
  - Comp breakdown: mean / trimmed mean / median / low / high (small stats rail).
  - Expandable "View all sold listings" section — row per `SoldListingMirror` with title, price, date, tappable source link, and an outlier badge when `isOutlier == true` (text: `outlierReason` → "High outlier" or "Low outlier").
  - Sparkline + velocity unchanged from parent spec.

No new screens. No changes to `LotsListView`, `NewLotSheet`, `LotReviewView`.

## Testing strategy

### Edge Function unit (Deno, inside the function's test file)
- Outlier MAD math — fixtures: dense-normal, one high outlier, one low outlier, all-identical, N=1, N=2.
- Aggregate math — cents-only integer arithmetic, no float-drift on round-trip.
- Confidence scoring — cardinal transitions at n=0, n=1, n=10, n=11, window 90 vs 365.
- Cascade selection — mock MI client; assert the correct bucket is picked.
- Title-parse validation — non-matching `(grading_service, grade)` dropped.
- Token caching — expiry window respected; 401 triggers re-fetch.

### Edge Function integration
- Local mock eBay server (Deno `serve` returning canned fixtures from `supabase/functions/price-comp/__fixtures__/`).
- Seeded `graded_card_identities` + `graded_cards`; assert rows land in `graded_market_sales` + `graded_market` with correct aggregates.
- Cache-hit path: second call within TTL returns `cache_hit: true` without hitting the mock server.
- Stale-fallback path: mock server 500; assert `is_stale_fallback: true` and stale payload returned.

### iOS (Swift Testing)
- Decode tests for the full response shape (all fields, optional fields null-safe).
- `CompRepository` stale-cache handling for the new fields.
- `SoldListingMirror` cascade-delete when snapshot is replaced.

### Manual end-to-end
- One simulator flow on a known-populated identity (real eBay call) to verify live path.
- One flow on a never-seen identity to verify first-request live fetch + cache warm-up.
- Airplane-mode flow to verify outbox retry on `503`.

## Observability

Structured logs via the Edge Function's stdout (Supabase Logs), one log line per live fetch:

```json
{
  "fn": "price-comp",
  "identity_id": "…",
  "grading_service": "PSA",
  "grade": "10",
  "cache_state": "hit" | "miss" | "stale",
  "live_fetch": true | false,
  "bucket_hit": 1 | 2 | 3 | 4 | null,
  "result_count": 10,
  "oauth_cache_hit": true,
  "response_time_ms": 847,
  "outlier_count": 1,
  "is_stale_fallback": false
}
```

No new dashboards or alert rules in this sub-feature. Query-via-Supabase-Logs is sufficient for MVP; observability sub-project owns any additional wiring later.

## Security

The Cert ID visible in the onboarding screenshot is compromised and must be rotated via the eBay developer console ("Rotate (Reset) Cert ID") before `EBAY_CERT_ID` is set as a Supabase secret. Implementation plan gates the secret-set step on this rotation.

No end-user credentials are stored; all eBay access is application-scoped (`client_credentials`).

## Open follow-ups (for implementation plan or post-launch)

- Re-calibrate the `3 × MAD` outlier threshold once we have real sample distributions.
- Tune `EBAY_FRESHNESS_TTL_SECONDS` based on observed per-identity re-scan cadence at card shows.
- Decide whether to expose the 180d intermediate window in the cascade (currently reserved).
- Consider a background warm-up job that pre-fetches for newly-ingested `graded_card_identities` to avoid the first-user-scan cold path.
- Column-naming alignment: the parent spec refers to `graded_market.low_price` / `median_price` / `high_price`; this spec uses the `_cents` suffix for new columns (`mean_price_cents`, `trimmed_mean_price_cents`). The implementation plan must verify the actual tcgcsv migration's column names and reconcile (either rename to `_cents` or drop the suffix everywhere) so the code and spec stay consistent.

## Cross-cutting references

- Parent: [`2026-04-22-bulk-scan-comp-design.md`](./2026-04-22-bulk-scan-comp-design.md)
- Pre-grade estimator spec (sibling): [`2026-04-23-pre-grade-estimator-design.md`](./2026-04-23-pre-grade-estimator-design.md)
- tcgcsv data surface (ownership of `graded_market`, `graded_market_sales`): [`tcgcsv/docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md`](../../../tcgcsv/docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md)
- Existing eBay scraper library reused here: `scraper/src/graded/sources/ebay.ts`, `scraper/src/graded/cert-parser.ts`
- eBay account-deletion webhook (already live, referenced for the Deno edge-function pattern): `supabase/functions/ebay-account-deletion/index.ts`
- Raw/graded decoupling memory note — this feature stays fully inside the graded domain.
