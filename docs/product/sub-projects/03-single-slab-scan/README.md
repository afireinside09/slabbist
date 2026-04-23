# Sub-project 3 — Single slab scan & comp

One slab, one comp. The foundational scan path that bulk scan (sub-project 5) extends.

## Scope

- Single-slab camera scan screen using AVFoundation + Apple Vision.
- Grader cert OCR for PSA, BGS, CGC, SGC, TAG (grader-specific regex + stability thresholds).
- Manual cert entry fallback (grader picker + cert number field).
- `/cert-lookup` Edge Function that imports the tcgcsv repo's graded libraries (`src/graded/sources/<service>.ts` + `src/graded/identity.ts`) to run per-service lookups and identity normalization, then upserts `graded_card_identities` and `graded_cards` server-side.
- Render a single comp result via `/price-comp` (reads `graded_market` — owned by sub-project 2/tcgcsv).
- Scan history per user / store (search, filter, re-open past scans).

## Features captured

- Single slab scan via camera (cert number OCR)
- Manual cert entry fallback
- Scan history per user and per store
- All grader support (PSA/BGS/CGC/SGC/TAG)

## What this sub-project owns vs references

- **Owns:** the iOS scan UI, the `/cert-lookup` Edge Function (as a thin wrapper around tcgcsv's graded libs), the scan-history UI.
- **References:** `graded_card_identities`, `graded_cards`, `graded_market` (sub-project 2 / tcgcsv). Reads only; writes to identity/cards happen through tcgcsv's `normalizeIdentity()`.

## Dependencies

- Sub-project 1 (auth/store — scans are owned by `store_id`)
- Sub-project 2 (tcgcsv's `graded_card_identities` + `graded_cards` tables must exist before Plan 2 of sub-project 5 lands the scan FK)
- Sub-project 4 (comp engine — to actually show a price)

## Unblocks

- Sub-project 5 (bulk scan reuses the camera pipeline and OCR recognizer)
