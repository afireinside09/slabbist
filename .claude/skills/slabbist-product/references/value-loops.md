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
