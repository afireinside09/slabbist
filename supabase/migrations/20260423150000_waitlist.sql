-- Pre-launch email waitlist from the marketing site (slabbist.com).
--
-- Writes are only allowed via the server-side API route
-- (marketing/app/api/waitlist/route.ts), which uses the service-role
-- key. The client does NOT write directly, so we can enforce
-- rate limiting and capture a hashed IP before insert.

create table public.waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  audience text not null,
  created_at timestamptz not null default now(),
  source text,
  user_agent text,
  ip_hash text,
  constraint waitlist_audience_chk
    check (audience in ('store', 'collector')),
  constraint waitlist_email_format_chk
    check (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

create unique index waitlist_email_lower_uidx
  on public.waitlist (lower(email));

-- Supports rate-limit lookups: "how many signups from this IP in the
-- last 60s?" — ip_hash filter + descending created_at.
create index waitlist_ip_hash_recent_idx
  on public.waitlist (ip_hash, created_at desc);

alter table public.waitlist enable row level security;

-- No non-privileged role can touch this table. Only service_role
-- (which bypasses RLS) may read/write, and that only happens from
-- the Next.js server runtime.
revoke all on public.waitlist from anon, authenticated;

comment on table  public.waitlist is 'Pre-launch email waitlist from slabbist.com marketing site. Writes only via server API route.';
comment on column public.waitlist.audience is 'store | collector';
comment on column public.waitlist.source   is 'document.referrer at time of submit, optional';
comment on column public.waitlist.ip_hash  is 'SHA-256 of (client IP + WAITLIST_IP_SALT); used for per-IP rate limiting, not reversible';
