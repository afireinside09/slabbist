-- Adds RLS DELETE policies for `lots` and `scans` so members of a store
-- can remove rows their app has already removed locally + enqueued in
-- the outbox. The original tenant migration only granted SELECT/INSERT/
-- UPDATE; without these, the iOS outbox worker's DELETE round-trip
-- silently fails server-side and rows reappear on next hydration.

create policy lots_delete_members
  on lots for delete
  using (is_store_member(store_id));

create policy scans_delete_members
  on scans for delete
  using (is_store_member(store_id));
