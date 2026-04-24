-- 20260423160000_graded_watchlist.sql
-- Watchlist of graded slabs the eBay ingest actively tracks on its 6-hour cadence.
-- Seeded with ~200 popular slabs; auto-promoted by iOS scan activity
-- (>= 5 distinct certs scanned in trailing 7 days).

create table if not exists public.graded_watchlist (
  identity_id       uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service   text not null check (grading_service in ('PSA','CGC','BGS','SGC','TAG')),
  grade             text not null,
  source            text not null check (source in ('seed','auto_promoted','manual')),
  popularity_rank   int,
  is_active         boolean not null default true,
  scan_count_7d     int not null default 0,
  last_scraped_at   timestamptz,
  last_promoted_at  timestamptz,
  added_at          timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (identity_id, grading_service, grade)
);

create index if not exists graded_watchlist_active_rank_idx
  on public.graded_watchlist(is_active, popularity_rank nulls last, identity_id);

alter table public.graded_watchlist enable row level security;
drop policy if exists graded_watchlist_public_read on public.graded_watchlist;
create policy graded_watchlist_public_read on public.graded_watchlist for select using (true);

create or replace function public.promote_scanned_slabs_to_watchlist(
  min_scans int default 5,
  window_days int default 7
)
returns int
language plpgsql
security definer
set search_path = public
as $fn$
declare
  rows_promoted int;
begin
  with scan_aggregates as (
    select
      gc.identity_id,
      gc.grading_service,
      gc.grade,
      count(distinct s.cert_number)::int as scans_window
    from public.scans s
    join public.graded_cards gc
      on gc.grading_service = s.grader::text
     and gc.cert_number = s.cert_number
    where s.created_at >= now() - make_interval(days => window_days)
    group by gc.identity_id, gc.grading_service, gc.grade
    having count(distinct s.cert_number) >= min_scans
  ),
  upserted as (
    insert into public.graded_watchlist
      (identity_id, grading_service, grade, source,
       scan_count_7d, last_promoted_at, is_active, updated_at)
    select
      sa.identity_id, sa.grading_service, sa.grade,
      'auto_promoted', sa.scans_window, now(), true, now()
    from scan_aggregates sa
    on conflict (identity_id, grading_service, grade) do update
      set scan_count_7d    = excluded.scan_count_7d,
          last_promoted_at = excluded.last_promoted_at,
          is_active        = true,
          updated_at       = now()
    returning 1
  )
  select count(*)::int into rows_promoted from upserted;
  return coalesce(rows_promoted, 0);
end;
$fn$;
