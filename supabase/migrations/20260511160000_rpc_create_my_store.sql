-- Client-callable RPC that creates a store owned by the authenticated
-- user plus the matching `store_members` row. Mirrors the signup-time
-- `handle_new_user()` trigger so users whose trigger didn't seed a
-- store (e.g. accounts predating the bootstrap migration, or any
-- future flow where a user lands without a store) can self-serve from
-- the iOS app.
--
-- There is no INSERT RLS policy on `stores` — INSERTs must go through
-- a `security definer` function so the membership row is always
-- created in lockstep.
create or replace function create_my_store(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  new_store_id uuid;
  trimmed_name text := nullif(btrim(p_name), '');
begin
  if caller_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if trimmed_name is null then
    raise exception 'store name is required' using errcode = '22023';
  end if;

  insert into stores (name, owner_user_id)
  values (trimmed_name, caller_id)
  returning id into new_store_id;

  insert into store_members (store_id, user_id, role)
  values (new_store_id, caller_id, 'owner');

  return new_store_id;
end;
$$;

revoke all on function create_my_store(text) from public;
grant execute on function create_my_store(text) to authenticated;
