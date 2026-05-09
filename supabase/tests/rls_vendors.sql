-- supabase/tests/rls_vendors.sql
--
-- pgTAP coverage for vendors RLS: store-A user can CRUD their own vendors,
-- store-B user cannot read or write store-A's vendors. Mirrors the pattern
-- in supabase/tests/rls_tenant_isolation.sql.

begin;
select plan(8);

create extension if not exists pgtap;

insert into auth.users (id, email, aud, role)
values
  ('00000000-0000-0000-0000-0000000000a1', 'a@vendors.test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b1', 'b@vendors.test', 'authenticated', 'authenticated');

-- Triggers from 20260422000007_signup_bootstrap.sql have already created a
-- store + owner membership for each user. Capture both store ids before
-- switching roles so the cross-tenant probe below has a valid id to attack.
create temporary table _store_ids on commit drop as
select owner_user_id, id as store_id from stores;
grant select on _store_ids to authenticated;

set local role authenticated;

-- USER A: insert + select
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

select lives_ok($$
  insert into vendors (store_id, display_name, contact_method, contact_value)
  select store_id, 'Acme Cards', 'phone', '555-0100'
  from _store_ids
  where owner_user_id = '00000000-0000-0000-0000-0000000000a1';
$$, 'A can insert a vendor in their own store');

select is(
  (select display_name from vendors
   where store_id = (select store_id from _store_ids
                     where owner_user_id = '00000000-0000-0000-0000-0000000000a1')),
  'Acme Cards',
  'A reads back their own vendor');

-- USER B: cannot see A's vendors
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);

select is((select count(*)::int from vendors), 0, 'B sees zero vendors (RLS isolates)');

-- USER B: cannot insert into A's store
select throws_ok($$
  insert into vendors (store_id, display_name)
  select store_id, 'Sneaky'
  from _store_ids
  where owner_user_id = '00000000-0000-0000-0000-0000000000a1';
$$, NULL, 'B cannot insert a vendor into A''s store');

-- USER B: their own insert lives
select lives_ok($$
  insert into vendors (store_id, display_name)
  select store_id, 'B Vendor'
  from _store_ids
  where owner_user_id = '00000000-0000-0000-0000-0000000000b1';
$$, 'B can insert their own vendor');

-- USER A: still cannot see B's vendor (symmetric isolation check)
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

select is(
  (select count(*)::int from vendors where display_name = 'B Vendor'),
  0,
  'A cannot see B''s vendor');

-- USER B: cannot update A's vendor (returns 0 rows updated under RLS, no row matches USING)
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);

create temporary table _upd_b on commit drop as
with upd as (
  update vendors set display_name = 'pwned'
  where display_name = 'Acme Cards'
  returning 1
)
select count(*)::int as n from upd;

select is((select n from _upd_b), 0, 'B cannot update A''s vendor (RLS USING filters it out)');

-- USER A: archive (soft delete) works
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

create temporary table _upd_a on commit drop as
with upd as (
  update vendors set archived_at = now()
  where display_name = 'Acme Cards'
  returning 1
)
select count(*)::int as n from upd;

select is((select n from _upd_a), 1, 'A can archive their own vendor');

select * from finish();
rollback;
