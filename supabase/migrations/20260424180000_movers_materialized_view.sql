-- 20260424180000_movers_materialized_view.sql
-- Movers materialized view + refresh function.
--
-- Replaces the on-demand window-function query inside `get_top_movers()`
-- with a pre-computed snapshot. The RPC now does a narrow indexed scan
-- against `public.movers` instead of re-ranking `tcg_price_history` on
-- every call. Refresh is explicit: the scraper calls
-- `public.refresh_movers()` at the tail of each tcgcsv raw ingest, so
-- the view always reflects the latest completed scrape.
--
-- Shape mirrors the RPC return type so iOS `MoverDTO` decoding and the
-- `get_top_movers()` contract remain identical — callers don't need to
-- change.

-- ---------------------------------------------------------------
-- Materialized view: public.movers
-- ---------------------------------------------------------------

create materialized view if not exists public.movers as
with ranked as (
  select
    h.product_id,
    h.sub_type_name,
    h.market_price,
    h.captured_at,
    row_number() over (
      partition by h.product_id, h.sub_type_name
      order by h.captured_at desc
    ) as rn
  from public.tcg_price_history h
  where h.market_price is not null
    and h.market_price > 0
),
pairs as (
  select
    cur.product_id,
    cur.sub_type_name,
    cur.market_price                                              as current_price,
    prv.market_price                                              as previous_price,
    (cur.market_price - prv.market_price)                         as abs_change,
    ((cur.market_price - prv.market_price) / prv.market_price)
      * 100                                                       as pct_change,
    cur.captured_at                                               as captured_at,
    prv.captured_at                                               as previous_captured_at
  from ranked cur
  join ranked prv
    on prv.product_id    = cur.product_id
   and prv.sub_type_name = cur.sub_type_name
   and prv.rn            = 2
  where cur.rn = 1
)
select
  pairs.product_id,
  p.category_id,
  p.name                                                          as product_name,
  g.name                                                          as group_name,
  p.image_url,
  pairs.sub_type_name,
  pairs.current_price,
  pairs.previous_price,
  pairs.abs_change,
  pairs.pct_change,
  pairs.captured_at,
  pairs.previous_captured_at
from pairs
join public.tcg_products p on p.product_id = pairs.product_id
left join public.tcg_groups g on g.group_id = p.group_id;

-- Unique index → enables REFRESH MATERIALIZED VIEW CONCURRENTLY.
create unique index if not exists movers_product_sub_uniq
  on public.movers (product_id, sub_type_name);

-- Ordered access: latest rank for a given (category, sub_type, direction).
create index if not exists movers_category_sub_pct_desc_idx
  on public.movers (category_id, sub_type_name, pct_change desc);

create index if not exists movers_category_sub_pct_asc_idx
  on public.movers (category_id, sub_type_name, pct_change asc);

-- ---------------------------------------------------------------
-- Refresh function
-- ---------------------------------------------------------------

create or replace function public.refresh_movers()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- CONCURRENTLY avoids a write lock on the view for readers. Falls back
  -- to non-concurrent on first refresh (before the view is populated).
  begin
    refresh materialized view concurrently public.movers;
  exception when feature_not_supported or object_not_in_prerequisite_state then
    refresh materialized view public.movers;
  end;
end;
$$;

grant select on public.movers to anon, authenticated;
grant execute on function public.refresh_movers() to service_role;

-- ---------------------------------------------------------------
-- Rewrite get_top_movers() to read from the materialized view
-- ---------------------------------------------------------------

create or replace function public.get_top_movers(
  p_category_id int,
  p_direction   text default 'gainers',
  p_limit       int  default 10,
  p_sub_type    text default 'Normal'
)
returns table (
  product_id           int,
  product_name         text,
  group_name           text,
  image_url            text,
  sub_type_name        text,
  current_price        numeric,
  previous_price       numeric,
  abs_change           numeric,
  pct_change           numeric,
  captured_at          timestamptz,
  previous_captured_at timestamptz
)
language sql
stable
as $$
  select
    m.product_id,
    m.product_name,
    m.group_name,
    m.image_url,
    m.sub_type_name,
    m.current_price,
    m.previous_price,
    m.abs_change,
    m.pct_change,
    m.captured_at,
    m.previous_captured_at
  from public.movers m
  where m.category_id   = p_category_id
    and m.sub_type_name = p_sub_type
    and case
          when p_direction = 'gainers' then m.pct_change > 0
          when p_direction = 'losers'  then m.pct_change < 0
          else true
        end
  order by
    case when p_direction = 'gainers' then m.pct_change end desc nulls last,
    case when p_direction = 'losers'  then m.pct_change end asc  nulls last,
    abs(m.abs_change) desc
  limit greatest(p_limit, 0);
$$;

grant execute on function public.get_top_movers(int, text, int, text) to anon, authenticated;
