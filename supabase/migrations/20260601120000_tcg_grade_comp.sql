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

-- ---------------------------------------------------------------
-- Read RPCs. Live joins (data is near-static); no materialized slate.
-- Raw price for a product = the highest market_price across its
-- sub-types (the gradeable chase printing). Spread = psa10 − raw.
-- Reuses public.movers_price_tier(numeric) for raw-price banding so
-- the bands match the Movers tab exactly.
-- ---------------------------------------------------------------

create or replace function public.get_grade_gain_sets()
returns table (
  group_id     int,
  group_name   text,
  gains_count  int,
  published_on date
)
language sql
stable
as $$
  with raw_best as (
    select distinct on (pr.product_id)
      pr.product_id, pr.market_price
    from public.tcg_prices pr
    where pr.market_price is not null and pr.market_price > 0
    order by pr.product_id, pr.market_price desc
  ),
  gains as (
    select p.group_id, count(*)::int as gains_count
    from public.tcg_grade_comp c
    join public.tcg_products p on p.product_id = c.product_id
    join raw_best rb           on rb.product_id = c.product_id
    where c.psa10_price_cents is not null
      and (c.psa10_price_cents - round(rb.market_price * 100)::int) > 0
    group by p.group_id
  )
  select gn.group_id, g.name as group_name, gn.gains_count, g.published_on
  from gains gn
  join public.tcg_groups g on g.group_id = gn.group_id
  where g.category_id = 3        -- English only for v1
  order by g.published_on desc nulls last, g.name asc;
$$;

grant execute on function public.get_grade_gain_sets() to anon, authenticated;

create or replace function public.get_set_grade_gains(
  p_group_id   int,
  p_price_tier text default 'under_5'
)
returns table (
  product_id        int,
  product_name      text,
  group_name        text,
  image_url         text,
  sub_type_name     text,
  raw_price_cents   int,
  psa10_price_cents int,
  spread_cents      int,
  pt_trend          text,
  pt_confidence     text,
  pt_sale_count     int
)
language sql
stable
as $$
  with raw_best as (
    select distinct on (pr.product_id)
      pr.product_id, pr.sub_type_name, pr.market_price
    from public.tcg_prices pr
    where pr.market_price is not null and pr.market_price > 0
    order by pr.product_id, pr.market_price desc
  )
  select
    p.product_id,
    p.name                                                    as product_name,
    g.name                                                    as group_name,
    p.image_url,
    rb.sub_type_name,
    round(rb.market_price * 100)::int                         as raw_price_cents,
    c.psa10_price_cents,
    (c.psa10_price_cents - round(rb.market_price * 100)::int) as spread_cents,
    c.pt_trend,
    c.pt_confidence,
    c.pt_sale_count
  from public.tcg_grade_comp c
  join public.tcg_products p on p.product_id = c.product_id
  join raw_best rb           on rb.product_id = c.product_id
  left join public.tcg_groups g on g.group_id = p.group_id
  where p.group_id = p_group_id
    and c.psa10_price_cents is not null
    and public.movers_price_tier(rb.market_price) = p_price_tier
    and (c.psa10_price_cents - round(rb.market_price * 100)::int) > 0
  order by spread_cents desc, p.product_id asc;
$$;

grant execute on function public.get_set_grade_gains(int, text) to anon, authenticated;
