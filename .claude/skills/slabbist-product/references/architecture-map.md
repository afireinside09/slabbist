# Slabbist Architecture Map

Enough architecture to reason about *product* decisions and find *where code lives*. The hard, enforceable rules live in `CLAUDE.md` — this defers to it and does not restate it.

## Product-reasoning invariants

- **Raw / graded decoupling.** `tcg_*` (raw, TCGPlayer-indexed) and `graded_*` tables share no FKs, identities, or join tables. Matching them for side-by-side UX is a consumer-side concern, done independently on the client.
- **Offline-first outbox.** All writes go through `OutboxDrainer` (`Core/Sync/`); repositories under `Core/Data/Repositories/` are the only layer that talks to Supabase. A new write surface extends `OutboxKind` + `OutboxPayloads` + the drainer.
- **Hero flow.** scraper → Postgres tables → Edge Function → app. The scraper populates `graded_*`/`tcg_*`; iOS scans call Edge Functions that import the scraper's libraries server-side. iOS never re-implements aggregator logic.
- **Watchlist, not catalog.** eBay ingest tracks a curated `graded_watchlist`. Scans auto-promote popular identities into it; arbitrary on-demand lookups happen on-device.
- **Multi-tenant.** Every data table is `store_id`-scoped with RLS; new tables need RLS policies tested under `supabase/tests/`.
- **Cache + per-source fallback.** Comps read a cache and fall back per source: a fresh cache hit, a stale-but-safe value if a source is down, or a live fetch on miss. Prices move ~daily, so stale is acceptable.

## Comp-source landscape

Multiple sources feed comps and signals; they are independent and fan out in parallel.

| Source | Role | Notes |
|---|---|---|
| **Pokemon Price Tracker (PPT)** | Primary graded pricing | eBay-aggregate per (grader, grade) with multi-month history and a per-grade ladder in one call. |
| **Poketrace** | Secondary graded pricing + rich metadata | Adds trend / confidence / sale-count dimensions; backfills the Grade Gains lookup. |
| **eBay sold listings / movers** | Momentum signal | Drives Movers; momentum, not a live per-slab comp. Uses its own eBay credentials. |
| **PriceCharting** | Comp source (see spec) | `2026-05-05-pricecharting-comp-design.md`. |
| **Pop reports (PSA/CGC/BGS/SGC/TAG)** | Population stats | Submission-difficulty / gem-rate signal; scraped on a schedule; **not** a pricing source. |

**Reconciliation.** PPT and Poketrace run in parallel on every comp request; the reconciled headline blends both, falling back to whichever source succeeds. Spec: `2026-05-13-poketrace-first-class-fanout-design.md`.

## Code map

Where the moving parts live, so a session can navigate fast.

**iOS (`ios/slabbist/slabbist/`):**
- `Features/` — one folder per surface: `Lots`, `Scanning` (`Camera`, `BulkScan`), `Comp`, `Movers`, `Offers`, `Vendors`, `Transactions`, `Grading` (`Capture`, `History`, `Report`), `CertLookup`, `Stores`, `Settings`, `Auth`, `Shell`.
- `Core/Data/DTOs/` — wire types: e.g. `MoverDTO`, `MoversSetDTO`, `MoverEbayListingDTO`, `ScanDTO`, `LotDTO`, `GradeEstimateDTO`, `PriceHistoryDTO`, `VendorDTO`, `StoreDTO`, `EbayListingBrowseRowDTO`.
- `Core/Data/Repositories/` — the only Supabase-facing layer: `MoversRepository`, `ScanRepository`, `LotRepository`, `GradeEstimateRepository`, `VendorRepository`, `TransactionRepository`, `StoreRepository`, `StoreMemberRepository`, `GradePhotoUploader`, `SupabaseRepository`, `RepositoryProtocols`.
- `Core/Data/Mapping/` — DTO ↔ SwiftData model mapping.
- `Core/Sync/` — `OutboxDrainer` and the offline-first sync machinery; `Core/Persistence/Outbox/`.

**Supabase (`supabase/`):**
- `migrations/` — the only place schema is defined.
- `functions/` — Edge Functions: `price-comp`, `cert-lookup`, `grade-estimate`, `lot-offer-recompute`, `transaction-commit`, `transaction-void`, `purge-grade-photos`, `ebay-account-deletion`, `_shared`.
- `tests/` — RLS tests (`rls_*.sql`).

**Scraper (`scraper/`):** the ingest that populates `tcg_*` / `graded_*`; the Edge Functions import its libraries. Never defines schema.

**Wiring a new Edge Function shape:** do a live `Decodable` round-trip against a real response — curl smoke tests miss shape mismatches.
