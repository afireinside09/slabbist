-- 20260601130000_grade_comp_candidates_batched.sql
-- grade_comp_candidates() sorted the entire English catalog by published_on
-- and exceeded the statement timeout. Replace with a group-batched approach:
-- walk groups newest-first (cheap) and pull each group's stale candidates by
-- group_id index (cheap), avoiding a global product sort.

drop function if exists public.grade_comp_candidates();

create or replace function public.grade_comp_groups()
returns table (group_id int)
language sql stable as $$
  select g.group_id
  from public.tcg_groups g
  where g.category_id = 3
  order by g.published_on desc nulls last, g.group_id asc;
$$;

grant execute on function public.grade_comp_groups() to service_role;

create or replace function public.grade_comp_candidates_for_group(p_group_id int)
returns table (product_id int, resolved_at timestamptz)
language sql stable as $$
  select p.product_id, c.resolved_at
  from public.tcg_products p
  left join public.tcg_grade_comp c on c.product_id = p.product_id
  where p.group_id = p_group_id
    and exists (select 1 from public.tcg_prices pr
                where pr.product_id = p.product_id
                  and pr.market_price is not null and pr.market_price > 0)
    and (c.resolved_at is null or c.resolved_at < now() - interval '7 days')
  order by p.product_id asc;
$$;

grant execute on function public.grade_comp_candidates_for_group(int) to service_role;
