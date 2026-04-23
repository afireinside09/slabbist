-- On every new auth.users row, create a store and an owner membership.
-- This is the MVP auto-bootstrap; Plan 1 of sub-project 1 replaces this
-- with an explicit multi-user flow.
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_store_id uuid;
  default_name text;
begin
  default_name := coalesce(new.raw_user_meta_data->>'store_name', 'My Store');

  insert into stores (name, owner_user_id)
  values (default_name, new.id)
  returning id into new_store_id;

  insert into store_members (store_id, user_id, role)
  values (new_store_id, new.id, 'owner');

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
