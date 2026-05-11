-- supabase/migrations/20260511130100_transactions_table.sql

create table transactions (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references stores(id),
  lot_id uuid not null references lots(id),
  vendor_id uuid references vendors(id) on delete set null,  -- ON DELETE SET NULL preserves receipt readability
  vendor_name_snapshot text not null,
  total_buy_cents bigint not null,
  payment_method payment_method not null,
  payment_reference text,
  paid_at timestamptz not null,
  paid_by_user_id uuid not null references auth.users(id),
  voided_at timestamptz,
  voided_by_user_id uuid references auth.users(id),
  void_reason text,
  void_of_transaction_id uuid references transactions(id),
  created_at timestamptz not null default now()
);

create index transactions_store_paid_at on transactions(store_id, paid_at desc);
create index transactions_lot_id on transactions(lot_id);
create index transactions_vendor_id on transactions(vendor_id);

-- A lot has at most one non-voided transaction. Voids and the original both
-- have one of {void_of_transaction_id IS NOT NULL, voided_at IS NOT NULL},
-- so the partial uniqueness only matches "active originals."
create unique index transactions_one_active_per_lot
  on transactions(lot_id)
  where void_of_transaction_id is null and voided_at is null;

comment on table transactions is
  'Immutable buy ledger. Voids are new rows, never updates.';
comment on column transactions.vendor_id is
  'FK to vendors; ON DELETE SET NULL so a store cascade-delete leaves old receipts intact via vendor_name_snapshot.';
comment on column transactions.vendor_name_snapshot is
  'Vendor display name at paid_at time. Stays stable if the vendor record is later renamed or archived.';
comment on column transactions.void_of_transaction_id is
  'Self-FK pointing at the original transaction this row voids.';
