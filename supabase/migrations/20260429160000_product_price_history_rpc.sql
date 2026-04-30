-- 20260429160000_product_price_history_rpc.sql
-- Read RPC behind the iOS card-detail screen's price-history chart.
--
-- Why an RPC instead of a direct PostgREST query:
--   The chart needs an N-day window with non-null market prices,
--   ordered ascending by captured_at. Expressing that through
--   PostgREST is awkward — `now() - interval '90 days'` requires a
--   server-side helper anyway, so we put the whole shape in one
--   function and let the client just hand over (product_id, days).
--
-- Rows returned: ≤ one per scrape run × N days. The scraper has been
-- running ~once per ingest, so 90 days yields well under 100 points
-- per (product, sub_type) — small enough to render directly without
-- downsampling on the client.
--
-- Index plan: existing tcg_price_history(product_id, captured_at DESC)
-- composite serves the (product_id, sub_type_name) filter and the
-- captured_at ordering directly.

create or replace function public.get_product_price_history(
  p_product_id int,
  p_sub_type   text default 'Normal',
  p_days       int  default 90
)
returns table (
  captured_at  timestamptz,
  market_price numeric,
  low_price    numeric,
  mid_price    numeric,
  high_price   numeric
)
language sql
stable
as $$
  select h.captured_at, h.market_price, h.low_price, h.mid_price, h.high_price
  from public.tcg_price_history h
  where h.product_id     = p_product_id
    and h.sub_type_name  = p_sub_type
    and h.market_price   is not null
    and h.market_price   > 0
    and h.captured_at   >= now() - make_interval(days => greatest(p_days, 1))
  order by h.captured_at asc;
$$;

grant execute on function public.get_product_price_history(int, text, int) to anon, authenticated;
