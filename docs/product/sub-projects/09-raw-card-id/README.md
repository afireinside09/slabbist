# Sub-project 9 — Raw card identification

Extends scanning to ungraded cards — the other half of the store-buy flow.

## Scope

- Raw card image recognition pipeline (set symbol, card number, name, variant).
- Decision point: **build our own model on a Pokémon dataset vs. use a service like Ximilar.** TBD — recommendation: start with a service, build in-house when the volume and feedback loop justify the investment.
- Japanese card support end-to-end (OCR + matching against `tcg_products` where `category_id = 85`).
- Sealed product scanning via barcode (booster boxes, ETBs, packs) — reads `tcg_products` for product identification.
- Condition assessment helper for raw cards — camera overlays for centering, edges, surface with photo guides.
- Batch photo upload from the camera roll for cards already photographed.

## Features captured

- Raw card identification via image recognition
- Japanese card support (raw domain)
- Sealed product scanning via barcode
- Condition assessment helper
- Batch photo upload

## What this sub-project owns vs references

- **Owns:** iOS image-recognition pipeline, raw-card scan UI, raw-card comp view, condition-helper UX.
- **References:** `tcg_products`, `tcg_prices`, `tcg_price_history` (sub-project 2 / tcgcsv). Read-only.
- **Never references:** `graded_*` tables. A raw Charizard product row and a graded PSA-10 Charizard row are independent records, joined only at the UI level if/when "compare raw to graded" becomes a feature.

## Dependencies

- Sub-project 2 (tcgcsv) — `tcg_*` tables must be populated.
- Sub-project 4 extension — need a raw-specific `/price-comp-raw` Edge Function or a raw branch in `/price-comp` that reads `tcg_prices`.

## Unblocks

- Nothing blocking — this is an expansion that layers onto the MVP slab flow.
