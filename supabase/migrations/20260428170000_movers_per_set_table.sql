-- 20260428170000_movers_per_set_table.sql
-- Replace the per-product materialized view with a real table that
-- stores per-set top-10 gainers + bottom-10 losers, computed against
-- a 90-day baseline price snapshot. Refresh now happens through
-- UPSERT + delete-stale, not REFRESH MATERIALIZED VIEW, so the table
-- always reflects "movers from the last 90 days" — a row exists only
-- while the underlying move does.
--
-- Key shape change:
--   Old MV PK: (product_id, sub_type_name)         — one row per card
--   New table PK: (group_id, sub_type_name, direction, rank)
--                                                  — top 10 per set
--   So Base Set EN, Base Set JP, Scarlet & Violet EN, etc. each get
--   their own 10-gainer / 10-loser slate. With ~200 groups across
--   Pokémon EN (cat 3) + Pokémon JP (cat 85), the table tops out at
--   about 200 × 20 ≈ 4 000 rows.
--
-- Why a real table (not a materialized view):
--   We need stable PKs that refresh_movers() can upsert against.
--   When a card stays in a set's top 10, its row's values get
--   overwritten in place. When it falls out, the row is explicitly
--   deleted. This matches the user-visible idea — the table is a
--   live answer to "who moved in the last 90 days," not a frozen
--   snapshot.
--
-- Why a 90-day baseline (not "previous snapshot"):
--   Day-over-day deltas are noisy; a 90-day baseline captures the
--   moves that actually matter to slab economics. Pair this with
--   public.prune_tcg_price_history() so the baseline never reaches
--   further than 90 days into the past.
--
-- Backwards compatibility:
--   public.get_top_movers(p_category_id, p_direction, p_limit,
--   p_sub_type) keeps the same signature and result columns. The iOS
--   MoversRepository / MoverDTO do not change.

-- ---------------------------------------------------------------
-- Drop the old materialized view + dependent functions.
-- ---------------------------------------------------------------

drop function if exists public.get_top_movers(int, text, int, text);
drop function if exists public.refresh_movers();
drop materialized view if exists public.movers;

-- ---------------------------------------------------------------
-- New movers table
-- ---------------------------------------------------------------

create table public.movers (
  group_id              int           not null references public.tcg_groups(group_id) on delete cascade,
  category_id           int           not null,
  sub_type_name         text          not null,
  direction             text          not null check (direction in ('gainers','losers')),
  rank                  smallint      not null check (rank between 1 and 10),
  product_id            int           not null references public.tcg_products(product_id) on delete cascade,
  product_name          text          not null,
  group_name            text,
  image_url             text,
  current_price         numeric(12,2) not null,
  previous_price        numeric(12,2) not null,
  abs_change            numeric(12,2) not null,
  pct_change            numeric(12,4) not null,
  captured_at           timestamptz   not null,
  previous_captured_at  timestamptz   not null,
  refreshed_at          timestamptz   not null default now(),
  primary key (group_id, sub_type_name, direction, rank)
);

-- Speeds up the category-wide top-N queries used by get_top_movers().
-- pct_change is signed, so the same index serves gainers (DESC) and
-- losers (ASC) without a second copy.
create index movers_category_direction_pct_idx
  on public.movers (category_id, direction, sub_type_name, pct_change);

grant select on public.movers to anon, authenticated;

-- ---------------------------------------------------------------
-- Refresh function: per-set top 10 gainers + losers, 90-day window
-- ---------------------------------------------------------------
--
-- Strategy: build the fresh top-10 set in a TEMP TABLE (so INSERT and
-- DELETE can both reference it without re-running the heavy CTE), do
-- INSERT ... ON CONFLICT DO UPDATE to overwrite by PK, then DELETE
-- any pre-existing row whose PK isn't in the fresh set. Both steps
-- run inside the function's transaction, so readers never observe a
-- partial state.

create or replace function public.refresh_movers()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  drop table if exists _movers_fresh;
  create temp table _movers_fresh on commit drop as
  with latest as (
    -- One row per (product, sub_type) — the most recent snapshot.
    select distinct on (h.product_id, h.sub_type_name)
      h.product_id,
      h.sub_type_name,
      h.market_price                                                         as current_price,
      h.captured_at
    from public.tcg_price_history h
    where h.market_price is not null
      and h.market_price > 0
    order by h.product_id, h.sub_type_name, h.captured_at desc
  ),
  baseline as (
    -- Oldest snapshot still inside the 90-day window. Becomes the
    -- comparison anchor; prune_tcg_price_history() keeps this bounded.
    select distinct on (h.product_id, h.sub_type_name)
      h.product_id,
      h.sub_type_name,
      h.market_price                                                         as previous_price,
      h.captured_at                                                          as previous_captured_at
    from public.tcg_price_history h
    where h.market_price is not null
      and h.market_price > 0
      and h.captured_at >= v_now - interval '90 days'
    order by h.product_id, h.sub_type_name, h.captured_at asc
  ),
  moves as (
    select
      l.product_id,
      l.sub_type_name,
      l.current_price,
      b.previous_price,
      l.captured_at,
      b.previous_captured_at,
      (l.current_price - b.previous_price)                                   as abs_change,
      ((l.current_price - b.previous_price) / b.previous_price) * 100        as pct_change
    from latest l
    join baseline b
      on b.product_id    = l.product_id
     and b.sub_type_name = l.sub_type_name
    -- Skip products whose latest IS the baseline (only one snapshot
    -- in the window) — there's no comparable move.
    where l.captured_at > b.previous_captured_at
  ),
  enriched as (
    select
      m.*,
      p.group_id,
      p.category_id,
      p.name      as product_name,
      g.name      as group_name,
      p.image_url
    from moves m
    join public.tcg_products p on p.product_id = m.product_id
    left join public.tcg_groups g on g.group_id = p.group_id
  ),
  ranked_gainers as (
    select
      e.*,
      'gainers'::text as direction,
      row_number() over (
        partition by e.group_id, e.sub_type_name
        order by e.pct_change desc, abs(e.abs_change) desc, e.product_id asc
      ) as rank
    from enriched e
    where e.pct_change > 0
  ),
  ranked_losers as (
    select
      e.*,
      'losers'::text as direction,
      row_number() over (
        partition by e.group_id, e.sub_type_name
        order by e.pct_change asc, abs(e.abs_change) desc, e.product_id asc
      ) as rank
    from enriched e
    where e.pct_change < 0
  )
  select
    group_id, category_id, sub_type_name, direction, rank::smallint as rank,
    product_id, product_name, group_name, image_url,
    current_price, previous_price, abs_change, pct_change,
    captured_at, previous_captured_at
  from ranked_gainers
  where rank <= 10
  union all
  select
    group_id, category_id, sub_type_name, direction, rank::smallint as rank,
    product_id, product_name, group_name, image_url,
    current_price, previous_price, abs_change, pct_change,
    captured_at, previous_captured_at
  from ranked_losers
  where rank <= 10;

  -- Upsert the fresh top-10 — values overwrite, identity (PK) stays.
  insert into public.movers (
    group_id, category_id, sub_type_name, direction, rank,
    product_id, product_name, group_name, image_url,
    current_price, previous_price, abs_change, pct_change,
    captured_at, previous_captured_at, refreshed_at
  )
  select
    f.group_id, f.category_id, f.sub_type_name, f.direction, f.rank,
    f.product_id, f.product_name, f.group_name, f.image_url,
    f.current_price, f.previous_price, f.abs_change, f.pct_change,
    f.captured_at, f.previous_captured_at, v_now
  from _movers_fresh f
  on conflict (group_id, sub_type_name, direction, rank) do update
  set
    category_id          = excluded.category_id,
    product_id           = excluded.product_id,
    product_name         = excluded.product_name,
    group_name           = excluded.group_name,
    image_url            = excluded.image_url,
    current_price        = excluded.current_price,
    previous_price       = excluded.previous_price,
    abs_change           = excluded.abs_change,
    pct_change           = excluded.pct_change,
    captured_at          = excluded.captured_at,
    previous_captured_at = excluded.previous_captured_at,
    refreshed_at         = excluded.refreshed_at;

  -- Delete rows whose PK no longer matches any fresh top-10 row.
  -- Anything that fell out of the 90-day window or out of its set's
  -- top 10 simply isn't in _movers_fresh, so it gets removed here.
  delete from public.movers m
  where not exists (
    select 1
    from _movers_fresh f
    where f.group_id      = m.group_id
      and f.sub_type_name = m.sub_type_name
      and f.direction     = m.direction
      and f.rank          = m.rank
  );
end;
$$;

grant execute on function public.refresh_movers() to service_role;

-- ---------------------------------------------------------------
-- Retention: prune tcg_price_history beyond 90 days
-- ---------------------------------------------------------------
--
-- Called from the scraper after refresh_movers() so freshness and
-- retention stay in lockstep. Service-role only — clients never need
-- to invoke it. Returns the row count for log lines.

create or replace function public.prune_tcg_price_history()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
begin
  with deleted as (
    delete from public.tcg_price_history
    where captured_at < now() - interval '90 days'
    returning 1
  )
  select count(*) into v_deleted from deleted;
  return v_deleted;
end;
$$;

grant execute on function public.prune_tcg_price_history() to service_role;

-- ---------------------------------------------------------------
-- Update get_top_movers() to read the new table.
-- ---------------------------------------------------------------
--
-- Same signature, same result columns. Rows are sourced from the
-- per-set top-10 buckets, so a single hot set can contribute at most
-- 10 entries to the global category list. The ORDER BY uses both the
-- gainers DESC and losers ASC arms — exactly one is non-null per call.

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
    and m.direction     = p_direction
  order by
    case when p_direction = 'gainers' then m.pct_change end desc nulls last,
    case when p_direction = 'losers'  then m.pct_change end asc  nulls last,
    abs(m.abs_change) desc
  limit greatest(p_limit, 0);
$$;

grant execute on function public.get_top_movers(int, text, int, text) to anon, authenticated;
