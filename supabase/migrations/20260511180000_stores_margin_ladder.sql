-- Add a per-store margin ladder: a buyer-configurable rule that maps a
-- slab's reconciled comp value to the offer percentage. The iOS app reads
-- the ladder when auto-deriving per-scan `buy_price_cents` (in absence of
-- a manual lot-level override on `lots.margin_pct_snapshot`).
--
-- Shape (JSONB array, descending threshold):
--   [
--     {"min_comp_cents": 100000, "margin_pct": 0.90},
--     {"min_comp_cents":  50000, "margin_pct": 0.85},
--     {"min_comp_cents":  25000, "margin_pct": 0.80},
--     {"min_comp_cents":  10000, "margin_pct": 0.75},
--     {"min_comp_cents":      0, "margin_pct": 0.70}
--   ]
--
-- The check constraint validates jsonb-shape minimally: the column must be a
-- JSON array. Per-element shape validation is enforced client-side — the
-- iOS settings editor canonicalizes + clamps before write, and the outbox
-- worker patches the entire array atomically (no partial-tier updates).

alter table stores
  add column margin_ladder jsonb not null default jsonb_build_array(
    jsonb_build_object('min_comp_cents', 100000, 'margin_pct', 0.90),
    jsonb_build_object('min_comp_cents',  50000, 'margin_pct', 0.85),
    jsonb_build_object('min_comp_cents',  25000, 'margin_pct', 0.80),
    jsonb_build_object('min_comp_cents',  10000, 'margin_pct', 0.75),
    jsonb_build_object('min_comp_cents',      0, 'margin_pct', 0.70)
  )
  check (jsonb_typeof(margin_ladder) = 'array');

comment on column stores.margin_ladder is
  'Per-store offer ladder. Each element: {min_comp_cents, margin_pct}. Sorted descending by min_comp_cents. Used per-scan when lots.margin_pct_snapshot is null.';
