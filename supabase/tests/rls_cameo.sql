-- cameo_subjects / cameo_cards: anyone may read; only service-role may write.
begin;
create extension if not exists pgtap;
select plan(4);

-- Service-role-equivalent (superuser) write succeeds — the seed-script path.
select lives_ok($$
  insert into public.cameo_subjects (id, kind, ndex, name, card_count)
  values ('22222222-2222-2222-2222-222222222222', 'pokemon', 25, 'Pikachu', 1);
$$, 'service-role can insert a cameo subject');

select lives_ok($$
  insert into public.cameo_cards (subject_id, card_name, set_name, card_number, generation)
  values ('22222222-2222-2222-2222-222222222222', 'Pokémon March', 'Neo Genesis', '102', 'Gen 2');
$$, 'service-role can insert a cameo card');

-- Become an authenticated end-user.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated"}', true);

select lives_ok($$ select 1 from public.cameo_subjects limit 1; $$,
  'authenticated can select cameo subjects');

select throws_ok($$
  insert into public.cameo_subjects (kind, name) values ('pokemon', 'Bulbasaur');
$$, NULL, 'authenticated cannot insert cameo subjects');

select * from finish();
rollback;
