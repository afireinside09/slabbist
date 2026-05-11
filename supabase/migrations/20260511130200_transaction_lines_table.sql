-- supabase/migrations/20260511130200_transaction_lines_table.sql

create table transaction_lines (
  transaction_id uuid not null references transactions(id) on delete cascade,
  scan_id uuid not null references scans(id),
  line_index int not null,
  buy_price_cents bigint not null,
  identity_snapshot jsonb not null,
  primary key (transaction_id, scan_id)
);

create index transaction_lines_scan_id on transaction_lines(scan_id);

comment on table transaction_lines is
  'Frozen line items per transaction. identity_snapshot captures card/cert details so a future schema change to graded_card_identities cannot retroactively rewrite a paid receipt.';
comment on column transaction_lines.identity_snapshot is
  'Shape: {card_name, set_name, card_number, year, variant, grader, grade, cert_number, comp_used_cents, reconciled_source}';
