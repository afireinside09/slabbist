-- supabase/migrations/20260604120000_remove_ppt_poketrace_only.sql
-- Remove PokemonPriceTracker; Poketrace becomes the sole graded source.
-- Spec: docs/superpowers/specs/2026-06-04-poketrace-only-comp-design.md
-- Live schema verified 2026-06-04 before authoring.

-- 1. Drop PPT-only rows from the market table.
delete from public.graded_market where source = 'pokemonpricetracker';

-- 2. Default future rows to poketrace.
alter table public.graded_market alter column source set default 'poketrace';

-- 3. Drop the PPT ladder + identifiers. Keep headline_price + price_history
--    (written for the poketrace source too) and all pt_* columns.
alter table public.graded_market
  drop column if exists ppt_tcgplayer_id,
  drop column if exists ppt_url,
  drop column if exists loose_price,
  drop column if exists psa_7_price,
  drop column if exists psa_8_price,
  drop column if exists psa_9_price,
  drop column if exists psa_9_5_price,
  drop column if exists psa_10_price,
  drop column if exists bgs_10_price,
  drop column if exists cgc_10_price,
  drop column if exists sgc_10_price;

-- 4. Identities: drop PPT url, rename the tcgplayer id (still needed for the
--    Tier A cross-walk), rename its partial index.
alter table public.graded_card_identities drop column if exists ppt_url;
alter table public.graded_card_identities
  rename column ppt_tcgplayer_id to tcgplayer_product_id;
alter index if exists graded_card_identities_ppt_tcgplayer_idx
  rename to graded_card_identities_tcgplayer_product_idx;

-- 5. Recreate graded_market_sales (dropped in 20260505120200) for sold comps.
create table if not exists public.graded_market_sales (
  id                bigserial primary key,
  identity_id       uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service   text not null check (grading_service in ('PSA','CGC','BGS','SGC','TAG')),
  grade             text not null,
  source            text not null default 'ebay',
  source_listing_id text not null,
  sold_price        numeric(12,2) not null,
  sold_at           timestamptz not null,
  title             text,
  url               text,
  grader            text,
  condition         text,
  anomaly_flag      text,
  captured_at       timestamptz not null default now(),
  unique (source, source_listing_id)
);
create index if not exists graded_market_sales_sold_at_idx
  on public.graded_market_sales (sold_at desc);
create index if not exists graded_market_sales_lookup_idx
  on public.graded_market_sales (identity_id, grading_service, grade);

-- 6. RLS: readable by authenticated; writes are service-role only (Edge Fn).
alter table public.graded_market_sales enable row level security;
drop policy if exists graded_market_sales_select_authenticated on public.graded_market_sales;
create policy graded_market_sales_select_authenticated
  on public.graded_market_sales for select
  to authenticated
  using (true);
