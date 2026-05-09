-- supabase/migrations/20260509130100_vendors_table.sql
--
-- Vendors directory scoped per store. Soft-archive (no hard delete) because
-- analytics needs the row even after a vendor stops doing business.

create type contact_method as enum ('phone', 'email', 'instagram', 'in_person', 'other');

create table vendors (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references stores(id) on delete cascade,
  display_name text not null,
  contact_method contact_method,
  contact_value text,
  notes text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index vendors_store_id on vendors(store_id);
create index vendors_store_active on vendors(store_id) where archived_at is null;
create index vendors_display_name_trgm on vendors using gin (display_name gin_trgm_ops);

comment on table vendors is
  'Per-store vendor directory. Soft-archive only.';
comment on column vendors.archived_at is
  'Soft-archive timestamp; non-null hides the row from active pickers but keeps it for ledger reads.';
