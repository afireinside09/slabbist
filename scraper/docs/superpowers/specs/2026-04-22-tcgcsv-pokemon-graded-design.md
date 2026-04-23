# tcgcsv: Pokémon + graded-card data pipeline

**Date:** 2026-04-22
**Repo:** `/Users/dixoncider/slabbist/tcgcsv/`
**Role in Slabbist monorepo:** sub-project 2 (catalog ingest — tcgcsv.com data for raw + grading APIs + eBay for graded)

## Problem

Slabbist is an iOS app that helps Pokémon hobby-store vendors comp raw and graded cards in bulk. The app reads from a shared Supabase Postgres DB in the monorepo. This repo's job is to fill that DB with two independent data sets:

1. **Raw Pokémon card catalog and pricing** from tcgcsv.com (English category 3 + Japanese category 85).
2. **Graded card data** — per-cert identity and market pricing — from PSA, CGC, BGS, SGC, and TAG grading services plus eBay sold listings.

## Goals

- Keep raw and graded domains architecturally decoupled. No foreign keys between them. Any linkage is a presentation-layer concern in the consuming apps.
- Write-only from this repo. Consumers (iOS, website, Edge Functions) read directly from Supabase.
- Idempotent, observable ingestion jobs that can fail partially without corrupting state.
- Schema additions coordinated through the monorepo-shared Supabase migrations directory so parallel sub-projects don't collide.

## Non-goals

- No HTTP/GraphQL API surface from this repo.
- No user-initiated cert lookup flow. That's an iOS-app feature served by a separate `/cert-lookup` Supabase Edge Function, out of scope here.
- No entity resolution between raw tcgcsv products and graded cards. Those remain distinct domains.
- No `stores`, `store_members`, `cards`, `comp_snapshots`, or `lots` tables — those belong to other sub-projects.

## Architecture overview

- **Language/stack:** TypeScript (ESM, strict), Node 20+, Bun for package management, Vitest, Commander CLI, `p-limit`, `@supabase/supabase-js`, `zod`.
- **Storage:** shared Supabase Postgres in monorepo. Tables live under `tcg_*` (raw) and `graded_*` (graded) prefixes.
- **Runtime:** GitHub Actions cron, one workflow per job.
- **Cadence:**
  - tcgcsv ingestion: daily
  - eBay sold listings: hourly
  - grading-service pop reports: weekly
- **Consumers:** Slabbist iOS app and Next.js website read Supabase directly via `@supabase/supabase-js` with RLS. Read-only access for them; service-role writes from this repo.
- **Schema location:** monorepo-shared at `/Users/dixoncider/slabbist/supabase/migrations/`. Not inside this repo.

## Data model

All tables defined in one additive migration at
`/Users/dixoncider/slabbist/supabase/migrations/<timestamp>_tcgcsv_pokemon_and_graded.sql`.

### Raw domain (6 tables)

- **`tcg_categories`** — `category_id` PK, `name`, `modified_on`. Only rows 3 (Pokémon EN) and 85 (Pokémon JP) are populated.
- **`tcg_groups`** — `group_id` PK, `category_id` FK, `name`, `abbreviation`, `is_supplemental`, `published_on`, `modified_on`.
- **`tcg_products`** — `product_id` PK, `group_id` FK, `category_id`, `name`, `clean_name`, `image_url`, `url`, `modified_on`, `image_count`, `is_presale`, `presale_release_on`, `presale_note`, Pokémon extracts (`card_number`, `rarity`, `card_type`, `hp`, `stage`), full `extended_data JSONB`.
- **`tcg_prices`** — latest snapshot. Composite PK `(product_id, sub_type_name)`. Fields: `low_price`, `mid_price`, `high_price`, `market_price`, `direct_low_price`, `updated_at`.
- **`tcg_price_history`** — append-only. `id`, `scrape_run_id` FK, `product_id`, `sub_type_name`, same price fields, `captured_at`.
- **`tcg_scrape_runs`** — `id UUID`, `category_id`, `started_at`, `finished_at`, `status` (`running`/`completed`/`failed`/`stale`), counters (`groups_total`, `groups_done`, `products_upserted`, `prices_upserted`), `error_message`.

### Graded domain (7 tables)

- **`graded_card_identities`** — graded-domain normalized card identity. `id UUID PK`, `game` (`'pokemon'` for now), `language` (`'en'`/`'jp'`), `set_name`, `set_code`, `year`, `card_number`, `card_name`, `variant`. Created on first sighting by any source. Ambiguous matches are surfaced for manual review rather than silently collapsed.
- **`graded_cards`** — per-cert row. `id UUID PK`, `identity_id` FK, `grading_service` (`PSA`/`CGC`/`BGS`/`SGC`/`TAG`), `cert_number`, `grade` (string to handle BGS `9.5` and sub-grades), `graded_at`, raw source payload `JSONB`. Unique `(grading_service, cert_number)`.
- **`graded_card_pops`** — population snapshots. `(identity_id, grading_service, grade, captured_at)` plus `population`. Append-only; written weekly.
- **`graded_market`** — grade-level comp aggregate. PK `(identity_id, grading_service, grade)`. Fields: `low_price`, `median_price`, `high_price`, `last_sale_price`, `last_sale_at`, `sample_count_30d`, `sample_count_90d`, `updated_at`. Primary pricing surface for the iOS app.
- **`graded_market_sales`** — raw eBay sold listings feeding `graded_market`. Fields include `identity_id`, `grading_service`, `grade`, `source`, `source_listing_id`, `sold_price`, `sold_at`, `title`, `url`, `captured_at`. Dedupe on `(source, source_listing_id)`.
- **`graded_cert_sales`** — per-cert sales when attributable (PSA APR, eBay listings with cert# in title). `id`, `graded_card_id` FK, `source`, `source_listing_id`, `sold_price`, `sold_at`, `title`, `url`, `captured_at`.
- **`graded_ingest_runs`** — `id UUID`, `source` (`psa`/`cgc`/`bgs`/`sgc`/`tag`/`ebay`/`pop`), `started_at`, `finished_at`, `status`, `stats JSONB`, `error_message`.

### Indexes

- `tcg_products(group_id)`, `tcg_products(card_number)`, `tcg_prices(product_id)`, `tcg_price_history(product_id, captured_at DESC)`
- `graded_cards(identity_id)`, `graded_card_identities(set_code, card_number)`, `graded_market(identity_id)`, `graded_market_sales(sold_at DESC)`, `graded_card_pops(identity_id, captured_at DESC)`

### RLS

All tables: public `SELECT`, service-role only for `INSERT`/`UPDATE`/`DELETE`. No user PII resides here.

## Components

### Repository layout

```
tcgcsv/
  src/
    shared/
      db/supabase.ts       singleton service-role client
      http/fetch.ts        fetch wrapper with retry + User-Agent
      retry.ts             exponential backoff, Retry-After aware
      concurrency.ts       p-limit wrapper
      logger.ts            structured logging
      config.ts            env var loading (dotenv)

    raw/
      sources/tcgcsv.ts    groups / products / prices API client
      extractors.ts        parse Pokémon fields from extendedData
      models.ts            TS types for raw domain
      ingest.ts            orchestrator: cat 3 & 85 -> DB upsert + history append
      images.ts            optional: mirror product images to Supabase Storage

    graded/
      sources/
        psa.ts             PSA Public API: cert lookup, pop, APR
        cgc.ts             CGC scraper: census + cert pages
        bgs.ts             BGS/Beckett: OPG + cert pages
        sgc.ts             SGC: API or scraper (depends on available access)
        tag.ts             TAG Grading: lookup + pricing
        ebay.ts            eBay Browse + Marketplace Insights when approved;
                           sold-items scraping fallback
      identity.ts          normalizeIdentity() -> find/create graded_card_identities
      cert-parser.ts       detect cert numbers in eBay titles
      aggregates.ts        recompute graded_market from graded_market_sales
      models.ts
      ingest/
        pop-reports.ts     weekly worker
        ebay-sold.ts       hourly worker

    cli.ts                 commander-based CLI
                           run raw tcgcsv [flags]
                           run graded ebay [flags]
                           run graded pop [--service psa|cgc|bgs|sgc|tag|all]

  tests/                   vitest
  .github/workflows/
    ingest-raw-tcgcsv.yml      daily 06:00 UTC
    ingest-graded-ebay.yml     hourly
    ingest-graded-pop.yml      weekly Sunday 12:00 UTC
    ci.yml                     typecheck + tests on push/PR

  package.json tsconfig.json bun.lock README.md
```

### Source-module contract

Every `sources/<name>.ts` exposes the same shape: pure data fetchers that validate responses via zod and return `NormalizedPayload[]`. Persistence lives in the domain-level `ingest.ts` / `ingest/*.ts`. Source modules never touch Supabase.

### Run-row pattern

Every ingest opens a `*_runs` row at start with `status='running'`, writes counters as it progresses, and closes with `status='completed'` or `'failed'` plus `error_message`. Zombie rows (crashed jobs) are marked `'stale'` by the next run.

## Data flow

### Daily tcgcsv ingest (`run raw tcgcsv`)

1. Open `tcg_scrape_runs` row.
2. For each category (3, 85): fetch groups via `/tcgplayer/{cat}/groups`, upsert `tcg_groups`.
3. For each group (concurrency 3, 200 ms delay): fetch products and prices, upsert `tcg_products` (with Pokémon field extraction) and `tcg_prices`, append to `tcg_price_history` stamped with `scrape_run_id`.
4. Close run row.

### Hourly eBay sold ingest (`run graded ebay`)

1. Open `graded_ingest_runs` row (`source='ebay'`).
2. Read watermark: `max(sold_at)` in `graded_market_sales`, default to 24 h ago if empty.
3. Query eBay for graded Pokémon sold listings since watermark using a curated query list per `(service, grade)`. Marketplace Insights API when approved, sold-items page scraping until then.
4. For each listing:
   - Parse title into `(grading_service, grade, card identity hints)`.
   - `normalizeIdentity(hints)` — find or create `graded_card_identities`.
   - Upsert `graded_market_sales` (dedupe on `(source, source_listing_id)`).
   - If cert# parseable: find-or-create `graded_cards`; insert `graded_cert_sales`.
5. `aggregates.ts`: recompute 30 d/90 d stats for every `(identity_id, service, grade)` touched; upsert `graded_market`.
6. Close run row.

### Weekly pop ingest (`run graded pop`)

1. Open `graded_ingest_runs` row (`source='pop'`).
2. For each of 5 services: fetch pop data, iterate `(identity, grade, population)`.
3. `normalizeIdentity()` -> `identity_id`. Insert `graded_card_pops` stamped `captured_at = now()`. Append-only.
4. Close run row.

### Idempotency

All upserts use deterministic conflict keys. Time-series writes are append-only keyed on `captured_at`. Every job is safe to re-run after a partial failure.

### Concurrency & rate limits

- tcgcsv: 3 concurrent groups, 200 ms delay (proven in `tcgturf/scraper`)
- eBay: 1-2 concurrent queries, 1-2 s delay, aggressive backoff on any non-2xx
- Grading APIs: 1-2 concurrent to start; tune per service as published limits are learned

## Error handling

**Transport layer** — `shared/http/fetch.ts` + `retry.ts`. Exponential backoff with `Retry-After` honored. Retryable: 429, 500, 502, 503, 504, network errors. Non-retryable: other 4xx. Max 3 attempts, 2 s initial, 2× multiplier. Every HTTP call routes through this; no ad-hoc `fetch()`.

**Payload layer** — `zod` schemas per source, validated at the source boundary. Upstream shape changes surface as loud, attributable validation errors rather than silent `NULL`s.

**Run layer** — `*_runs` rows plus GH Actions exit codes. Every run is attributable; zombies marked `'stale'` on next invocation.

**Partial failures** — a single failed group or query logs an error to the run row and continues. One flaky set doesn't block the other 400. Matches `tcgturf/scraper` posture.

**Schema drift** — zod validation failure halts the affected source's run. Halt and investigate rather than persist corrupted data.

**Observability (MVP)** — run rows + GH Actions logs + workflow failure emails. No Sentry/Datadog in v1.

## Testing

**Vitest**, three tiers:

1. **Unit tests per source** — mock HTTP with fixture JSON under `tests/fixtures/<source>/`. Verify parse + zod validation + normalization. One fixture per distinct response shape (success, empty, rate-limited, malformed). No real network in unit tests.
2. **Normalization & aggregate tests** — pure-function tests for `normalizeIdentity()`, `cert-parser.ts`, `aggregates.ts`. Adversarial inputs including non-English titles, unusual grade strings (e.g. `"BGS 9.5 (10,10,9.5,9)"`), missing fields.
3. **Ingest integration tests** — one full ingest pass against ephemeral Postgres (pg-mem or testcontainers) with mocked HTTP. Verifies run-row lifecycle, idempotency (two runs = same state), and aggregate recompute. Runs on main-branch pushes, not on every PR.

**Out of scope for v1:** E2E tests against real tcgcsv/eBay/grading APIs. Real-network validation lives in a manual `bun run smoke <source>` command.

**CI:** single workflow on push/PR runs `bun run typecheck && bun run test`. Separate from scheduled ingest workflows.

## Secrets & config

Env vars loaded via `dotenv` for local runs; GH Actions repo secrets in CI:

- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- `PSA_API_KEY` (paid tier)
- `BECKETT_OPG_KEY` (when available; otherwise unused)
- `EBAY_APP_ID`, `EBAY_CERT_ID`, `EBAY_DEV_ID` (Browse API; Marketplace Insights once approved)
- `TAG_API_KEY` (if TAG exposes one)
- CGC and SGC may be scraping-only initially and require no secret.

Source modules that lack configured credentials no-op with a logged warning. An ingest run can complete with some sources unreachable — this is documented and reflected in the run row's stats.

## Deferred / future work

- User-initiated cert lookup flow — lives in the `/cert-lookup` Supabase Edge Function, called from the iOS app. Cert-lookup logic in this repo (`graded/sources/*` + `graded/identity.ts`) should be written as pure libraries so the Edge Function can import them when that work begins.
- Historical backfill via `tcgturf/tcg-archive` — filesystem snapshots can be imported into `tcg_price_history` on day one if desired. Not blocking MVP.
- Entity resolution between raw and graded domains — deliberately out of scope. If needed later, it's a presentation-layer concern in the consuming apps.
- Additional games beyond Pokémon — schema has `game` field on `graded_card_identities`; raw domain would need new category IDs. Trivial to extend when demand exists.

## Open items before implementation

- Confirm which grading-service credentials are already available (PSA, BGS, TAG, SGC). Sources without credentials ship as scrapers.
- Decide timing for eBay Marketplace Insights API application — code path is ready, approval gates it.
- Align migration filename/timestamp with whatever convention the monorepo's `supabase/migrations/` adopts (this repo is the first to write to it; convention will be established by this PR).
