-- supabase/migrations/20260510130000_lots_offer_columns.sql

create type lot_offer_state as enum (
  'drafting',   -- scans landing; no buy prices yet
  'priced',     -- buy_price_cents filled on at least one scan
  'presented',  -- operator showed offer to vendor; awaiting agreement
  'accepted',   -- vendor agreed; payment method captured
  'declined',   -- vendor said no; lot still inspectable
  'paid',       -- (Plan 3) transaction row exists, totals frozen
  'voided'      -- (Plan 3) transaction was voided after pay
);

alter table lots
  add column vendor_id uuid references vendors(id),
  add column vendor_name_snapshot text,
  add column margin_pct_snapshot numeric(5,4)
    check (margin_pct_snapshot is null
           or (margin_pct_snapshot >= 0 and margin_pct_snapshot <= 1)),
  add column lot_offer_state lot_offer_state not null default 'drafting',
  add column lot_offer_state_updated_at timestamptz;

create index lots_vendor_id on lots(vendor_id);
create index lots_offer_state on lots(store_id, lot_offer_state);

comment on column lots.vendor_name_snapshot is
  'Vendor display name at offer time. Stays stable if the vendor record is later renamed.';
comment on column lots.margin_pct_snapshot is
  'Snapshot of stores.default_margin_pct at lot creation. Plan 3-replaced by margin_rule_id output once subproject 7 lands.';
comment on column lots.lot_offer_state is
  'Where this lot is in the offer/transaction lifecycle. Parallel to lot_status; do not merge.';
