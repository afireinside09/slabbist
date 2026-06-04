# Product-Intent Knowledge Base Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author a `slabbist-product` Claude skill that captures the app's durable product intent (who/why/IA/value-loops/vocabulary/invariants) with progressive disclosure and spec pointers.

**Architecture:** One project skill under `.claude/skills/slabbist-product/` — a lean `SKILL.md` entry point plus three reference files loaded on demand. Content is durable-intent-with-pointers: it captures slow-to-change knowledge and points to authoritative specs for specifics, never restating formulas/thresholds/shapes. It does not duplicate `CLAUDE.md` (commands + hard rules) or `.impeccable.md` (design system) — it references them.

**Tech Stack:** Markdown only. No application code. Verification is shell-based (file existence, frontmatter presence, line budget, spec-pointer resolution, anti-duplication grep).

**Out of scope:** The hardening strategy (strict DB types, drift guards, quality gates) is sketched in the spec and deferred to its own brainstorm → spec → plan. This plan authors the knowledge base only.

**Source of truth:** `docs/superpowers/specs/2026-06-01-product-intent-kb-design.md`.

---

### Task 1: Skill entry point (`SKILL.md`)

**Files:**
- Create: `.claude/skills/slabbist-product/SKILL.md`

- [ ] **Step 1: Create the directory**

Run:
```bash
mkdir -p .claude/skills/slabbist-product/references
```

- [ ] **Step 2: Write `SKILL.md` with this exact content**

````markdown
---
name: slabbist-product
description: Use when planning, designing, or implementing any Slabbist iOS product feature — captures who the user is, the IA, the flagship value loops (movers, comps, grade-gains), domain vocabulary, and architectural invariants. Read before non-trivial product work.
---

# Slabbist — Product Intent

Durable product knowledge for Slabbist. This is the *why*. It points to authoritative specs for specifics (formulas, thresholds, response shapes) rather than restating them — those evolve, this doesn't.

**This skill does not duplicate:**
- `CLAUDE.md` — commands and hard architecture rules (it owns those).
- `.impeccable.md` — the design system (it owns that).

Read those directly for what they own. This skill links to specs in `docs/superpowers/specs/` for feature specifics.

## What Slabbist is

An iOS-first app for **hobby-store vendors / buy-side dealers** comping Pokémon slabs to make defensible cash offers. It is a **buy-side tool, not a collector vault**. Mockups sometimes speak collector language ("vault", "portfolio") — that is visual reference only and must never leak into product IA.

## Who the user is

A shop owner at the counter, a buyer at a card show, or a back-office operator clearing a consignment intake — processing **stacks of graded slabs**, often quickly, often in front of the seller, and needing a real number to anchor an offer.

Three jobs-to-be-done:
- *"What's this stack worth right now?"* — bulk scan → blended comp from real market sales.
- *"What can I offer and still make margin?"* — confidence-weighted estimate with a margin control.
- *"Get me out of the spreadsheet."* — lots open and close; CSV export; a transactions ledger.

**Not collectors.** The IA is buy-side: Lots / Scans / Comps / Offers. Don't port collector IA by reflex.

## Information architecture

Canonical IA: **Lots / Scans / Comps / Offers.** These map onto the real iOS surfaces under `ios/slabbist/slabbist/Features/`:

| IA concept | Feature surfaces |
|---|---|
| Lots | `Lots`, `Stores` |
| Scans | `Scanning` (incl. `BulkScan`), `CertLookup` |
| Comps | `Comp`, `Movers`, `GradeGains` |
| Offers | `Offers`, `Vendors`, `Transactions` |
| (cross-cutting) | `Grading` (pre-grade estimator), `Auth`, `Settings`, `Shell` |

## Value loops

One line each — read `references/value-loops.md` for purpose, the shape of the output, and the authoritative spec for each.

- **Movers** — ranked top gainers/losers from real eBay sales; the dealer's market-momentum indicator.
- **Graded card comps** — multi-source fan-out (PPT + Poketrace), reconciled into one *defensible number* with a per-grade ladder.
- **Grade gains / pre-grade estimator** — "is this raw card worth grading?": profit-spread ranking by set, plus photo-based sub-grade estimation.
- **Bulk scan / comp** — scan a stack fast (OCR cert → resolve → comp → lot); speed for offers made in front of the vendor.
- **Lots & offers** — the vendor workflow from open lot to paid, immutable transaction.

## Product invariants (in brief)

Read `references/architecture-map.md` for detail. Hard rules live in `CLAUDE.md`.

1. **Raw and graded are decoupled.** `tcg_*` and `graded_*` share no FKs or identities; side-by-side is a presentation concern.
2. **Offline-first via the outbox.** Writes go through `OutboxDrainer`; repos are the only Supabase layer.
3. **Hero flow: scraper → tables → Edge Function → app.** iOS never adds raw aggregator logic.
4. **Watchlist, not whole catalog.** eBay ingest is curated; scans auto-promote popular identities; on-demand lookups happen on-device.
5. **Defensible number, show the work.** Every comp cites source/date/confidence; the tool earns trust by being legible about uncertainty, never by performing it.

## When to load which reference

| Doing this | Read |
|---|---|
| Understanding what a feature is *for* | `references/value-loops.md` → then the cited spec |
| Decoding an unfamiliar term | `references/glossary.md` |
| Reasoning about data flow, comp sources, or where code lives | `references/architecture-map.md` |
| Commands, build, hard architecture rules | `CLAUDE.md` |
| Anything visual (palette, type, spacing, components) | `.impeccable.md` |
| Feature specifics (formulas, thresholds, shapes) | the spec cited in `value-loops.md` |
````

- [ ] **Step 3: Verify the file exists, has frontmatter, and is within the line budget**

Run:
```bash
test -f .claude/skills/slabbist-product/SKILL.md && \
head -1 .claude/skills/slabbist-product/SKILL.md | grep -qx -- '---' && \
grep -q '^name: slabbist-product$' .claude/skills/slabbist-product/SKILL.md && \
grep -q '^description: ' .claude/skills/slabbist-product/SKILL.md && \
echo "frontmatter OK" && \
wc -l < .claude/skills/slabbist-product/SKILL.md
```
Expected: prints `frontmatter OK` then a line count ≤ 150.

- [ ] **Step 4: Verify it does not duplicate the design system (no palette hex / token values)**

Run:
```bash
grep -nE '#08080A|oklch\(|rgba\(255' .claude/skills/slabbist-product/SKILL.md && echo "FOUND DESIGN TOKENS — REMOVE" || echo "no design-token duplication OK"
```
Expected: `no design-token duplication OK`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/slabbist-product/SKILL.md
git commit -m "feat(skill): add slabbist-product knowledge-base entry point"
```

---

### Task 2: Glossary reference (`references/glossary.md`)

**Files:**
- Create: `.claude/skills/slabbist-product/references/glossary.md`

- [ ] **Step 1: Write `glossary.md` with this exact content**

````markdown
# Slabbist Glossary

Domain vocabulary, grounded in how the specs use each term. Definitions are durable; for the mechanics behind a term, follow the value loop that uses it (`value-loops.md`).

| Term | Definition |
|---|---|
| **Slab** | A graded Pokémon card in a PSA/CGC/BGS/SGC/TAG holder. The primary buy unit. |
| **Cert number** | The unique serial on the slab holder (e.g. PSA 12345678). OCR'd from the label during a scan. |
| **Cert** | The certification on the slab — grader + grade (e.g. "PSA 10", "CGC 9.5"). |
| **Grade** | The numeric score (1–10, including half-grades). Each grade has its own market price. |
| **Grader / grading service** | The certifier: PSA, CGC, BGS, SGC, TAG. Each has its own pricing market and pop reports. |
| **Comp** | The market valuation of a graded slab from a data source. Includes a headline price, per-grade ladder, and metadata. |
| **Headline price** | The market price for the exact (grader, grade) of the slab in hand — the anchor for an offer. |
| **Per-grade ladder** | The matrix of prices across Raw / lower grades / 10 for the card. Supports crack-and-resubmit ("what's the upside if I regrade?") reasoning. |
| **Source** | The data feed behind a comp — e.g. `pokemonpricetracker`, `poketrace`. See `architecture-map.md`. |
| **Reconciled** | When multiple sources exist, the blended headline (e.g. average), with fallback to a single source if another fails. |
| **Fanout** | Fetching multiple comp sources in parallel on one request, failures isolated per source. |
| **Watchlist** | The curated subset of graded slabs the scraper tracks on a schedule. Not the whole catalog. |
| **Lot** | A named bundle of scans a vendor is selling. Stateful, from open to paid. |
| **Scan** | A single slab inside a lot — its cert, grade, comp, and buy price. |
| **Offer** | The store's proposed total and per-line prices sent to a vendor. Stateful: presented → accepted/declined. |
| **Buy price** | The store's per-slab offer, derived from comp × margin; the operator can override any line. |
| **Vendor ask** | A fallback manual-input price field for a scan. |
| **Margin** | The store's profit multiplier applied to comp (per-lot or per-store default). |
| **Vendor** | A contact in the store's vendor DB, with queryable purchase history. Store-scoped. |
| **Transaction** | The immutable ledger row created when an offer is paid. Line items snapshot vendor name, comps, and buy prices; voids are new rows, nothing mutates. |
| **Raw** | An ungraded, TCGPlayer-indexed card. Decoupled from graded identities (no FKs). |
| **Graded identity** | The normalized tuple `(game, language, set, card_number, variant, grader, cert_number)` that maps to graded comps. |
| **Pop report** | Grading population stats (how many copies graded, distribution by grade). Signals submission difficulty / gem-rate; not a comp source. |
| **Grade gains** | The profit from grading a raw card — the spread between its graded comp and its raw price (net of grading fee). Used to find high-ROI submissions. |
| **Trend** | A source-provided price direction (up / down / stable). |
| **Confidence** | A source-provided trust signal for a comp, driven by sale count and recency. |
| **Outbox** | The on-device queue of pending writes that sync to Supabase when online. The offline-first mechanism. |
| **store_id** | The multi-tenant scope key. All data tables are store-scoped via RLS. |
````

- [ ] **Step 2: Verify the file exists and is a non-trivial table**

Run:
```bash
test -f .claude/skills/slabbist-product/references/glossary.md && \
grep -c '^| \*\*' .claude/skills/slabbist-product/references/glossary.md
```
Expected: a count ≥ 20 (one row per defined term).

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/slabbist-product/references/glossary.md
git commit -m "feat(skill): add slabbist-product glossary reference"
```

---

### Task 3: Value-loops reference (`references/value-loops.md`)

**Files:**
- Create: `.claude/skills/slabbist-product/references/value-loops.md`

- [ ] **Step 1: Write `value-loops.md` with this exact content**

````markdown
# Slabbist Value Loops

For each flagship loop: its **purpose**, **why it matters**, and the **shape of the output** — then the authoritative spec(s) for specifics. No formulas or thresholds here; those live in the specs and evolve.

Spec paths are relative to `docs/superpowers/specs/`.

## Movers

**Purpose.** A ranked, scrollable list of top gainers and losers across English and Japanese cards, from real eBay sold listings, drillable to a per-set detail view.
**Why it matters.** The dealer's market-momentum indicator — where the action is, what's heating or cooling, whether to buy more or hold.
**Output shape.** Ranked rows: product name, set, absolute + percentage price movement, a thumbnail for fast visual recognition; filterable by language, searchable by set.
**→ Specs:** `2026-05-26-movers-row-thumbnail-design.md`

## Graded card comps (multi-source)

**Purpose.** When a slab is scanned, fan out to multiple comp sources in parallel and reconcile them into one number with supporting detail.
**Why it matters.** The **defensible number**. Multiple independent sources build trust; the per-grade ladder supports crack-and-resubmit decisions; recent history shows whether a price is climbing or about to tank.
**Output shape.** A reconciled headline price; per-source rows (price, range, trend, confidence); a togglable price history sparkline; a per-grade ladder (raw → top grade); a deep-link to verify against actual sales.
**→ Specs:** `2026-05-06-pokemonpricetracker-comp-design.md`, `2026-05-08-poketrace-comp-design.md`, `2026-05-13-poketrace-first-class-fanout-design.md`, `2026-04-23-ebay-sold-listings-comp-design.md`, `2026-05-05-pricecharting-comp-design.md`

## Grade gains / pre-grade estimator

Two distinct features answering "is this raw card worth grading?"

**Grade gains page.**
- *Purpose.* Rank raw cards by the profit spread between their graded comp and their raw price, filtered by price band and set.
- *Why it matters.* The buyer at the counter needs to know which raw cards are the easy wins before spending on submission.
- *Output shape.* A ranked list with a per-row profit breakdown and a grading-fee control; a detail view with raw price history alongside the graded comp.

**Pre-grade estimator (vision).**
- *Purpose.* From front/back photos of a raw card, estimate the grade it would receive.
- *Why it matters.* Answers "what will this grade?" upfront, before any submission cost. Centering is measured on-device (the one thing a vision model is worst at), keeping the estimate honest.
- *Output shape.* A hyper-critical grade estimate with sub-grade notes tied to visible features, a submit/don't verdict, and optional cross-grader predictions.
**→ Specs:** `2026-06-01-grade-gains-page-design.md`, `2026-04-23-pre-grade-estimator-design.md`

## Bulk scan / comp

**Purpose.** Scan a stack of slabs rapidly: OCR the cert → resolve it to a graded identity → fetch a comp → add the scan to a lot.
**Why it matters.** **Speed.** A dealer must make an offer in front of the vendor — minutes for a stack, not an hour in a spreadsheet. Scans queue offline and sync when connectivity returns, so a card show with spotty wifi is not a blocker.
**Output shape.** A growing list of scan rows, each populating with its comp; pending-validation / pending-comp badges while offline; uninterrupted scanning.
**→ Specs:** `2026-04-22-bulk-scan-comp-design.md`, `2026-05-07-outbox-worker-design.md`

## Lots & offers

**Purpose.** The vendor workflow: attach a vendor to a lot of scans, auto-fill per-line buy prices from comp × margin, send an offer, negotiate, and finalize to a paid transaction.
**Why it matters.** The **business transaction** — from "what's this stack worth?" to money in hand — in one coherent state machine. Capture is safe offline; finalizing to paid is the one boundary that must be online.
**Output shape.** A lot moving through states (open → priced → presented → accepted → paid, with decline/void/bounce-back paths); per-scan buy prices the operator can override; an immutable transaction ledger on payment.
**→ Specs:** `2026-05-08-store-workflow-design.md`, `2026-05-11-lot-flow-ux-improvements-design.md`, `2026-05-12-lot-margin-mode-toggle-design.md`
````

- [ ] **Step 2: Verify every cited spec pointer resolves to a real file**

Run:
```bash
cd /Users/dixoncider/slabbist
missing=0
for f in $(grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md' .claude/skills/slabbist-product/references/value-loops.md | sort -u); do
  if [ -f "docs/superpowers/specs/$f" ]; then echo "OK  $f"; else echo "MISSING  $f"; missing=1; fi
done
test "$missing" -eq 0 && echo "ALL POINTERS RESOLVE" || echo "BROKEN POINTERS — FIX BEFORE COMMIT"
```
Expected: every line `OK ...` then `ALL POINTERS RESOLVE`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/slabbist-product/references/value-loops.md
git commit -m "feat(skill): add slabbist-product value-loops reference"
```

---

### Task 4: Architecture-map reference (`references/architecture-map.md`)

**Files:**
- Create: `.claude/skills/slabbist-product/references/architecture-map.md`

- [ ] **Step 1: Write `architecture-map.md` with this exact content**

````markdown
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
| **Poketrace** | Sole graded pricing (PPT removed 2026-06-04) | eBay-sourced per (grader, grade): avg/low/high, trend, confidence, sale-count, per-tier ladder, multi-month history, and individual sold listings (Scale plan). Backfills the Grade Gains lookup. |
| **eBay sold listings / movers** | Momentum signal | Drives Movers; momentum, not a live per-slab comp. Uses its own eBay credentials. |
| **PriceCharting** | Comp source (see spec) | `2026-05-05-pricecharting-comp-design.md`. |
| **Pop reports (PSA/CGC/BGS/SGC/TAG)** | Population stats | Submission-difficulty / gem-rate signal; scraped on a schedule; **not** a pricing source. |

**Reconciliation.** PPT and Poketrace run in parallel on every comp request; the reconciled headline blends both, falling back to whichever source succeeds. Spec: `2026-05-13-poketrace-first-class-fanout-design.md`.

## Code map

Where the moving parts live, so a session can navigate fast.

**iOS (`ios/slabbist/slabbist/`):**
- `Features/` — one folder per surface: `Lots`, `Scanning` (`Camera`, `BulkScan`), `Comp`, `Movers`, `GradeGains`, `Offers`, `Vendors`, `Transactions`, `Grading` (`Capture`, `History`, `Report`), `CertLookup`, `Stores`, `Settings`, `Auth`, `Shell`.
- `Core/Data/DTOs/` — wire types: e.g. `MoverDTO`, `MoversSetDTO`, `MoverEbayListingDTO`, `ScanDTO`, `LotDTO`, `GradeEstimateDTO`, `GradeGainDTO`, `GradeGainSetDTO`, `PriceHistoryDTO`, `VendorDTO`, `StoreDTO`, `EbayListingBrowseRowDTO`.
- `Core/Data/Repositories/` — the only Supabase-facing layer: `MoversRepository`, `ScanRepository`, `LotRepository`, `GradeEstimateRepository`, `GradeGainRepository`, `VendorRepository`, `TransactionRepository`, `StoreRepository`, `StoreMemberRepository`, `GradePhotoUploader`, `SupabaseRepository`, `RepositoryProtocols`.
- `Core/Data/Mapping/` — DTO ↔ SwiftData model mapping.
- `Core/Sync/` — `OutboxDrainer` and the offline-first sync machinery; `Core/Persistence/Outbox/`.

**Supabase (`supabase/`):**
- `migrations/` — the only place schema is defined.
- `functions/` — Edge Functions: `price-comp`, `cert-lookup`, `grade-estimate`, `lot-offer-recompute`, `transaction-commit`, `transaction-void`, `purge-grade-photos`, `ebay-account-deletion`, `_shared`.
- `tests/` — RLS tests (`rls_*.sql`).

**Scraper (`scraper/`):** the ingest that populates `tcg_*` / `graded_*`; the Edge Functions import its libraries. Never defines schema.

**Wiring a new Edge Function shape:** do a live `Decodable` round-trip against a real response — curl smoke tests miss shape mismatches.
````

- [ ] **Step 2: Verify the file exists and the cited code paths are real**

Run:
```bash
cd /Users/dixoncider/slabbist
test -f .claude/skills/slabbist-product/references/architecture-map.md && \
test -d ios/slabbist/slabbist/Core/Sync && \
test -f ios/slabbist/slabbist/Core/Data/Repositories/MoversRepository.swift && \
test -d supabase/functions/price-comp && \
test -d supabase/functions/cert-lookup && \
echo "code-map paths OK"
```
Expected: `code-map paths OK`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/slabbist-product/references/architecture-map.md
git commit -m "feat(skill): add slabbist-product architecture-map reference"
```

---

### Task 5: Final integration verification

**Files:** none (verification only).

- [ ] **Step 1: Verify the full skill tree exists**

Run:
```bash
cd /Users/dixoncider/slabbist
test -f .claude/skills/slabbist-product/SKILL.md && \
test -f .claude/skills/slabbist-product/references/glossary.md && \
test -f .claude/skills/slabbist-product/references/value-loops.md && \
test -f .claude/skills/slabbist-product/references/architecture-map.md && \
echo "skill tree complete"
```
Expected: `skill tree complete`.

- [ ] **Step 2: Verify SKILL.md references each reference file by name (progressive disclosure wired)**

Run:
```bash
cd /Users/dixoncider/slabbist
for ref in glossary value-loops architecture-map; do
  grep -q "references/$ref.md" .claude/skills/slabbist-product/SKILL.md && echo "links $ref OK" || echo "MISSING LINK $ref"
done
```
Expected: `links glossary OK`, `links value-loops OK`, `links architecture-map OK`.

- [ ] **Step 3: Verify no duplication of CLAUDE.md command lines (anti-drift check)**

Run:
```bash
cd /Users/dixoncider/slabbist
grep -rnE 'supabase db push|bun run cli|xcodebuild' .claude/skills/slabbist-product/ && echo "FOUND DUPLICATED COMMANDS — REPLACE WITH POINTER TO CLAUDE.md" || echo "no command duplication OK"
```
Expected: `no command duplication OK`.

- [ ] **Step 4: Confirm the working tree is clean for this skill (all committed)**

Run:
```bash
cd /Users/dixoncider/slabbist
git status --porcelain .claude/skills/slabbist-product/
```
Expected: no output (everything committed across Tasks 1–4).

---

## Notes for the executor

- **Authoring, not coding.** "Tests" here are shell verifications. If a verification fails, fix the prose, not the check (unless the check itself is wrong).
- **Durable-intent rule.** If you feel the urge to add a formula, threshold, TTL, or response shape, stop — add a `→ spec` pointer instead.
- **Do not start the hardening work.** It is sketched in the spec and gets its own plan.
