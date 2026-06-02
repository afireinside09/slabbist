-- 20260601120000_tcg_grade_comp.sql
-- Materialized raw↔graded join for the Grade Gains page. Keyed by the
-- raw TCGPlayer product id (== tcg_products.product_id == the id
-- Poketrace's /cards?tcgplayer_ids= search accepts). Deliberately FK-free:
-- tcg_* and graded data stay decoupled; this table IS the consumer-side
-- join, not a foreign-key relationship.
--
-- Global reference data like tcg_prices → NOT tenant-scoped, NO RLS.

create table if not exists public.tcg_grade_comp (
  product_id         int  primary key,
  poketrace_card_id  text not null default '',   -- '' = looked-up, no match
  psa10_price_cents  int,                         -- PSA 10 avg; null = no PSA 10 tier
  pt_trend           text check (pt_trend in ('up','down','stable')),
  pt_confidence      text check (pt_confidence in ('high','medium','low')),
  pt_sale_count      int,
  resolved_at        timestamptz not null default now()
);

-- Supports spread sorting and "set has gains" checks.
create index if not exists tcg_grade_comp_psa10_idx
  on public.tcg_grade_comp (psa10_price_cents)
  where psa10_price_cents is not null;

comment on table public.tcg_grade_comp is
  'Poketrace PSA 10 comp per raw tcg product. FK-free consumer-side join for the Grade Gains page.';
