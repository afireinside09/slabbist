-- Cameo Dex: global reference data (same class as tcg_*/graded_*).
-- Not store-scoped. Public read; writes only via service role (seed script).

create table if not exists public.cameo_subjects (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('pokemon','trainer')),
  ndex        int,
  region      text,
  name        text not null,
  card_count  int  not null default 0,
  unique (kind, name)
);

create table if not exists public.cameo_cards (
  id           uuid primary key default gen_random_uuid(),
  subject_id   uuid not null references public.cameo_subjects(id) on delete cascade,
  card_name    text not null,
  set_name     text not null,
  card_number  text,
  notes        text,
  generation   text not null
);
create index if not exists cameo_cards_subject_id_idx on public.cameo_cards(subject_id);
create index if not exists cameo_subjects_name_idx on public.cameo_subjects(name);

-- Public-read RLS, mirroring the tcg_* pattern. No write policy: the seed
-- script connects with the service role, which bypasses RLS.
do $$
declare t text;
begin
  foreach t in array array['cameo_subjects','cameo_cards'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_public_read', t);
    execute format('create policy %I on public.%I for select using (true)', t || '_public_read', t);
  end loop;
end $$;
