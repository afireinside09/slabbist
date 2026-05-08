-- Follow-up to 20260508183209: add the partial index and the missing
-- column comment that the code review caught.

create index if not exists graded_card_identities_poketrace_card_idx
  on public.graded_card_identities (poketrace_card_id)
  where poketrace_card_id is not null and poketrace_card_id <> '';

comment on column public.graded_card_identities.poketrace_card_id_resolved_at is
  'Timestamp of the last Poketrace cross-walk attempt. NULL = never attempted. Re-attempt is allowed when older than 7 days regardless of the poketrace_card_id value.';
