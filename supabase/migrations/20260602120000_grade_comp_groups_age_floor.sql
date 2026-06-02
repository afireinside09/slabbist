-- 20260602120000_grade_comp_groups_age_floor.sql
-- Sets published in the last ~90 days have no graded market yet (PSA turnaround
-- + market formation), so resolving their cards wastes Poketrace budget on null
-- PSA 10 prices. Exclude them; keep newest-first among eligible (modern, graded)
-- sets. Sets with a NULL published_on are kept (unknown age, likely backfilled
-- catalog data) so we don't silently drop them.

create or replace function public.grade_comp_groups()
returns table (group_id int)
language sql stable as $$
  select g.group_id
  from public.tcg_groups g
  where g.category_id = 3
    and (g.published_on is null or g.published_on <= current_date - interval '90 days')
  order by g.published_on desc nulls last, g.group_id asc;
$$;

grant execute on function public.grade_comp_groups() to service_role;
