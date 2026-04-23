begin;
select plan(5);

-- pgTAP is installed into the test database by `supabase test db`.
create extension if not exists pgtap;

-- Create two users and impersonate them via the JWT-claims setter used by Supabase RLS.
insert into auth.users (id, email, aud, role)
values
  ('00000000-0000-0000-0000-000000000001', 'a@test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000000002', 'b@test', 'authenticated', 'authenticated');

-- Triggers created their stores and owner memberships. Capture store ids as the
-- superuser (before switching to the authenticated role) so they survive across
-- jwt-claim switches and are not filtered by RLS when we need to reference the
-- "other" user's store in a cross-tenant attack below.
create temporary table _test_store_ids on commit drop as
select owner_user_id, id as store_id from stores;
grant select on _test_store_ids to authenticated;

-- Triggers created their stores and owner memberships.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

-- As user A, count visible stores = 1
select is((select count(*)::int from stores), 1, 'user A sees exactly their own store');

-- Switch to user B
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);

-- As user B, count visible stores = 1 (different one)
select is((select count(*)::int from stores), 1, 'user B sees exactly their own store');

-- User B inserting a lot into user A's store should fail. Pull A's store_id
-- from the pre-captured temp table so the RLS SELECT filter on `stores` does
-- not hide it and turn the INSERT into a silent no-op.
select throws_ok($$
  insert into lots (store_id, created_by_user_id, name)
  select store_id, '00000000-0000-0000-0000-000000000002', 'Should not work'
  from _test_store_ids
  where owner_user_id = '00000000-0000-0000-0000-000000000001';
$$, NULL, 'user B cannot insert a lot in user A''s store');

-- Positive: user B can insert a lot in their own store.
select lives_ok($$
  insert into lots (store_id, created_by_user_id, name)
  select store_id, '00000000-0000-0000-0000-000000000002', 'B lot'
  from _test_store_ids
  where owner_user_id = '00000000-0000-0000-0000-000000000002';
$$, 'user B can insert a lot in their own store');

-- User A should not see user B's lot.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is((select count(*)::int from lots where name = 'B lot'), 0, 'user A cannot see user B''s lot');

select * from finish();
rollback;
