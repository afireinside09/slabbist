-- supabase/migrations/20260507120100_add_ppt_columns_to_identities.sql

alter table public.graded_card_identities
  add column if not exists ppt_tcgplayer_id text,
  add column if not exists ppt_url          text;

create index if not exists graded_card_identities_ppt_tcgplayer_idx
  on public.graded_card_identities (ppt_tcgplayer_id)
  where ppt_tcgplayer_id is not null;
