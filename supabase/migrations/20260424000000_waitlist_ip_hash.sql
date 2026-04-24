-- Bring prod in sync with the intent of 20260423150000_waitlist.sql.
--
-- That file was edited in place after being applied, so production is
-- missing the ip_hash column the marketing API relies on for rate
-- limiting. The API also moved from anon-insert to service-role writes,
-- so drop the anon insert policy and revoke the base grants.

alter table public.waitlist
  add column if not exists ip_hash text;

create index if not exists waitlist_ip_hash_recent_idx
  on public.waitlist (ip_hash, created_at desc);

drop policy if exists waitlist_anon_insert on public.waitlist;

revoke all on public.waitlist from anon, authenticated;

comment on column public.waitlist.ip_hash is
  'SHA-256 of (client IP + WAITLIST_IP_SALT); used for per-IP rate limiting, not reversible';
comment on column public.waitlist.source is
  'document.referrer at time of submit, optional';
