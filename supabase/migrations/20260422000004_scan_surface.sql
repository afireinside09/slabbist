create table lots (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references stores(id),
  created_by_user_id uuid not null references auth.users(id),
  name text not null,
  notes text,
  status lot_status not null default 'open',
  vendor_name text,
  vendor_contact text,
  offered_total_cents bigint,
  margin_rule_id uuid,
  transaction_stamp jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index lots_store_id on lots(store_id);
create index lots_store_status on lots(store_id, status);

create table scans (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references stores(id),
  lot_id uuid not null references lots(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  grader grader not null,
  cert_number text not null,
  grade text,
  -- graded_card_identity_id and graded_card_id FKs added by Plan 2
  -- after the tcgcsv graded-table migration has landed.
  status scan_status not null default 'pending_validation',
  ocr_raw_text text,
  ocr_confidence real,
  captured_photo_url text,
  offer_cents bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index scans_lot_id on scans(lot_id);
create index scans_store_status on scans(store_id, status);
create unique index scans_cert_per_lot on scans(lot_id, grader, cert_number);
