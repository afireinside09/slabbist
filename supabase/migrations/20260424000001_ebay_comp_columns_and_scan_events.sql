-- 20260424000001_ebay_comp_columns_and_scan_events.sql
-- Adds eBay-comp aggregate columns to graded_market and creates slab_scan_events
-- for the scraper's watchlist promotion signal.
-- Spec: docs/superpowers/specs/2026-04-23-ebay-sold-listings-comp-design.md

-- Column naming: graded_market already uses numeric(12,2) for prices
-- (see 20260422120000_tcgcsv_pokemon_and_graded.sql). Staying consistent.

alter table public.graded_market
  add column if not exists mean_price         numeric(12,2),
  add column if not exists trimmed_mean_price numeric(12,2),
  add column if not exists sample_window_days smallint,
  add column if not exists confidence         real;

create table if not exists public.slab_scan_events (
  id                uuid primary key default gen_random_uuid(),
  identity_id       uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service   public.grader not null,
  grade             text not null,
  store_id          uuid references public.stores(id),
  cache_state       text not null check (cache_state in ('hit','miss','stale')),
  scanned_at        timestamptz not null default now()
);

create index if not exists slab_scan_events_identity_time_idx
  on public.slab_scan_events (identity_id, grading_service, grade, scanned_at desc);
create index if not exists slab_scan_events_scanned_at_idx
  on public.slab_scan_events (scanned_at desc);

-- RLS: readable by authenticated users; writable only by service-role
-- (the Edge Function uses service-role for this write).
alter table public.slab_scan_events enable row level security;

create policy slab_scan_events_select_authenticated
  on public.slab_scan_events for select
  to authenticated
  using (true);
