# Bulk Scan & Comp — Design Spec

**Sub-project:** #5 — Bulk scan mode
**Date:** 2026-04-22
**Status:** Design approved; awaiting implementation plan

## Summary

The MVP headline feature. A hobby store owner can bulk-scan a stack of slabs, see per-slab blended comps from eBay sold listings (via an aggregator), and produce a reviewable saved lot that later sub-projects extend into offers and transactions.

This spec covers sub-project #5 end-to-end, including the minimum slices of sub-projects #1–#4 needed to ship it:

- Auth + `store` with a single-member `store_members` row (from #1)
- Camera + cert OCR + `/cert-lookup` Edge Function (from #3). The Edge Function **imports pure libraries from the `tcgcsv` repo** (`src/graded/sources/*` and `src/graded/identity.ts`) for grader lookup and identity normalization — it does not re-implement them.
- `/price-comp` Edge Function (from #4) — a thin reader over `graded_market` (populated by the tcgcsv hourly eBay ingest). Blended price + confidence are derived server-side from `graded_market` fields.

**What this sub-project owns:** the tenant tables (`stores`, `store_members`, `lots`, `scans`) and their RLS policies; the `/cert-lookup` and `/price-comp` Edge Functions; the iOS app.

**What this sub-project references but does not own:** the entire graded-card data surface — `graded_card_identities`, `graded_cards`, `graded_market`, `graded_market_sales`, `graded_card_pops`, `graded_cert_sales`, `graded_ingest_runs` — all owned by the **tcgcsv sub-project** (design at `tcgcsv/docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md`). Raw-card tables (`tcg_*`) are also owned by tcgcsv and **stay architecturally decoupled** from the graded domain (no FKs, no shared identities) — see the memory note *"Raw and graded card data stay decoupled"*.

Everything else — offers/transactions/vendor DB/margin rules/inventory/raw-card UX — is deliberately deferred.

## Goals

1. A store owner can scan 30 slabs in under 4 minutes and see a defensible price per slab.
2. The feature works end-to-end offline (card show, spotty wifi) with transparent sync state.
3. Data model supports being extended into offers and transactions (sub-project 6) **without schema migration**.
4. Multi-store tenancy is correct from day one (sub-project 1 extends it without schema migration).
5. Every external dependency (aggregator, grader APIs) is replaceable without iOS changes.

## Non-goals

- Offer sheets, vendor attachment, margin rules, "show customer" mode — sub-project 6/7.
- Raw card identification — sub-project 9.
- Pop reports, cross-grade comparison, grade arbitrage — sub-project 4 beyond v1.
- Analytics dashboards — sub-project 8.
- Android, web dashboard, push notifications — sub-project 12.
- Label-vs-cert cross-check fraud detection — differentiator; leave an extension seam but do not implement.

## Architecture

### Three tiers plus one shared-data sibling

```
┌──────────────────────┐     ┌──────────────────────────────────────┐
│  iOS App             │     │  Supabase (shared across monorepo)   │
│  ─────────           │     │  ─────────────────────────────────   │
│  SwiftUI views       │     │  Postgres + RLS                      │
│  SwiftData cache     │◄───►│    owned by THIS sub-project:        │
│  Vision OCR          │     │      stores, store_members,          │
│  AVFoundation camera │     │      lots, scans                     │
│  Outbox + sync       │     │                                      │
│                      │     │    owned by tcgcsv sub-project:      │
│                      │     │      graded_card_identities,         │
│                      │     │      graded_cards, graded_market,    │
│                      │     │      graded_market_sales,            │
│                      │     │      graded_card_pops, etc.          │
│                      │     │      (raw: tcg_*, decoupled)         │
│                      │     │                                      │
│                      │     │  Auth (email / OAuth)                │
│                      │     │                                      │
│                      │     │  Edge Functions (owned here):        │
│                      │     │    /cert-lookup — imports tcgcsv     │
│                      │     │        graded libs (psa, cgc, bgs,   │
│                      │     │        sgc, tag, identity.ts)        │
│                      │     │    /price-comp — reads graded_market │
└──────────────────────┘     └──────────────────────────────────────┘
                                              ▲
                                              │  writes (service role)
                                              │
                             ┌────────────────┴───────────────────┐
                             │  tcgcsv repo (scheduled workers)   │
                             │  ──────────────────────────────    │
                             │  GH Actions crons:                 │
                             │    raw tcgcsv (daily)              │
                             │    graded ebay sold (hourly)       │
                             │    graded pop reports (weekly)     │
                             │                                    │
                             │  Calls: tcgcsv.com, eBay, PSA,     │
                             │         CGC, BGS, SGC, TAG APIs    │
                             └────────────────────────────────────┘
```

### Key boundaries

- **iOS never calls externals directly.** Grader API keys and eBay credentials live with the tcgcsv repo (workers) and its pure libraries, which the Edge Functions import server-side. The app knows exactly two external-facing endpoints: `/cert-lookup` and `/price-comp`. Swapping data sources later is a tcgcsv-library change.
- **Supabase is the source of truth; SwiftData is a cache.** Reads hit SwiftData first and refresh from Supabase in the background. Writes go into a local `outbox` table and flush to Supabase when online.
- **Auth is scoped by `store_id` via RLS.** Every tenant table query is filtered server-side; the app cannot accidentally leak across stores.
- **Raw and graded domains stay decoupled.** The scan pipeline lives entirely in the graded domain (`graded_card_identities`, `graded_cards`, `graded_market`). Raw tcgcsv product rows are never referenced from scans. If a later feature wants to show raw + graded pricing side-by-side, that matching is a presentation-layer concern in the iOS app, not a schema concern.

### Request path for a single bulk scan

1. OCR recognizes cert text in a camera frame → a `Scan` row is inserted locally with `status = pending_validation` in the **same SwiftData transaction** as an `OutboxItem` of kind `cert_lookup_job`.
2. `OutboxWorker` pops the job → `POST /cert-lookup` with `{grader, cert_number}`.
3. Edge Function imports the tcgcsv graded libraries, calls the right grader source (`psa.ts`, `cgc.ts`, etc.), runs `normalizeIdentity()` → upserts `graded_card_identities` and `graded_cards` (service role, idempotent on unique keys), and returns `{graded_card_identity_id, graded_card_id, grade, card fields}`.
4. Worker updates the local `Scan`: `status = validated`, `graded_card_identity_id`, `graded_card_id`, `grade`. Enqueues an `OutboxItem` of kind `price_comp_job`.
5. Worker pops the comp job → `POST /price-comp` with `{graded_card_identity_id, grading_service, grade}`.
6. Edge Function reads the latest `graded_market` row for `(identity_id, grading_service, grade)`. Derives `blended_price_cents` (median), `confidence` (from sample counts), velocities (from `sample_count_30d`, `sample_count_90d`), and the last-N sold listings (from `graded_market_sales`). Returns the response shape the client expects. **No aggregation happens here** — that's tcgcsv's hourly ingest's job.
7. SwiftData caches the response as a `GradedMarketSnapshot` row keyed by `(identity_id, grading_service, grade)`. UI re-renders the slab's row with the price.

Offline: steps 2–6 sit in the outbox with `status = pending` and a visible "pending validation" / "pending comp" badge in the UI. User can keep scanning indefinitely. When `NWPathMonitor` reports connectivity, the worker drains.

## Data model

### Postgres schema (Supabase)

**Identity & tenancy**

```sql
create table stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create type store_role as enum ('owner', 'manager', 'associate');

create table store_members (
  store_id uuid not null references stores(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role store_role not null,
  created_at timestamptz not null default now(),
  primary key (store_id, user_id)
);
```

**Graded-card tables — REFERENCED, NOT OWNED.** The tcgcsv sub-project owns `graded_card_identities`, `graded_cards`, `graded_market`, `graded_market_sales`, `graded_card_pops`, `graded_cert_sales`, and `graded_ingest_runs`. See the tcgcsv design for exact column definitions. This sub-project:

- **Reads** `graded_card_identities`, `graded_cards`, `graded_market`, `graded_market_sales` from the iOS app via Edge Functions (RLS allows `SELECT` for authenticated users on tcgcsv tables).
- **Writes** `graded_card_identities` and `graded_cards` through `/cert-lookup` using a service-role client (when the grader returns a cert the tcgcsv ingest hasn't seen yet). The Edge Function calls `normalizeIdentity()` from the tcgcsv graded library and performs the same upserts the scheduled ingest would.
- **Does not touch** `graded_market`, `graded_market_sales`, `graded_card_pops`, `graded_cert_sales`, `graded_ingest_runs` — those are populated exclusively by tcgcsv workers.

**Tenant data** — OWNED by this sub-project.

```sql
create type lot_status as enum ('open', 'closed', 'converted');

create table lots (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references stores(id),
  created_by_user_id uuid not null references auth.users(id),
  name text not null,
  notes text,
  status lot_status not null default 'open',
  -- progressive columns (null in MVP, filled by sub-project 6):
  vendor_name text,
  vendor_contact text,
  offered_total_cents bigint,
  margin_rule_id uuid,                     -- fk to future margin_rules
  transaction_stamp jsonb,                 -- {paid_at, payment_method, ...}
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index lots_store_id on lots(store_id);
create index lots_store_status on lots(store_id, status);

create type grader as enum ('PSA', 'BGS', 'CGC', 'SGC', 'TAG');
create type scan_status as enum ('pending_validation', 'validated', 'validation_failed', 'manual_entry');

create table scans (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references stores(id),
  lot_id uuid not null references lots(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  grader grader not null,
  cert_number text not null,
  grade text,                                           -- filled after /cert-lookup
  graded_card_identity_id uuid references graded_card_identities(id),  -- added once tcgcsv migration has landed
  graded_card_id uuid references graded_cards(id),                     -- per-cert row; added once tcgcsv migration has landed
  status scan_status not null default 'pending_validation',
  ocr_raw_text text,
  ocr_confidence real,
  captured_photo_url text,
  offer_cents bigint,                                   -- filled by sub-project 6
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index scans_lot_id on scans(lot_id);
create index scans_store_status on scans(store_id, status);
create unique index scans_cert_per_lot on scans(lot_id, grader, cert_number);
```

**Migration sequencing:** the `scans.graded_card_identity_id` and `scans.graded_card_id` FKs require the tcgcsv migration to have landed first. Plan 1 (walking skeleton) intentionally omits these two columns; Plan 2 (cert validation) adds them via `alter table` once `graded_card_identities` and `graded_cards` exist.

**Pricing surface** (read-only — populated by tcgcsv hourly eBay ingest)

- `graded_market(identity_id, grading_service, grade)` → latest aggregate: `low_price`, `median_price`, `high_price`, `last_sale_price`, `last_sale_at`, `sample_count_30d`, `sample_count_90d`, `updated_at`.
- `graded_market_sales` → raw sold listings feeding the aggregate. The `/price-comp` Edge Function joins these two to produce the client payload.

The iOS app caches `/price-comp` responses in a local `GradedMarketSnapshot` row (SwiftData, see "SwiftData mirrors" below). Invalidation is response-driven: every `/price-comp` call upserts the snapshot with a fresh `fetched_at` timestamp; clients show "last refreshed X minutes ago" and the `CompRepository` refreshes in the background on open.

### Row Level Security

Policies (sketch — full policy SQL belongs in migration files):

- `stores`, `store_members`, `lots`, `scans` (OWNED here): `SELECT/INSERT/UPDATE` only where `store_id` is in the caller's memberships (`exists (select 1 from store_members where user_id = auth.uid() and store_id = <row>.store_id)`). No `DELETE` from the app for `scans` or `lots` — soft-delete via a status column when that becomes necessary.
- `graded_*`, `tcg_*` (OWNED by tcgcsv): RLS is set by tcgcsv — public `SELECT` for authenticated users, service-role only for `INSERT/UPDATE/DELETE`. This sub-project does not redefine those policies.
- Every policy has paired positive and negative test cases in the RLS test suite.

### SwiftData mirrors (device-side)

One `@Model` per Postgres entity we cache, plus `OutboxItem`:

- `GradedCardIdentity` — cached indefinitely; upserted when a `/cert-lookup` response arrives. Mirrors tcgcsv's `graded_card_identities`.
- `GradedCard` — per-cert row (grading_service + cert_number + grade + identity_id). Upserted with each `/cert-lookup`. Mirrors tcgcsv's `graded_cards`.
- `GradedMarketSnapshot` — cache of the most recent `/price-comp` response keyed by `(identity_id, grading_service, grade)`. Has a `fetched_at` stamp; refresh-on-open.
- `Lot` — writable; user-owned
- `Scan` — writable; user-owned
- `Store`, `StoreMember` — lightweight; cached at sign-in
- `OutboxItem` — local-only; never syncs

`OutboxItem` fields:

```swift
@Model
final class OutboxItem {
    var id: UUID
    var kind: OutboxKind              // enum: insertScan, updateScan, insertLot, updateLot, certLookupJob, priceCompJob
    var payload: Data                 // JSON
    var status: OutboxStatus          // pending, inFlight, completed, failed
    var attempts: Int
    var lastError: String?
    var createdAt: Date
    var nextAttemptAt: Date
}
```

## iOS application structure

Feature-folder layout mapped so each sub-project slots into its own directory:

```
slabbist/
├── slabbistApp.swift
├── Core/
│   ├── Networking/ (SupabaseClient, EdgeFunctions)
│   ├── Persistence/ (ModelContainer, Outbox/)
│   ├── Sync/ (SyncCoordinator, Reachability)
│   ├── Models/ (GradedCardIdentity, GradedCard, GradedMarketSnapshot, Lot, Scan, Store, StoreMember)
│   ├── DesignSystem/ (Tokens, Theme, Components/)
│   └── Utilities/ (Currency, Logger)
├── Features/
│   ├── Auth/ (sub-project 1)
│   ├── Scanning/ (sub-projects 3 + 5: Camera/, SingleScan/, BulkScan/, Review/)
│   ├── Comp/ (sub-project 4: CompRepository, CompCardView, SoldListingsSheet)
│   ├── Lots/ (sub-project 5)
│   └── Settings/
└── Resources/ (Assets, Localizable.xcstrings)
```

Rules:

- `Core/` never imports from `Features/`.
- Features don't import each other; shared code moves to `Core/`.
- One folder per sub-project — zero reshuffling when later sub-projects land.
- MVVM-ish: SwiftUI `View` + `@Observable` ViewModel + repository for SwiftData/Supabase access. View models are testable without a simulator.

Full directory tree, including tests, is in the "iOS app structure" section of the design conversation; it should be scaffolded to match exactly when the implementation plan lands.

## Scan → comp pipeline

### State machine per `Scan`

```
  capturing ──ocr ok──► pending_validation ──cert found──► validated ──comp fetched──► comp attached
     │                          │
     │ ocr fail                 │ cert 404 / timeout
     ▼                          ▼
  manual_entry             validation_failed
     │                          │ user re-enters
     └─► pending_validation ◄───┘
```

### Capture loop

- `AVCaptureSession` streams at 30 fps into a `VNRecognizeTextRequest` (Apple Vision).
- `CertOCRRecognizer` applies a grader-specific regex to each recognition frame. Initial patterns:
  - PSA: 8–9 digit sequence near "PSA" keyword
  - BGS: 10-digit cert near "BGS" or "BECKETT"
  - CGC: 10-digit cert near "CGC"
  - SGC: 8-digit cert near "SGC"
  - TAG: format per TAG cert; exact regex calibrated against real label fixtures
- Stability gate: same value across 3 consecutive frames within ~200ms and Vision confidence >0.85 → fire capture.
- OCR confidence thresholds (0.85 stable capture, 0.5 fallback trigger) are declared as `CertOCRConfig` constants to enable calibration against real slab photos without a code change. Calibration is a follow-up task post-launch.

### Capture mode UX (MVP ships mode A; B and C behind feature flags)

- **Mode A — one-by-one in hand**: camera pauses briefly on capture; "got it" chip; resumes.
- **Mode B — continuous**: camera keeps running with an in-memory dedup set keyed by `(grader, cert_number)` for the session. Accepted risk: app crash mid-session resets dedup and allows re-scans; user can remove duplicates in review.
- **Mode C — tripod**: same as A with stronger haptic and instant transition.

Mode selector lives in the `BulkScanView` top bar but is a no-op for MVP except for A.

### Write path (local-first)

1. `Scan` inserted into SwiftData with `status = pending_validation`.
2. `OutboxItem(kind: .insertScan)` created in the same transaction.
3. `OutboxWorker` picks up on its next tick or on `NWPathMonitor` online transition.

### `/cert-lookup` Edge Function contract

- Request: `{ grader, cert_number }` (JWT auth)
- Response 200: `{ graded_card_identity_id, graded_card_id, grade, identity: { game, language, set_code, set_name, card_number, card_name, variant, year } }`
- Response 404: `{ code: "CERT_NOT_FOUND" }` — `Scan` moves to `validation_failed`; UI surfaces "Cert not found — re-enter?"
- Response 5xx / timeout: worker retries with exponential backoff (30s, 2m, 10m, capped at 1h)
- **Implementation:** imports `src/graded/sources/<service>.ts` and `src/graded/identity.ts` from the tcgcsv repo as a workspace dependency or deno-compatible package. Runs the source, then `normalizeIdentity()`, then upserts `graded_card_identities` + `graded_cards` via the Supabase service-role client. No per-service logic is re-implemented here.
- Offline: job sits in outbox; "pending validation" badge in UI

### `/price-comp` Edge Function contract

- Request: `{ graded_card_identity_id, grading_service, grade }` (JWT auth)
- Response 200: `{ blended_price_cents, confidence, velocity_7d, velocity_30d, velocity_90d, sold_listings[], fetched_at }`
  - `blended_price_cents` = `graded_market.median_price_cents` (or best-available from the row)
  - `confidence` = function of `sample_count_30d` and `sample_count_90d` (piecewise: 0 samples → 0.0; 30d ≥ 8 → 1.0; linear between)
  - `velocity_7d/30d/90d` = derived from `graded_market_sales` with a windowed count (the Edge Function can compute `velocity_7d` on the fly since `graded_market` only carries 30d/90d counts)
  - `sold_listings[]` = last N rows from `graded_market_sales` matching the key, joined to `{sold_price, sold_at, title, url, source}`
  - `fetched_at` = now; SwiftData caches this
- Response 404: `{ code: "NO_MARKET_DATA" }` — no `graded_market` row yet for this key. Client shows "No recent comps" with `confidence = 0`.
- Behavior: **thin read-through**. All aggregation lives in the tcgcsv hourly ingest (`graded/aggregates.ts`). The Edge Function only transforms shape.
- Rate limits: Supabase-level (per-project), not needed in the Function since there's no external API call.

### Read path

- `CompRepository.snapshot(for: Scan)` returns the most recent `GradedMarketSnapshot` from SwiftData, filtered by `(identity_id, grading_service, grade)`.
- On miss or stale (configurable — default 60 minutes), enqueues a refresh via the outbox (`price_comp_job`).
- SwiftUI binds to a SwiftData query; when a new `GradedMarketSnapshot` lands, the view re-renders automatically.

### Outbox worker specifics

- **Priority order:** `cert_lookup_job` > `price_comp_job` > `insert_scan` > `update_scan`. (Validation unblocks comp; comp is what the user is waiting to see.)
- **Dedup:** if a `price_comp_job` for `(graded_card_identity_id, grading_service, grade)` is already queued, a new one collapses in. Similarly for `cert_lookup_job` on `(grader, cert_number)`.
- **Max concurrency:** 4 in-flight requests; tuned against Supabase project quotas.
- **Persistence:** outbox lives in SwiftData so it survives app restarts.
- **Lifecycle:** runs continuously in foreground; triggers on `NWPathMonitor` online transitions; optional BGProcessingTask for background drain post-MVP.

### Snapshot freshness

`GradedMarketSnapshot` is refreshed on open — the client calls `/price-comp` any time a scan's detail view is shown and the local snapshot's `fetched_at` is older than 60 minutes (configurable). Since `graded_market` itself is updated hourly by the tcgcsv ingest, any more aggressive refresh cadence would be wasted work.

### Invariants

1. A `Scan` insert and its `OutboxItem` must happen in a single SwiftData transaction or neither.
2. An `OutboxItem` is only marked `completed` after the server confirms persistence. No fire-and-forget.
3. A `GradedMarketSnapshot` is never returned as "fresh" if its `fetched_at` is older than the refresh threshold — the repo always checks.
4. Every cross-store read is filtered by `store_id` in the repo layer — belt-and-suspenders with RLS.
5. The iOS app never reads a `tcg_*` table. Raw-card data is out of scope for the graded scan pipeline.

## UI surface

Five screens + design-system primitives. Visual/brand treatment happens in the implementation step via the `frontend-design` + `mobile-ios-design` skills; this spec nails the structural choices.

### `LotsListView` — home tab

- Header: store name + user avatar + settings.
- Primary CTA: **"New bulk scan"**.
- Sections: **Open lots** (status `open`), **Recent lots** (closed, last 30d), **All lots** (link to search later — punted for MVP).
- Row: lot name, scan count, total comp value, last-updated time, status chip.
- Empty state: onboarding card + CTA.

### `NewLotSheet`

- Presented as a sheet.
- Fields: lot name (auto-suggested, editable); optional collapsed "Add details" for vendor/notes.
- Primary: **"Start scanning"** → create `Lot` locally (status `open`) → outbox the insert → push `BulkScanView`.

### `BulkScanView` — the workbench

```
┌───────────────────────────────────────────┐
│ ← Lot name            [Mode: A ▾]   ⏸    │
├───────────────────────────────────────────┤
│            CAMERA PREVIEW                 │
│     (crosshair + detected cert overlay)   │
├───────────────────────────────────────────┤
│  ⟵ swipe up for full queue ⟶              │
│  ┌──────┬──────┬──────┬──────┬──────┐    │
│  │ slab │ slab │ slab │ slab │ slab │    │
│  │  ✓   │ ⏳   │  ✓   │ ⏳   │  ✓   │    │
│  │ $120 │ ...  │ $45  │ ...  │ $310 │    │
│  └──────┴──────┴──────┴──────┴──────┘    │
│  12 scanned · 8 comped · 4 pending       │
├───────────────────────────────────────────┤
│        [  Done — Review Lot  ]            │
└───────────────────────────────────────────┘
```

States & transitions:

- **Camera permissions denied:** preview replaced by empty state with "Open Settings" + "Enter cert manually" actions.
- **OCR capture:** brief flash + haptic; slab slides into the horizontal queue; pending badge flips to price when comp lands.
- **Manual entry fallback:** long-press on preview or tap ⌨ icon → sheet with grader picker + cert number field.
- **Offline indicator:** non-modal strip above the queue when `NWPathMonitor` reports no network: "Offline — syncing 12 items".
- **Pause (⏸):** stops camera session (saves battery during card-show setup pauses); tap resumes.
- **Mode selector (A/B/C):** MVP only exposes A; B/C behind a feature flag.

### `LotReviewView`

- Grouped list of scans: **Ready** (comp attached), **Pending** (validation or comp in flight), **Issues** (validation_failed / manual correction needed).
- Row: thumbnail, card name + set + grade, comp price, confidence meter, overflow menu (remove, re-scan, force manual).
- Header summary: total slabs, total comp value, total pending, confidence-weighted aggregate.
- Bottom action bar: **Close lot**, **Export CSV**.
- PDF export deferred to sub-project 6 (offer sheets).

### `ScanDetailView`

- Big slab photo.
- Card identity (from grader): set, name, number, grade, year, variant.
- Comp section: blended price (large), confidence meter, velocity breakdown (7/30/90d), sparkline, last 5 sold listings (tappable to source URLs).
- Actions: **Remove from lot**, **Re-scan**, **Report issue** (future fraud detection).
- **Edit offer** action stubbed out / hidden for MVP (enabled by sub-project 6).

### Navigation

Three-tab MVP: **Lots** (home) | **Scan** (shortcut to most-recent-open-lot's scanner, or `NewLotSheet`) | **More** (settings, sign out, legal).

### Design-system dependencies in `Core/DesignSystem/Components`

- `PriceBadge` — money chip, handles placeholder/pending/fresh states
- `ConfidenceMeter` — horizontal bar with tap-to-explain tooltip
- `Sparkline` — `Canvas`-based micro-chart for 7/30/90d
- `SlabThumbnail` — rounded photo tile with status overlay

## Error handling

| Class | Examples | User-visible behavior |
|---|---|---|
| **Network transient** | offline, timeout, 5xx | Silent; outbox retries with backoff; queue counter updates |
| **Validation miss** | grader 404, unreadable cert | Scan → `validation_failed`; Issues section in review; retry/manual-correct |
| **Comp unavailable** | no recent sold listings | Row renders "No recent comps" + confidence 0; card identity still visible |
| **Auth expired** | session refresh failure | One auto-refresh; on second failure, prompt re-auth; outbox pauses; scans still land locally |
| **SwiftData failure** | disk full, corruption | Crash-recovery screen with JSON export of queued scans. Never silently drop data. |
| **Camera/permissions** | denied, restricted, hardware unavailable | Empty state with "Open Settings" + "Enter cert manually" |
| **Quota exceeded** | aggregator 429, cost ceiling | Worker long-backs-off; "Comps slowed — catching up" banner (not a failure) |
| **Duplicate cert in lot** | user rescans the same slab in mode A; race in mode B dedup | Unique index `scans_cert_per_lot` rejects with 409. OutboxWorker treats 409 as success (scan already persisted), marks local scan as duplicate-of-existing, and removes the redundant row from SwiftData. No user-visible error. |

## Testing strategy

### Unit (Swift Testing / XCTest)

- `CertOCRRegex` — fixture strings per grader; known false-positives (expiration dates, barcode digits)
- `OutboxWorker` — mock Supabase client; state transitions, retry backoff curve, priority ordering, dedup
- `SyncCoordinator` — offline→online transitions, concurrent writes, outbox draining
- `CompRepository` — snapshot-freshness enforcement; stale vs missing vs fresh branches; race between local cache hit and server refresh
- Money math — cents-only arithmetic; no float rounding creep

### Integration

- Supabase-side: migration tests; RLS policy tests for our tenant tables (positive + negative per policy). tcgcsv owns its own RLS tests.
- Edge Function tests: `/cert-lookup` with mocked tcgcsv graded libraries; `/price-comp` against seeded `graded_market` + `graded_market_sales` rows.
- End-to-end: iOS simulator → local Supabase stack → seeded graded data (from the tcgcsv project's test fixtures when available, or a small seed file for MVP).

### UI (XCUITest)

- Happy path: new lot → scan 3 slabs → review → close
- Offline path: airplane mode → scan 3 → back online → sync drains → comps render
- Manual entry fallback
- Permission-denied empty states

### Fixtures

- Growing corpus of real slab photos per grader (anonymized) for OCR regression
- Seeded aggregator response snapshots for deterministic comp rendering in tests

## Observability

- Structured logs via OSLog with subsystem `com.slabbist.{module}`
- MVP metrics: OCR success rate per grader; outbox retry counts; median time-to-comp per scan; validation 404 rate; aggregator 429 rate
- Crash reporting: Apple MetricKit; revisit Sentry/Crashlytics once paying users exist

## Out of scope (explicit)

- **Offer / vendor / transaction model** on `lots` — columns exist but stay null; UI ignores them (sub-project 6).
- **Margin rules / role visibility / buylist surfacing** in the comp view (sub-project 7).
- **PDF offer-sheet export** (sub-project 6).
- **Pop reports, cross-grade comparison, grade arbitrage** (expansion of sub-project 4).
- **Raw card ID** (sub-project 9).
- **Push notifications, multi-device sync, audit log, web dashboard, Android** (sub-project 12).
- **Label-OCR fraud cross-check** — leave an extension seam in the scan pipeline; do not build.

## Follow-up tasks (captured for the plan step)

- Calibrate OCR confidence thresholds against real slab photos post-launch.
- Calibrate outbox concurrency numbers against real usage.
- Tune the 60-minute `GradedMarketSnapshot` refresh threshold after observing tcgcsv ingest cadence and real user behavior.
- Design polish: exact visual treatment of the `PriceBadge`, `ConfidenceMeter`, `Sparkline`, and `BulkScanView` happens at implementation via `frontend-design` + `mobile-ios-design` skills.
- Define the confidence-score function precisely (piecewise or analytic) once we have the first batch of real `graded_market` data to calibrate against.

## Cross-cutting references

- Feature capture: [`docs/product/README.md`](../../product/README.md) and `sub-projects/`.
- **tcgcsv data pipeline design** (owns all graded + raw card tables): [`tcgcsv/docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md`](../../../tcgcsv/docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md)
- Raw/graded decoupling rationale: see memory note *"Raw and graded card data stay decoupled"*.
- Supabase schema lives at the monorepo path `/Users/dixoncider/slabbist/supabase/migrations/`. Migrations here and in the tcgcsv repo share that directory and must be timestamp-ordered such that tcgcsv's graded-table migration lands before this sub-project's `scans.graded_card_identity_id` / `scans.graded_card_id` FK-adding migration.
