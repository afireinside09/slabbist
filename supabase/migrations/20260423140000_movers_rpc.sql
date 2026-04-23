-- 20260423140000_movers_rpc.sql
-- Top 10 movers (gainers / losers) for a TCG category.
--
-- Pairs the two most recent `tcg_price_history` snapshots per
-- (product_id, sub_type_name) within a category, computes the percent
-- move between them, and returns the top N by direction. When only one
-- snapshot exists (fresh install, single scrape run), the `rn = 2`
-- self-join matches no rows and the RPC returns an empty result — the
-- UI shows a "waiting for next sync" empty state until the second run
-- lands.
--
-- Performance plan:
--   1. `tcg_products(category_id)` → cheap narrow filter on a 60k-row
--      table; keeps the history scan bounded to one category.
--   2. Existing composite `tcg_price_history(product_id, captured_at
--      DESC)` serves the window partition efficiently (PARTITION BY
--      product_id + already-sorted captured_at).
--   3. CASE-expression ORDER BY picks the right direction without
--      firing two separate queries.
--
-- Verify plan once data accumulates a second snapshot:
--   EXPLAIN (ANALYZE, BUFFERS)
--   SELECT * FROM public.get_top_movers(3, 'gainers', 10, 'Normal');
-- Expect: Index Scan on tcg_products_category_id_idx feeding an Index
-- Scan on tcg_price_history_product_captured_idx.

-- ---------------------------------------------------------------
-- Supporting index: category filter on tcg_products.
-- ---------------------------------------------------------------

create index if not exists tcg_products_category_id_idx
  on public.tcg_products(category_id);

-- ---------------------------------------------------------------
-- RPC: get_top_movers
-- ---------------------------------------------------------------

create or replace function public.get_top_movers(
  p_category_id int,
  p_direction   text    default 'gainers',
  p_limit       int     default 10,
  p_sub_type    text    default 'Normal'
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
    join public.tcg_products p on p.product_id = h.product_id
    where p.category_id = p_category_id
      and h.sub_type_name = p_sub_type
      and h.market_price is not null
      and h.market_price > 0
  ),
  pairs as (
    select
      cur.product_id,
      cur.sub_type_name,
      cur.market_price                                                           as current_price,
      prv.market_price                                                           as previous_price,
      (cur.market_price - prv.market_price)                                      as abs_change,
      ((cur.market_price - prv.market_price) / prv.market_price) * 100           as pct_change,
      cur.captured_at,
      prv.captured_at                                                            as previous_captured_at
    from ranked cur
    join ranked prv
      on prv.product_id    = cur.product_id
     and prv.sub_type_name = cur.sub_type_name
     and prv.rn            = 2
    where cur.rn = 1
  )
  select
    pairs.product_id,
    p.name                                                                       as product_name,
    g.name                                                                       as group_name,
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
  left join public.tcg_groups g on g.group_id = p.group_id
  where case
          when p_direction = 'gainers' then pairs.pct_change > 0
          when p_direction = 'losers'  then pairs.pct_change < 0
          else true
        end
  order by
    case when p_direction = 'gainers' then pairs.pct_change end desc nulls last,
    case when p_direction = 'losers'  then pairs.pct_change end asc  nulls last,
    abs(pairs.abs_change) desc
  limit greatest(p_limit, 0);
$$;

grant execute on function public.get_top_movers(int, text, int, text) to anon, authenticated;
