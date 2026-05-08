-- 20260508210000_refresh_movers_function_timeout.sql
--
-- The maintenance RPCs (refresh_movers, prune_tcg_price_history) are
-- invoked by the scraper via the data API using a service_role JWT.
-- PostgREST opens its pool connections as `authenticator`, whose
-- ALTER ROLE-set statement_timeout (8s) is loaded at connect time;
-- `SET LOCAL ROLE service_role` per request does NOT reset that
-- session GUC. As tcg_price_history grows past ~800K rows the full
-- refresh exceeds 8s, the connection is killed by Postgres, the JS
-- client returns an error that the scraper currently swallows, and
-- the workflow goes green with a stale movers table.
--
-- Per-function GUCs (`ALTER FUNCTION ... SET ...`) are applied via
-- `SET LOCAL` when entering the function and override the session
-- value for the duration of the call, regardless of caller. 5 min
-- gives 30x current headroom while still bounding pathological runs.

alter function public.refresh_movers()
  set statement_timeout = '5min';

alter function public.prune_tcg_price_history()
  set statement_timeout = '5min';
