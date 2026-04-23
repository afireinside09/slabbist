# Sub-project 2 — Card & slab data model

**Status:** Implementing in the `tcgcsv` repo.

**Design spec:** [`/Users/dixoncider/slabbist/tcgcsv/docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md`](../../../../tcgcsv/docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md)

## Scope (delegated to tcgcsv)

The `tcgcsv` repo owns this sub-project end-to-end. It defines two independent domains living in the shared Supabase Postgres instance:

**Raw domain** (Pokémon English + Japanese catalog and pricing from tcgcsv.com):
- `tcg_categories`, `tcg_groups`, `tcg_products`, `tcg_prices`, `tcg_price_history`, `tcg_scrape_runs`

**Graded domain** (per-cert slab identity and market pricing from grading services + eBay):
- `graded_card_identities` — normalized card identity (game, language, set, card number, name, variant)
- `graded_cards` — per-cert rows (grading_service + cert_number + grade, FK to identity)
- `graded_market` — grade-level comp aggregate keyed `(identity_id, grading_service, grade)`
- `graded_market_sales` — raw eBay sold listings
- `graded_card_pops` — population snapshots, weekly
- `graded_cert_sales` — per-cert sales when attributable (PSA APR, cert# in title)
- `graded_ingest_runs` — observability for scheduled jobs

**Explicit decoupling:** no foreign keys, no shared identities, no join tables between `tcg_*` and `graded_*`. Matching raw to graded is a presentation-layer concern in consuming apps. See memory note *"Raw and graded card data stay decoupled"* for rationale.

## How other sub-projects interact with this data

- **Sub-project 3 (single slab scan)** and **sub-project 5 (bulk scan)** have scans that reference `graded_card_identities.id` and `graded_cards.id` via FK. The FK is added to `scans` in Plan 2 of the bulk-scan sub-project, once the tcgcsv migration has landed.
- **Sub-project 4 (comp engine)** is the iOS-app-side `/price-comp` Edge Function that reads `graded_market` + `graded_market_sales`. It does not write those tables.
- **Sub-project 9 (raw card ID)** consumes `tcg_products` for raw-card comp. Still does not join to `graded_*`.

## Features captured

- Canonical card catalog (raw + graded, separately)
- Japanese card support (raw: category 85 in tcgcsv; graded: `graded_card_identities.language = 'jp'`)
- Sealed product catalog (future — tcgcsv can extend)
- External-ref mapping for price sources and image sources (`tcg_products.image_url`, etc.)

## Features deferred from this sub-project

- Any cross-domain entity resolution or matching — deliberately out of scope.
- User-initiated cert-lookup flow — belongs to sub-project 3 + 5 as an Edge Function that imports tcgcsv's graded libraries.

## Dependencies

- Sub-project 1 (auth) — data tables share RLS conventions (public `SELECT` for authenticated users, service-role writes). Not a hard blocker.

## Unblocks

- Sub-projects 3, 4, 5, 9 — all scan/comp/raw features.
