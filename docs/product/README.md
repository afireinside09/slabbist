# Slabbist — Product

Slabbist is an iOS app that helps Pokémon hobby store owners and vendors efficiently **comp** (determine value for) graded slabs and raw cards — primarily for buy/trade decisions at the counter or at card shows.

## Core value prop

> Bulk-scan slabs. Get defensible offer prices in seconds. Buy with confidence.

The hero flow: a store owner takes in a stack of 30 slabs, bulk-scans them, and sees a blended price + confidence score per slab based on recent eBay sold listings and other price sources. No more flipping between 130point, eBay, and a calculator.

## Sub-project organization

Each sub-project below has its own directory with a `README.md` capturing its feature scope. Sub-projects are numbered by **recommended build order**, not importance — earlier sub-projects build foundations that later sub-projects depend on.

| # | Sub-project | Status |
|---|---|---|
| 1 | [Auth & store/team model](sub-projects/01-auth-store-team/README.md) | planned |
| 2 | [Card & slab data model](sub-projects/02-card-slab-data-model/README.md) | **implementing** (tcgcsv repo) |
| 3 | [Single slab scan & comp](sub-projects/03-single-slab-scan/README.md) | planned |
| 4 | [Comp engine v1](sub-projects/04-comp-engine-v1/README.md) | planned |
| 5 | [Bulk scan mode](sub-projects/05-bulk-scan/README.md) | **designing** (MVP target) |
| 6 | [Store workflow — transactions, vendor DB, offers](sub-projects/06-store-workflow/README.md) | planned |
| 7 | [Margin rules, role visibility, shared buylist](sub-projects/07-margin-rules-buylist/README.md) | planned |
| 8 | [Analytics & reporting](sub-projects/08-analytics-reporting/README.md) | planned |
| 9 | [Raw card identification](sub-projects/09-raw-card-id/README.md) | planned |
| 10 | [Grading workflow](sub-projects/10-grading-workflow/README.md) | planned |
| 11 | [Integrations](sub-projects/11-integrations/README.md) | planned |
| 12 | [Marketplace, web dashboard, Android](sub-projects/12-marketplace-web-android/README.md) | planned |
| — | [Differentiators to prototype](sub-projects/differentiators/README.md) | exploration |

## Architecture baseline

- iOS: native SwiftUI + SwiftData + AVFoundation + Apple Vision
- Backend: Supabase (Postgres + Auth + RLS + Edge Functions)
- External data: hybrid — aggregator behind a `PriceSource` Edge Function, migrate to official eBay API later. Grader cert-lookup APIs (PSA/BGS/CGC/SGC/TAG) through `/cert-lookup` Edge Function.
- Offline-first everywhere: local SwiftData cache, outbox pattern for writes, TTL cache for reads.
- Multi-tenant from day one: `stores` + `store_members` scaffolded, `store_id`-scoped RLS, single-member for MVP.

## Upfront architectural decisions

1. **eBay data** — ingested by the tcgcsv repo (hourly cron) directly into `graded_market` + `graded_market_sales` tables. The iOS app's `/price-comp` Edge Function is a thin read-through over those tables. Aggregator/swap-out strategy is a tcgcsv concern.
2. **Image recognition (raw cards)** — deferred to sub-project #9. Decision between a third-party service (Ximilar) and a custom model happens there.
3. **Offline-first vs online-only** — offline-first, both store and card-show environments first-class.
4. **Raw + graded decoupling** — the raw Pokémon catalog (`tcg_*` tables) and the graded-card surface (`graded_*` tables) are architecturally independent. No foreign keys, no shared identities, no join tables between them. Any "show raw + graded side-by-side" UX is a presentation-layer concern in the consuming apps. Rationale in memory note *"Raw and graded card data stay decoupled"*.
