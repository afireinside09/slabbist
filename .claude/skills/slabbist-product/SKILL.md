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
