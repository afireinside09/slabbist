-- Enable RLS on the tenant tables this sub-project owns.
-- RLS on graded_* and tcg_* tables is set by the tcgcsv migration.
alter table stores          enable row level security;
alter table store_members   enable row level security;
alter table lots            enable row level security;
alter table scans           enable row level security;

-- Helper: "the authenticated user is a member of this store"
create or replace function is_store_member(target_store uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from store_members
    where user_id = auth.uid()
      and store_id = target_store
  );
$$;

-- stores: a member can see their store(s); only the owner can update.
create policy stores_select_members
  on stores for select
  using (is_store_member(id));

create policy stores_update_owner
  on stores for update
  using (owner_user_id = auth.uid())
  with check (owner_user_id = auth.uid());

-- store_members: a member can see the membership rows for their store(s).
create policy store_members_select_members
  on store_members for select
  using (is_store_member(store_id));

-- lots: members can see/insert/update their store's lots.
create policy lots_select_members
  on lots for select
  using (is_store_member(store_id));

create policy lots_insert_members
  on lots for insert
  with check (is_store_member(store_id) and created_by_user_id = auth.uid());

create policy lots_update_members
  on lots for update
  using (is_store_member(store_id))
  with check (is_store_member(store_id));

-- scans: same shape as lots.
create policy scans_select_members
  on scans for select
  using (is_store_member(store_id));

create policy scans_insert_members
  on scans for insert
  with check (is_store_member(store_id) and user_id = auth.uid());

create policy scans_update_members
  on scans for update
  using (is_store_member(store_id))
  with check (is_store_member(store_id));
