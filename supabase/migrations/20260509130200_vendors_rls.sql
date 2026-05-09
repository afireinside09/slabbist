-- supabase/migrations/20260509130200_vendors_rls.sql
--
-- Vendors are tenant data; reuse the `is_store_member()` helper defined in
-- `20260422000006_rls_policies.sql`. No DELETE policy — archive only.

alter table vendors enable row level security;

create policy vendors_select_members
  on vendors for select
  using (is_store_member(store_id));

create policy vendors_insert_members
  on vendors for insert
  with check (is_store_member(store_id));

create policy vendors_update_members
  on vendors for update
  using (is_store_member(store_id))
  with check (is_store_member(store_id));
