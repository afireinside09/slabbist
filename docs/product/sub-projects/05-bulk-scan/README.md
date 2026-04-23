# Sub-project 5 — Bulk scan mode

**The MVP headline feature.** Scan dozens of slabs in one session, see live comps, produce a reviewable saved lot.

## Status

**Designing.** Full design spec: [`../../../superpowers/specs/2026-04-22-bulk-scan-comp-design.md`](../../../superpowers/specs/2026-04-22-bulk-scan-comp-design.md)

## Scope

- `lots` entity — progressive data model that starts as a saved session, can become an offer, can become a transaction.
- `scans` entity — one per OCR capture inside a lot.
- **Three capture modes:** one-by-one in hand (MVP day-one), continuous / assembly-line (follow-up), tripod / stand mode (follow-up). All share the same queue + comp pipeline; only the capture UI differs.
- Offline-first pipeline: local SwiftData cache, outbox pattern for writes and validation/comp jobs, graceful degradation with pending badges.
- Lot review screen (grouped by Ready / Pending / Issues).
- Scan detail drill-in.
- CSV export of lot.

## Features captured

- Bulk scan mode — multiple slabs in one session
- Queue and batch process
- Scan history per lot
- Pending-validation / pending-comp badges for offline mode

## Deferred

- Offer sheet (PDF, pricing with margin rules) — sub-project 6 + 7
- Vendor attachment — sub-project 6
- Showing customer a clean comp-only view — sub-project 6

## Dependencies

- Sub-projects 1 (auth/store), 2 (cards), 3 (scan pipeline), 4 (comp engine)

## Unblocks

- Sub-project 6 (workflow features extend the lot entity)
