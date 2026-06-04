# Product-Intent Knowledge Base — Design

**Date:** 2026-06-01
**Status:** Approved (design); implementation plan pending
**Topic:** A Claude-skill knowledge base capturing the durable product intent of the Slabbist iOS app, plus a sketched (not-yet-built) hardening strategy.

## Problem

The *why* behind Slabbist — who the user is, the flagship value loops, the domain vocabulary, the architectural invariants — already exists, but it is scattered across 15 long design specs, 19 plans, `CLAUDE.md`, and `.impeccable.md`. A fresh Claude session cannot cheaply load "what is this product trying to be" before it starts changing code. The result is drift between sessions and the risk of shipping changes that contradict product intent.

We want a **durable knowledge base, authored as a Claude skill**, that a future session loads early and uses to make decisions aligned with the product's intent — so we keep shipping high-quality code.

Separately, the codebase needs **hardening** so future changes don't introduce buggy code (e.g. strict database types, drift guards, quality gates). That is a distinct deliverable. This document **designs both** but scopes implementation to the knowledge base first; hardening is sketched here as a menu and will get its own spec → plan.

## Goals

- A single, auto-discovered project skill that captures **durable product intent** — slow-to-change knowledge, not implementation specifics.
- Resist drift: the skill **points to** authoritative specs for formulas/thresholds/shapes rather than restating them.
- Do **not** duplicate `CLAUDE.md` (commands, hard architecture rules) or `.impeccable.md` (design system) — reference them.
- Cheap to load (lean `SKILL.md`), deep on demand (reference files).

## Non-Goals

- Restating spec specifics (TTLs, exact response shapes, column counts, thresholds, formulas) — these evolve and belong in specs.
- Human onboarding docs — the audience is future Claude sessions.
- Building the hardening work in this iteration (it is sketched, then deferred to its own spec).
- Touching application code. This deliverable is authored docs/skill content only.

## Audience

Future Claude sessions doing Slabbist product/feature work — planning, designing, or implementing. Not human onboarding.

## Structure

A single project skill with progressive disclosure, placed where Claude Code auto-discovers project skills:

```
.claude/skills/slabbist-product/
├── SKILL.md                      # lean entry point
└── references/
    ├── value-loops.md            # flagship loops: purpose + shape + spec pointer
    ├── glossary.md               # domain vocabulary lookup
    └── architecture-map.md       # product-reasoning invariants + comp-source landscape + code map
```

**Why this shape.** `SKILL.md` stays cheap to load and frontmatter-triggers on Slabbist product work. The three reference files load on demand, each with one job. This is the "one domain skill + refs" approach with strictly durable-intent content.

### Discovery

`SKILL.md` frontmatter `description` is tuned so a fresh session pulls it when reasoning about *what to build or why*:

> Use when planning, designing, or implementing any Slabbist iOS product feature — captures who the user is, the IA, the flagship value loops (movers, comps, grade-gains), domain vocabulary, and architectural invariants. Read before non-trivial product work.

`name`: `slabbist-product`.

### Relationship to existing docs (the anti-drift rule)

This skill is the **durable layer**. It never restates formulas, thresholds, TTLs, or response shapes — those live in specs and evolve. It captures who/why/what and **points** to the authoritative spec for specifics.

- `CLAUDE.md` remains the owner of commands + hard architecture rules. The skill references it, does not duplicate it.
- `.impeccable.md` remains the owner of the design system. The skill references it, does not duplicate it.
- Specs in `docs/superpowers/specs/` remain authoritative for feature specifics. The skill points to them by filename.

Each durable claim in the skill that maps to a spec carries a `→ <spec-filename>` pointer so a session can jump to the authoritative source.

## Content

### `SKILL.md`

1. **What Slabbist is** — one paragraph: buy-side vendor comp tool, not a collector vault.
2. **Who the user is** — hobby-store vendor / buy-side dealer at the counter or card show; the three jobs-to-be-done ("what's this stack worth right now", "what can I offer and still make margin", "get me out of the spreadsheet"); explicit "not collectors — IA is Lots/Scans/Comps/Offers, never vault/portfolio."
3. **The IA** — Lots / Scans / Comps / Offers, mapped to the real `Features/` surfaces (Movers, Comp, Lots, Offers, Scanning, Grading, Vendors, Transactions, CertLookup, Stores).
4. **Value-loop index** — one line each (Movers, Graded Comps, Grade Gains / Pre-Grade Estimator, Bulk Scan, Lots & Offers) → "read `references/value-loops.md`".
5. **Five product invariants in brief** — raw/graded decoupling; offline-first outbox; hero flow (scraper → tables → edge-fn → app); watchlist-not-catalog; defensible-number / show-the-work → "read `references/architecture-map.md`".
6. **"When to load which reference / spec" table** — the pointer layer that routes a session to the right reference file or spec for the task at hand.

Target ~150 lines. If it grows past that, content is being restated that should be a pointer instead.

### `references/value-loops.md`

For each flagship loop: a durable 2-4 sentence **purpose + why it matters + the shape of the output**, then **→ authoritative spec(s)** by filename. No formulas, no thresholds.

Loops covered:

- **Movers** — ranked top gainers/losers across EN/JP from real eBay sold listings; the dealer's market-momentum indicator. → `2026-05-26-movers-row-thumbnail-design.md`
- **Graded card comps (Poketrace-only)** — Poketrace headline + per-grade ladder + history + individual sold eBay listings; the *defensible number*. (PPT removed 2026-06-04.) → `2026-06-04-poketrace-only-comp-design.md`, `2026-05-08-poketrace-comp-design.md`, `2026-04-23-ebay-sold-listings-comp-design.md`
- **Grade gains / pre-grade estimator** — "is this raw card worth grading?": Grade Gains ranks raw cards by PSA-10 profit spread by set; the Pre-Grade Estimator does photo-based sub-grade estimation. → `2026-06-01-grade-gains-page-design.md`, `2026-04-23-pre-grade-estimator-design.md`
- **Bulk scan / comp** — scan a stack of slabs fast (OCR cert → cert-lookup → price-comp → lot); speed for offers made in front of the vendor. → `2026-04-22-bulk-scan-comp-design.md`, `2026-05-07-outbox-worker-design.md`
- **Lots & offers** — the vendor workflow state machine from open lot to paid immutable transaction. → `2026-05-08-store-workflow-design.md`, `2026-05-11-lot-flow-ux-improvements-design.md`, `2026-05-12-lot-margin-mode-toggle-design.md`

### `references/glossary.md`

Domain vocabulary table, one-line definitions grounded in how the specs use each term: slab, cert number, cert, grade, grader/grading service, comp, headline price, per-grade ladder, source, reconciled, watchlist, lot, scan, offer, buy price, vendor ask, margin, raw, graded identity, pop report, grade gains, trend, confidence, fanout, outbox, store_id, transaction.

### `references/architecture-map.md`

- **Product-reasoning invariants** — raw/graded decoupling; offline-first outbox (writes via `OutboxDrainer`, repos are the only Supabase layer); hero flow; watchlist-not-catalog with scan auto-promotion; multi-tenant store_id + RLS; cache + per-source fallback. (Brief; defers to `CLAUDE.md` for the hard rules.)
- **Comp-source landscape** — PPT (primary, cheap, 6-month history + ladder), Poketrace (secondary, trend/confidence, backfills Grade Gains), eBay movers (momentum, not live comps), pop reports (population stats, not pricing) — and how they relate via first-class fanout + reconciliation.
- **Code map** — DTO ↔ repository ↔ edge-function ↔ table, so a session knows *where* things live: e.g. `MoverDTO`/`MoversRepository` ↔ Movers feature; `price-comp` / `cert-lookup` / `grade-estimate` edge functions; the `Core/Data/{DTOs,Repositories,Mapping}` + `Core/Sync` layering.

## Hardening Strategy (sketch — deferred to its own spec)

This section is a **menu with a recommendation**, not a committed plan. It will become its own brainstorm → spec → plan after the knowledge base lands.

**Strict DB types**
- Generate Supabase TypeScript types (via `mcp__supabase__generate_typescript_types`) into the repo for scraper / dashboard / edge functions; treat the generated file as checked-in source.
- For iOS (no codegen): require a checked-in `Decodable` round-trip test against a captured real response for every edge-function shape. (Already a stated value — see the "live decode round-trip" memory.)

**Drift guards**
- CI step that regenerates Supabase types and fails the build on diff (types must be regenerated when schema changes).
- A test asserting every `OutboxKind` case has a corresponding drainer branch (prevents silent outbox gaps when a new write surface is added).

**Quality gates**
- `swiftui-expert-skill` review in the loop for SwiftUI changes (already a project convention).
- RLS test (`supabase/tests/rls_*.sql`) required for any new `store_id`-scoped table.
- Live-decode round-trip as an explicit definition-of-done when wiring a new edge-function shape.

**Recommendation:** start hardening with strict DB types + the type-drift CI guard (highest leverage against the exact "buggy code from schema drift" risk), then layer the OutboxKind-coverage test and the RLS-test gate.

## Success Criteria

- `.claude/skills/slabbist-product/SKILL.md` exists, is discoverable, and a fresh session loading it can correctly answer: who is the user, what is the IA, what is each value loop *for*, and which spec is authoritative for a given feature.
- No durable claim in the skill restates a formula/threshold/shape; each maps to a `→ spec` pointer.
- `SKILL.md` ≤ ~150 lines; the three reference files each have a single clear job.
- Nothing in the skill duplicates `CLAUDE.md` or `.impeccable.md`; both are referenced.
- The hardening sketch is captured here as a menu so its future spec has a starting point.

## Open Questions

None blocking. The hardening specifics are intentionally deferred to a separate spec.
