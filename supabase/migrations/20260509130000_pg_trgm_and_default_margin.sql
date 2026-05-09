-- supabase/migrations/20260509130000_pg_trgm_and_default_margin.sql
--
-- Foundation for sub-project #6: enables `pg_trgm` for vendor fuzzy search
-- (used by Plan 1's `VendorPicker`) and adds `stores.default_margin_pct`
-- so each new lot can snapshot the store's default offer percentage.
-- See spec: docs/superpowers/specs/2026-05-08-store-workflow-design.md#stores-existing-table--column-added

create extension if not exists pg_trgm;

alter table stores
  add column default_margin_pct numeric(5,4) not null default 0.6000
  check (default_margin_pct >= 0 and default_margin_pct <= 1);

comment on column stores.default_margin_pct is
  'Per-store default offer pct (0..1). Snapshotted to lots.margin_pct_snapshot at lot creation.';
