-- supabase/migrations/20260511130300_transactions_rls.sql
--
-- Transactions and lines are read-only for store members. Writes happen via
-- the /transaction-commit and /transaction-void Edge Functions using the
-- service role — no direct INSERT/UPDATE policy for authenticated users.

alter table transactions enable row level security;
alter table transaction_lines enable row level security;

create policy transactions_select_members
  on transactions for select
  using (is_store_member(store_id));

create policy transaction_lines_select_members
  on transaction_lines for select
  using (
    exists (
      select 1 from transactions t
      where t.id = transaction_lines.transaction_id
        and is_store_member(t.store_id)
    )
  );

-- No INSERT/UPDATE/DELETE policies. Service role bypasses RLS by design.
