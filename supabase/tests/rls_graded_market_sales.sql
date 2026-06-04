-- supabase/tests/rls_graded_market_sales.sql
-- graded_market_sales: authenticated may read; only service-role may write.
-- Mirrors the slab_scan_events RLS shape (select to authenticated; writes via
-- the Edge Function's service-role connection, which bypasses RLS).
begin;
create extension if not exists pgtap;
select plan(3);

-- Seed a parent identity as superuser (bypasses RLS) so the FK is satisfiable.
insert into public.graded_card_identities (id, language, set_name, card_name)
values ('11111111-1111-1111-1111-111111111111', 'en', 'RLS Test Set', 'RLS Test Card');

-- Superuser / service-role-equivalent write succeeds (the Edge Function path).
select lives_ok($$
  insert into public.graded_market_sales
    (identity_id, grading_service, grade, source, source_listing_id, sold_price, sold_at)
  values
    ('11111111-1111-1111-1111-111111111111', 'PSA', '10', 'ebay', 'rls-test-1', 100.00, now());
$$, 'service-role can insert a sold listing');

-- Become an authenticated end-user.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated"}', true);

-- Authenticated can read.
select lives_ok($$ select 1 from public.graded_market_sales limit 1; $$,
  'authenticated can select sold listings');

-- Authenticated cannot write (no insert policy exists).
select throws_ok($$
  insert into public.graded_market_sales
    (identity_id, grading_service, grade, source, source_listing_id, sold_price, sold_at)
  values
    ('11111111-1111-1111-1111-111111111111', 'PSA', '10', 'ebay', 'rls-test-2', 1.00, now());
$$, NULL, 'authenticated cannot insert sold listings');

select * from finish();
rollback;
