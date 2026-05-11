-- supabase/tests/rls_transactions.sql
begin;
select plan(4);
create extension if not exists pgtap;

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000c1', 'a@txn.test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000c2', 'b@txn.test', 'authenticated', 'authenticated');

create temporary table _store_ids on commit drop as
select owner_user_id, id as store_id from stores;
grant select on _store_ids to authenticated, service_role;

-- Bypass the policy via service role to insert seed data.
set local role service_role;

insert into vendors (store_id, display_name)
select store_id, 'A Vendor' from _store_ids
where owner_user_id = '00000000-0000-0000-0000-0000000000c1';

insert into lots (store_id, created_by_user_id, name, lot_offer_state)
select store_id, '00000000-0000-0000-0000-0000000000c1', 'A Lot', 'accepted'
from _store_ids where owner_user_id = '00000000-0000-0000-0000-0000000000c1';

insert into transactions (store_id, lot_id, vendor_id, vendor_name_snapshot,
                          total_buy_cents, payment_method, paid_at, paid_by_user_id)
select s.store_id, l.id, v.id, 'A Vendor', 1000, 'cash', now(), '00000000-0000-0000-0000-0000000000c1'
from _store_ids s
join lots l on l.store_id = s.store_id and l.name = 'A Lot'
join vendors v on v.store_id = s.store_id and v.display_name = 'A Vendor'
where s.owner_user_id = '00000000-0000-0000-0000-0000000000c1';

set local role authenticated;

-- USER A sees their own transaction
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
select is((select count(*)::int from transactions), 1, 'A sees their own transaction');

-- USER B sees zero
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
select is((select count(*)::int from transactions), 0, 'B sees no transactions across tenants');

-- USER A cannot insert a transaction directly (no policy permits insert)
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);

select throws_ok($$
  insert into transactions (store_id, lot_id, vendor_name_snapshot,
                            total_buy_cents, payment_method, paid_at, paid_by_user_id)
  select s.store_id, l.id, 'X', 100, 'cash', now(), '00000000-0000-0000-0000-0000000000c1'
  from _store_ids s join lots l on l.store_id = s.store_id and l.name = 'A Lot'
  where s.owner_user_id = '00000000-0000-0000-0000-0000000000c1';
$$, NULL, 'A cannot insert a transaction directly (write must go through Edge Function)');

-- transaction_lines select scopes via parent transaction
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
select is((select count(*)::int from transaction_lines), 0, 'B sees no transaction lines either');

select * from finish();
rollback;
