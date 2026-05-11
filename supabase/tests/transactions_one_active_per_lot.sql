-- supabase/tests/transactions_one_active_per_lot.sql
begin;
select plan(2);
create extension if not exists pgtap;

-- auth.users insert runs as the default (superuser) role; service_role
-- lacks INSERT privileges on auth.users locally. The signup_bootstrap
-- trigger creates the matching stores row.
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'u@active.test', 'authenticated', 'authenticated');

create temporary table _ids on commit drop as
select id as store_id, owner_user_id from stores
where owner_user_id = '00000000-0000-0000-0000-0000000000d1' limit 1;
grant select on _ids to service_role;

set local role service_role;

insert into lots (store_id, created_by_user_id, name, lot_offer_state)
select store_id, owner_user_id, 'L', 'accepted' from _ids;

insert into transactions (store_id, lot_id, vendor_name_snapshot, total_buy_cents,
                          payment_method, paid_at, paid_by_user_id)
select s.store_id, l.id, 'V', 100, 'cash', now(), s.owner_user_id
from _ids s join lots l on l.store_id = s.store_id;

-- A second active transaction for the same lot must fail.
select throws_ok($$
  insert into transactions (store_id, lot_id, vendor_name_snapshot, total_buy_cents,
                            payment_method, paid_at, paid_by_user_id)
  select s.store_id, l.id, 'V', 200, 'cash', now(), s.owner_user_id
  from _ids s join lots l on l.store_id = s.store_id;
$$, '23505', NULL, 'unique partial index rejects a second non-voided txn for the same lot');

-- A void row (void_of_transaction_id IS NOT NULL) is allowed.
select lives_ok($$
  insert into transactions (store_id, lot_id, vendor_name_snapshot, total_buy_cents,
                            payment_method, paid_at, paid_by_user_id, void_of_transaction_id)
  select s.store_id, l.id, 'V', -100, 'cash', now(), s.owner_user_id, t.id
  from _ids s
  join lots l on l.store_id = s.store_id
  join transactions t on t.lot_id = l.id and t.void_of_transaction_id is null;
$$, 'void rows can be inserted alongside the original');

select * from finish();
rollback;
