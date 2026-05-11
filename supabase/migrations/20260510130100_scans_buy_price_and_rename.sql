-- supabase/migrations/20260510130100_scans_buy_price_and_rename.sql
--
-- Renames scans.offer_cents → vendor_ask_cents to clear the name collision
-- with the new "store's offer to vendor" concept (buy_price_cents).
-- See spec: docs/superpowers/specs/2026-05-08-store-workflow-design.md#naming-clarification

alter table scans rename column offer_cents to vendor_ask_cents;
comment on column scans.vendor_ask_cents is
  'Vendor''s manual asking price for this slab when no comp data is available. Optional, operator-entered.';

alter table scans add column buy_price_cents bigint;
alter table scans add column buy_price_overridden boolean not null default false;

comment on column scans.buy_price_cents is
  'Store''s per-line offer to the vendor. Auto = round(reconciled_headline_price_cents * lot.margin_pct_snapshot); operator can override.';
comment on column scans.buy_price_overridden is
  'TRUE means an operator explicitly set buy_price_cents and a margin change should NOT auto-recompute it.';

create index scans_lot_buy_price on scans(lot_id) where buy_price_cents is not null;
