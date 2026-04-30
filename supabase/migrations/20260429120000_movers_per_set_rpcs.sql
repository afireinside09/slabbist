-- 20260429120000_movers_per_set_rpcs.sql
-- Read RPCs that let the iOS Movers tab filter by language + set,
-- plus the public-read RLS policy that the table was missing.
--
-- Why a public-read policy here and not in the table-creation migration:
--   `20260428170000_movers_per_set_table.sql` enabled RLS implicitly
--   (Supabase defaults to RLS-on for `public.*` tables) but never
--   declared a SELECT policy. With RLS on and zero policies, the anon
--   role's view through the RPCs is empty — `get_top_movers` is
--   `SECURITY INVOKER`, so it inherits the caller's row visibility.
--   That broke the iOS Movers tab silently. We add the policy here
--   instead of forking a one-line follow-up migration so this single
--   timestamp is the "Movers tab works" cut-line.
--
-- Why server-side functions and not direct PostgREST queries:
--   `get_movers_sets` needs DISTINCT-style aggregation joined to
--   `tcg_groups` for the `published_on` sort key — awkward to express
--   as a PostgREST URL, easy as a function. `get_set_movers` returns
--   both directions in one round-trip (≤20 rows), so the client can
--   render gainers + losers without a second request.
--
-- Index usage:
--   - get_movers_sets    → movers_category_direction_pct_idx covers the
--                          WHERE (category_id, sub_type_name); group-by
--                          on group_id is in-memory over a small set.
--   - get_set_movers     → primary key (group_id, sub_type_name,
--                          direction, rank) is a direct index lookup,
--                          ≤20 rows returned in PK order.

-- ---------------------------------------------------------------
-- Public-read policy on public.movers. Mirrors the pattern used by
-- the other read-only TCG tables (tcg_products, tcg_groups, …) which
-- also expose pre-derived public data to anon. Idempotent so a
-- re-run doesn't error.
-- ---------------------------------------------------------------

alter table public.movers enable row level security;
drop policy if exists movers_public_read on public.movers;
create policy movers_public_read
  on public.movers
  for select
  using (true);

-- ---------------------------------------------------------------
-- get_movers_sets — list groups (sets) with at least one mover row
-- in the requested category + sub_type, ordered newest-first.
-- ---------------------------------------------------------------

create or replace function public.get_movers_sets(
  p_category_id int,
  p_sub_type    text default 'Normal'
)
returns table (
  group_id     int,
  group_name   text,
  movers_count int,
  published_on date
)
language sql
stable
as $$
  with sets as (
    select m.group_id, count(*)::int as movers_count
    from public.movers m
    where m.category_id   = p_category_id
      and m.sub_type_name = p_sub_type
    group by m.group_id
  )
  select
    s.group_id,
    g.name           as group_name,
    s.movers_count,
    g.published_on
  from sets s
  join public.tcg_groups g on g.group_id = s.group_id
  order by g.published_on desc nulls last, g.name asc;
$$;

grant execute on function public.get_movers_sets(int, text) to anon, authenticated;

-- ---------------------------------------------------------------
-- get_set_movers — both directions (gainers + losers) for one set.
-- Returns ≤20 rows; client splits by `direction`. Single round-trip
-- replaces what would otherwise be two REST calls.
-- ---------------------------------------------------------------

create or replace function public.get_set_movers(
  p_group_id int,
  p_sub_type text default 'Normal'
)
returns table (
  direction            text,
  rank                 smallint,
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
    m.direction,
    m.rank,
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
  where m.group_id      = p_group_id
    and m.sub_type_name = p_sub_type
  order by m.direction asc, m.rank asc;
$$;

grant execute on function public.get_set_movers(int, text) to anon, authenticated;
