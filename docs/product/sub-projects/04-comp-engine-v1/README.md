# Sub-project 4 — Comp engine v1

The pricing surface on the iOS-app side. Takes a `graded_card_identity_id` + grading_service + grade, returns a defensible price with context.

## Scope

- **`/price-comp` Edge Function** — thin read-through over `graded_market` + `graded_market_sales`.
  - Request: `{graded_card_identity_id, grading_service, grade}`
  - Response: `{blended_price_cents, confidence, velocity_7d/30d/90d, sold_listings[], fetched_at}`
  - No aggregation happens server-side in this Function — aggregation lives in the tcgcsv hourly eBay ingest (`src/graded/aggregates.ts`).
- **iOS-side cache** — `GradedMarketSnapshot` SwiftData model caches `/price-comp` responses. Refresh on open when older than 60 minutes (configurable).
- Blended price (median), confidence (from sample counts), velocity (computed from `graded_market_sales` in the Edge Function), last N sold listings with attribution and drill-in URLs.
- Sparklines — derived from `graded_market_sales` time series; returned as data arrays in the `/price-comp` response.

## Features captured

- eBay sold listings integration with outlier filtering (handled by tcgcsv's ingest)
- Blended/weighted price calculation with confidence score
- Sales velocity (7/30/90 days)
- Price trend arrows and sparklines
- Currency conversion (display-only; prices normalized to USD upstream by tcgcsv)

## What this sub-project owns vs references

- **Owns:** `/price-comp` Edge Function, iOS `CompRepository`, `GradedMarketSnapshot` SwiftData model, in-app comp UI (`PriceBadge`, `ConfidenceMeter`, `Sparkline`).
- **References:** `graded_market`, `graded_market_sales` (sub-project 2 / tcgcsv). Read-only. Aggregation is tcgcsv's responsibility.

## Deferred to later sub-projects or later versions

- PWCC, Goldin, other auction-house data — new tcgcsv source adapters, not iOS work.
- Population reports + pop shift alerts — reads `graded_card_pops` (owned by tcgcsv); UI comes later.
- Grade arbitrage calculator — needs pop data + cross-grade comp math. Sub-project 4 v2.
- Cross-grade comparison UI — needs arbitrage math as substrate.
- Regional market adjustment — weighting model lives in tcgcsv's aggregates; UI toggle is later.

## Dependencies

- Sub-project 2 (tcgcsv) — `graded_market` and `graded_market_sales` must exist and be populated.

## Unblocks

- Sub-projects 3 and 5 (actually showing prices)
