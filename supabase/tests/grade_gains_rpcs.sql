-- supabase/tests/grade_gains_rpcs.sql
-- Run: psql "$DATABASE_URL" -f supabase/tests/grade_gains_rpcs.sql
begin;

-- Minimal fixtures in a disposable group id unlikely to collide.
insert into public.tcg_groups (group_id, category_id, name, published_on)
  values (999001, 3, 'TEST Grade Gains Set', date '2024-01-01')
  on conflict (group_id) do nothing;

-- Product A: holo subtype is the chase (raw $4 → under_5 band), PSA10 $50 → spread 4600
insert into public.tcg_products (product_id, group_id, category_id, name, card_number)
  values (999101, 999001, 3, 'TEST Card A', '1/100') on conflict do nothing;
insert into public.tcg_prices (product_id, sub_type_name, market_price, updated_at) values
  (999101, 'Normal',   1.00, now()),
  (999101, 'Holofoil', 4.00, now())
  on conflict (product_id, sub_type_name) do update set market_price = excluded.market_price;
insert into public.tcg_grade_comp (product_id, poketrace_card_id, psa10_price_cents, resolved_at)
  values (999101, 'uuid-a', 5000, now())
  on conflict (product_id) do update set psa10_price_cents = excluded.psa10_price_cents;

-- Product B: raw $30 (tier_25_50), PSA10 $40 → spread 1000
insert into public.tcg_products (product_id, group_id, category_id, name, card_number)
  values (999102, 999001, 3, 'TEST Card B', '2/100') on conflict do nothing;
insert into public.tcg_prices (product_id, sub_type_name, market_price, updated_at)
  values (999102, 'Normal', 30.00, now())
  on conflict (product_id, sub_type_name) do update set market_price = excluded.market_price;
insert into public.tcg_grade_comp (product_id, poketrace_card_id, psa10_price_cents, resolved_at)
  values (999102, 'uuid-b', 4000, now())
  on conflict (product_id) do update set psa10_price_cents = excluded.psa10_price_cents;

-- Product C: negative spread (PSA10 < raw) → must NOT appear
insert into public.tcg_products (product_id, group_id, category_id, name, card_number)
  values (999103, 999001, 3, 'TEST Card C', '3/100') on conflict do nothing;
insert into public.tcg_prices (product_id, sub_type_name, market_price, updated_at)
  values (999103, 'Normal', 100.00, now())
  on conflict (product_id, sub_type_name) do update set market_price = excluded.market_price;
insert into public.tcg_grade_comp (product_id, poketrace_card_id, psa10_price_cents, resolved_at)
  values (999103, 'uuid-c', 5000, now())
  on conflict (product_id) do update set psa10_price_cents = excluded.psa10_price_cents;

-- Assertion 1: under_5 band returns Card A only, raw from the HOLO subtype ($4 → 400c).
do $$
declare r record; begin
  select * into r from public.get_set_grade_gains(999001, 'under_5');
  assert r.product_id = 999101, 'expected Card A in under_5';
  assert r.raw_price_cents = 400, format('expected raw 400c (holo), got %s', r.raw_price_cents);
  assert r.sub_type_name = 'Holofoil', 'expected the highest-priced subtype';
  assert r.spread_cents = 4600, format('expected spread 4600, got %s', r.spread_cents);
end $$;

-- Assertion 2: tier_25_50 returns Card B; Card C (negative spread) is absent everywhere.
do $$
declare cnt int; begin
  select count(*) into cnt from public.get_set_grade_gains(999001, 'tier_25_50');
  assert cnt = 1, format('expected 1 row in tier_25_50, got %s', cnt);
  select count(*) into cnt from public.get_set_grade_gains(999001, 'tier_100_200')
    where product_id = 999103;
  assert cnt = 0, 'negative-spread Card C must never appear';
end $$;

-- Assertion 3: set count (gains_count) equals the total positive-spread products in the set (A + B = 2).
do $$
declare gc int; begin
  select gains_count into gc from public.get_grade_gain_sets() where group_id = 999001;
  assert gc = 2, format('expected gains_count 2, got %s', gc);
end $$;

rollback;  -- leave the DB clean; fixtures vanish.
\echo 'grade_gains_rpcs.sql: ALL ASSERTIONS PASSED'
