# @slabbist/tcgcsv

Ingestion-only pipeline that populates the Slabbist monorepo's Supabase DB with:
- **Raw** Pokémon catalog & pricing from tcgcsv.com (categories 3 English, 85 Japanese)
- **Graded** card data from PSA / CGC / BGS / SGC / TAG + eBay sold listings

Raw and graded domains are architecturally decoupled. Consumers (iOS, website) read Supabase directly.

See the design spec: `docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md`.

## Quick start

    bun install
    cp .env.example .env    # fill in credentials
    bun run typecheck
    bun run test

## CLI

    bun run cli run raw tcgcsv                    # daily tcgcsv refresh (cat 3 + 85)
    bun run cli run graded ebay                   # every 6h eBay sold listings (watchlist-driven)
    bun run cli run graded pop -s psa             # weekly pop report (one service)
    bun run cli run graded pop -s all             # weekly pop report (all services)
    bun run cli seed popular-slabs                # seed graded_watchlist with top-200 popular slabs

Flags:
- `-c, --concurrency <n>`  — concurrent group requests (default 3; raw only)
- `-d, --delay-ms <ms>`    — per-start delay between groups (default 200; raw only)
- `-q, --queries <list>`   — comma-separated eBay queries (graded ebay only; omit to source queries from `graded_watchlist`)

## Graded eBay watchlist

The eBay sold-listings ingest scrapes a curated watchlist of popular slabs, not the whole catalog.

- `graded_watchlist` holds `(identity_id, grading_service, grade)` rows with `source = seed | auto_promoted | manual`.
- Seed the initial set from `src/graded/seeds/popular-slabs.json` (top-200) with `bun run cli seed popular-slabs`.
- Every run calls `promote_scanned_slabs_to_watchlist(min_scans=5, window_days=7)`: any slab that was scanned by ≥5 distinct certs in the last 7 days (via iOS `scans` → `graded_cards`) gets auto-promoted.
- Live on-demand lookups for arbitrary cards happen in the iOS app; this ingest only keeps the watchlist's price history fresh.

## Scheduled jobs (GitHub Actions)

| Workflow                           | Cron             | What it runs                 |
|------------------------------------|------------------|------------------------------|
| `ingest-raw-tcgcsv.yml`            | `0 6 * * *`      | `run raw tcgcsv`             |
| `ingest-graded-ebay.yml`           | `0 */6 * * *`    | `run graded ebay`            |
| `ingest-graded-pop.yml`            | `0 12 * * 0`     | `run graded pop -s all`      |
| `ci.yml`                           | push/PR          | `typecheck` + `test`         |

Each cron workflow pulls secrets from GitHub repo secrets. See `.env.example` for the full list.

## Schema

Tables are defined in the monorepo-shared migration at:
`/Users/dixoncider/slabbist/supabase/migrations/20260422120000_tcgcsv_pokemon_and_graded.sql`

This repo never defines schema locally.

## Observability

- Every ingest writes a row to `tcg_scrape_runs` (raw) or `graded_ingest_runs` (graded) with start/end times, counters, and error messages.
- Failures surface via GH Actions workflow failure emails.
- Structured JSON logs go to stdout for the workflow run page.

## Developing a new source

1. Add a module under `src/<domain>/sources/<name>.ts` that exports pure fetchers returning normalized models. Validate responses with zod.
2. Add a fixture under `tests/fixtures/<name>/` that reflects a real response shape.
3. Add a unit test that stubs `fetch` against the fixture and asserts normalization output.
4. Wire the source into the appropriate domain ingest (`src/raw/ingest.ts` or `src/graded/ingest/*.ts`).
5. If the source contributes to a new scheduled cadence, add a `.github/workflows/ingest-<source>.yml` cron workflow.

## Known open items

- Grading-service credentials: PSA/BGS/TAG may be API-gated — sources without keys fall back to HTML scraping via `httpText()`.
- eBay Marketplace Insights API requires approval — scraping `ebay.com/sch` sold-items pages is used until approved.
- Migration-naming convention established by this migration (`YYYYMMDDHHMMSS_<description>.sql`); re-align if the monorepo's Supabase CLI config dictates otherwise.
