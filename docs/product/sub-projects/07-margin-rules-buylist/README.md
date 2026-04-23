# Sub-project 7 — Margin rules, role visibility, shared buylist

The pricing policy layer.

## Scope

- Store-wide pricing rules: default margin percentage, floors, ceilings, per-category overrides.
- Role-based price visibility — owners see cost/margin, associates see only buy price (enforced by both RLS and UI gating).
- Shared store buylist — specific cards with target buy prices. When a scanned card matches a buylist entry, the target price surfaces in the comp view.
- Want list / wishlist for specific cards with price alerts when comp drops below a threshold.

## Features captured

- Store-wide pricing rules
- Margin visibility controls
- Shared store buylist
- Want list / wishlist

## Dependencies

- Sub-projects 1 (roles), 6 (offer generation uses margin rules)

## Unblocks

- Inventory and analytics features (sub-project 8) that aggregate by rule
