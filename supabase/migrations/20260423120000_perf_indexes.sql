-- Performance hot-path indexes. Adds partial + composite indexes to
-- serve the most frequently executed queries (home screen lot list,
-- pending-validation queue, RLS membership check) without table scans.
--
-- Each CREATE INDEX runs non-concurrently here because Supabase's
-- migration harness executes each migration in a single transaction.
-- For live shops with significant table sizes, reapply equivalents
-- with `CREATE INDEX CONCURRENTLY` in a dedicated migration before
-- the data grows past a few hundred thousand rows.
--
-- Verify plans after applying:
--   EXPLAIN (ANALYZE, BUFFERS)
--   SELECT id, name, status FROM lots
--   WHERE store_id = '…' AND status = 'open'
--   ORDER BY created_at DESC LIMIT 50;
--
-- Expect: `Index Scan using lots_open_created_desc` (or
-- `lots_store_created_desc` for status != 'open' variants).

-- ---------------------------------------------------------------
-- store_members: RLS hot path.
--
-- `is_store_member(target_store)` runs for every row of every SELECT
-- on stores/lots/scans. The existing `store_members_user_id` index
-- serves `user_id = auth.uid()` but requires a heap lookup to check
-- `store_id`. The composite lets the check run as an index-only scan.
-- ---------------------------------------------------------------

create index if not exists store_members_user_store
  on store_members(user_id, store_id);

-- The composite above is a superset of the single-column index; drop
-- the old one. Safe: Postgres uses the leading column of the composite
-- to serve `user_id = X` queries.
drop index if exists store_members_user_id;

-- ---------------------------------------------------------------
-- lots: home-screen list (store_id, ordered by created_at desc).
--
-- The existing `lots_store_status` covers WHERE store_id=X AND status=Y
-- but still requires a sort on created_at. These two indexes remove
-- that sort for the common cases.
-- ---------------------------------------------------------------

-- General-purpose: every "recent lots in store" query.
create index if not exists lots_store_created_desc
  on lots(store_id, created_at desc);

-- Partial: smaller, cache-resident, serves the hottest filter
-- ("open lots in my store, newest first"). Size is proportional only
-- to the count of open lots, not the whole table.
create index if not exists lots_open_store_created_desc
  on lots(store_id, created_at desc)
  where status = 'open';

-- ---------------------------------------------------------------
-- scans: lot-detail list + validation queue.
-- ---------------------------------------------------------------

-- Scans within a lot, oldest first (capture order).
create index if not exists scans_lot_created_asc
  on scans(lot_id, created_at asc);

-- Validation queue: all pending scans in a store, oldest first.
create index if not exists scans_pending_store_created_asc
  on scans(store_id, created_at asc)
  where status = 'pending_validation';

-- Validation queue filtered to a single lot.
create index if not exists scans_pending_lot_created_asc
  on scans(lot_id, created_at asc)
  where status = 'pending_validation';
