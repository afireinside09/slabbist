-- 20260424170000_graded_card_identities_uniq_with_name.sql
-- Include card_name in the graded_card_identities unique index so that distinct
-- cards sharing the same (game, language, set_name, card_number, variant) tuple
-- -- e.g. the Tropical Mega Battle Trophy Trainers, or different SIRs in the
-- same set with temporarily null numbers in seed data -- can coexist as
-- separate identities. The in-code match in findOrCreateIdentity already keys
-- on card_name; this aligns the DB with that semantic.

drop index if exists public.graded_card_identities_unique_idx;

create unique index if not exists graded_card_identities_unique_idx
  on public.graded_card_identities(
    game,
    language,
    set_name,
    card_number,
    coalesce(variant, ''),
    card_name
  );
