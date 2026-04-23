# Bulk Scan & Comp — Plan 1: Walking Skeleton

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land a working, testable walking skeleton: a user can sign in, auto-create a store, create a lot, point the camera at a slab, and see the recognized cert number appear in an on-screen queue. No grader lookup, no comps — just the full write path from camera → SwiftData → Supabase (via outbox when online), scoped by `store_id` via Row Level Security.

**Architecture:** Native iOS (SwiftUI + SwiftData + AVFoundation + Vision) talking to a local Supabase stack (Postgres + Auth + RLS). iOS never calls externals directly; writes go through a local `outbox` so the app is offline-safe from day one. Multi-tenant from day one: every tenant row is `store_id`-scoped via RLS, but the MVP's signup flow auto-creates a single-member store per user.

**Tech Stack:**
- iOS: Swift 6, SwiftUI, SwiftData, AVFoundation, Vision, Network (NWPathMonitor), OSLog, Swift Testing (unit), XCUITest (UI)
- Backend: Supabase (Postgres 15 + Auth + RLS + Edge Functions), SQL migrations, pgTAP for RLS tests
- Dependencies: Supabase Swift SDK (via SPM)

**Prerequisites (verified on the dev machine):**
- Xcode 26.4 or newer
- Supabase CLI ≥ 2.90 (`supabase --version`)
- Docker Desktop running (Supabase local stack uses Docker)
- Git configured with a committer identity

**Monorepo coordination (critical):**
- Supabase migrations live in the **shared path** `/Users/dixoncider/slabbist/supabase/migrations/`. The tcgcsv sub-project writes `graded_*` and `tcg_*` migrations to the same directory. This plan owns only the tenant tables (`stores`, `store_members`, `lots`, `scans`).
- The graded-card tables (`graded_card_identities`, `graded_cards`, `graded_market`, `graded_market_sales`, `graded_card_pops`, `graded_cert_sales`, `graded_ingest_runs`) and the raw-card tables (`tcg_*`) are **not defined in Plan 1**. Plan 2 adds FKs from `scans` to `graded_card_identities` / `graded_cards` only once those tables exist — either because tcgcsv landed first, or as a coordinated pair.
- Plan 1's migration timestamps leave headroom (`20260422000001…000002`) so the tcgcsv migration can be timestamped before Plan 2's follow-up `alter table scans` migration without renumbering.
- Do not touch `tcg_*` or `graded_*` tables from this plan's migrations or iOS code. That's a schema-ownership violation (see memory: *"Raw and graded card data stay decoupled"*).

**Branch strategy:** Execute this plan on a feature branch or worktree off `main`. Commits should be frequent (one per task group), messages should reference "Plan 1 / Task N".

---

## File structure

Files this plan creates or modifies, grouped by responsibility:

### Monorepo root (`/Users/dixoncider/slabbist/`)

```
supabase/
├── config.toml                             # (T1) local stack config
├── migrations/
│   ├── 20260422000001_enums.sql            # (T3) grader, store_role, lot_status, scan_status
│   ├── 20260422000002_tenants.sql          # (T4) stores, store_members
│   ├── 20260422000004_scan_surface.sql     # (T6) lots, scans (without graded_* FKs — added in Plan 2)
│   ├── 20260422000006_rls_policies.sql     # (T8) RLS on stores, store_members, lots, scans
│   └── 20260422000007_signup_bootstrap.sql # (T9) auto-create store + owner membership on new auth user
└── tests/
    └── rls_tenant_isolation.sql            # (T10) pgTAP RLS policy tests
```

**Note:** the removed `20260422000003_card_catalog.sql` and `20260422000005_comp_snapshots.sql` slots are **deliberately skipped** — the `cards`/`comp_snapshots` equivalents live in the tcgcsv repo's migration as `graded_card_identities`, `graded_cards`, `graded_market`, etc. Skipping the timestamps preserves headroom for tcgcsv's migration to land between ours if needed.

### iOS app (`/Users/dixoncider/slabbist/ios/slabbist/slabbist/`)

```
slabbistApp.swift                                    # (T12) replace default entry; wire DI + auth gate
Info.plist                                           # (T22) add NSCameraUsageDescription

Core/
├── Config/
│   └── AppEnvironment.swift                         # (T11) Supabase URL + anon key from Info.plist or xcconfig
├── Networking/
│   └── SupabaseClient.swift                         # (T13) single Supabase client + session
├── Persistence/
│   ├── ModelContainer.swift                         # (T15) SwiftData container config
│   └── Outbox/
│       ├── OutboxKind.swift                         # (T16) enum of job types
│       └── OutboxItem.swift                         # (T16) @Model row
├── Sync/
│   └── Reachability.swift                           # (T17) NWPathMonitor wrapper
├── Models/
│   ├── Store.swift                                  # (T14) @Model mirror of stores
│   ├── StoreMember.swift                            # (T14) @Model mirror of store_members
│   ├── Lot.swift                                    # (T14) @Model mirror of lots
│   └── Scan.swift                                   # (T14) @Model mirror of scans
                                                     # GradedCardIdentity / GradedCard / GradedMarketSnapshot
                                                     # arrive in Plan 2+Plan 3 once tcgcsv tables exist
├── DesignSystem/
│   └── Tokens.swift                                 # (T18) color + spacing + typography constants
└── Utilities/
    ├── Currency.swift                               # (T19) cents → display string
    └── Logger.swift                                 # (T20) OSLog subsystem wrapper

Features/
├── Auth/
│   ├── SessionStore.swift                           # (T21) @Observable auth state wrapper
│   ├── AuthViewModel.swift                          # (T21) sign-in / sign-up actions
│   └── AuthView.swift                               # (T21) email/password form
├── Lots/
│   ├── LotsViewModel.swift                          # (T23) list + create
│   ├── LotsListView.swift                           # (T23) home tab
│   └── NewLotSheet.swift                            # (T23) create-lot sheet
└── Scanning/
    ├── Camera/
    │   ├── CameraSession.swift                      # (T24) AVCaptureSession wrapper
    │   └── CertOCRRecognizer.swift                  # (T25) Vision + per-grader regex + stability gate
    └── BulkScan/
        ├── BulkScanViewModel.swift                  # (T27) orchestrates capture → local insert → outbox
        ├── BulkScanView.swift                       # (T27) camera + queue UI
        └── ScanQueueView.swift                      # (T27) horizontal strip of recent scans
```

### Tests (`/Users/dixoncider/slabbist/ios/slabbist/slabbistTests/`)

```
Core/
├── CurrencyTests.swift                              # (T19)
├── OutboxItemTests.swift                            # (T16)
└── ReachabilityTests.swift                          # (T17)
Features/
├── LotsViewModelTests.swift                         # (T23)
├── CertOCRRecognizerTests.swift                     # (T26)
└── BulkScanViewModelTests.swift                     # (T27)
```

### Deleted

- `ios/slabbist/slabbist/ContentView.swift` (T12) — default template
- `ios/slabbist/slabbist/Item.swift` (T12) — default template model
- `ios/slabbist/slabbistTests/slabbistTests.swift` (T12) — default stub
- `ios/slabbist/slabbistUITests/slabbistUITestsLaunchTests.swift` (T12) — regenerated later in Plan 4

---

## Task 1: Initialize the Supabase local stack

**Files:** Create `supabase/config.toml` (generated by CLI).

- [ ] **Step 1: Initialize the Supabase project in the monorepo root**

Run from `/Users/dixoncider/slabbist/`:

```bash
supabase init
```

Expected output:
```
Generate VS Code settings for Deno? [y/N] N
Finished supabase init.
```

This creates `supabase/` with `config.toml`, `seed.sql`, and related scaffolding.

- [ ] **Step 2: Start the local stack to verify Docker + config**

```bash
supabase start
```

Expected output includes:
```
API URL: http://127.0.0.1:54321
DB URL: postgresql://postgres:postgres@127.0.0.1:54322/postgres
Studio URL: http://127.0.0.1:54323
anon key: eyJhbGciOiJIUzI1NiIs...
```

Copy the `anon key` and `API URL` — they're used in Task 11.

- [ ] **Step 3: Commit the Supabase scaffolding**

```bash
cd /Users/dixoncider/slabbist
git add supabase/config.toml supabase/seed.sql
git commit -m "Plan 1 / T1: initialize Supabase local stack config"
```

---

## Task 2: Configure repository .gitignore for Supabase

**Files:** Modify `/Users/dixoncider/slabbist/.gitignore` (create if missing).

- [ ] **Step 1: Append Supabase-generated paths to .gitignore**

Append these lines to `/Users/dixoncider/slabbist/.gitignore` (create the file if it doesn't exist):

```
# Supabase
supabase/.branches
supabase/.temp
supabase/.env
```

- [ ] **Step 2: Commit**

```bash
cd /Users/dixoncider/slabbist
git add .gitignore
git commit -m "Plan 1 / T2: ignore Supabase-generated dirs"
```

---

## Task 3: Migration — create enums

**Files:** Create `supabase/migrations/20260422000001_enums.sql`.

- [ ] **Step 1: Write the migration file**

`supabase/migrations/20260422000001_enums.sql`:

```sql
-- Enums used across tenant, scan, and lot tables.
create type store_role as enum ('owner', 'manager', 'associate');
create type lot_status as enum ('open', 'closed', 'converted');
create type grader as enum ('PSA', 'BGS', 'CGC', 'SGC', 'TAG');
create type scan_status as enum ('pending_validation', 'validated', 'validation_failed', 'manual_entry');
```

- [ ] **Step 2: Apply the migration against the local DB**

```bash
cd /Users/dixoncider/slabbist
supabase db reset
```

Expected: the reset runs all migrations, ending with `Finished supabase db reset`.

- [ ] **Step 3: Verify the enums exist**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\dT+"
```

Expected: four rows listing `store_role`, `lot_status`, `grader`, `scan_status`.

- [ ] **Step 4: Commit**

```bash
cd /Users/dixoncider/slabbist
git add supabase/migrations/20260422000001_enums.sql
git commit -m "Plan 1 / T3: add enums (store_role, lot_status, grader, scan_status)"
```

---

## Task 4: Migration — stores & store_members

**Files:** Create `supabase/migrations/20260422000002_tenants.sql`.

- [ ] **Step 1: Write the migration file**

`supabase/migrations/20260422000002_tenants.sql`:

```sql
create table stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table store_members (
  store_id uuid not null references stores(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role store_role not null,
  created_at timestamptz not null default now(),
  primary key (store_id, user_id)
);

create index store_members_user_id on store_members(user_id);
```

- [ ] **Step 2: Apply and verify**

```bash
cd /Users/dixoncider/slabbist
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\d stores" -c "\d store_members"
```

Expected: both tables printed with their columns, primary keys, and the `store_members_user_id` index.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add supabase/migrations/20260422000002_tenants.sql
git commit -m "Plan 1 / T4: add stores + store_members tables"
```

---

## Task 5: [REMOVED]

Previously: "Migration — cards catalog." **This task is owned by the tcgcsv sub-project** and lands as part of its `graded_card_identities` + `graded_cards` + companion tables migration. See `tcgcsv/docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md`.

Skip this task. Do not create a `cards` table in this sub-project's migrations.

---

## Task 6: Migration — lots & scans

**Files:** Create `supabase/migrations/20260422000004_scan_surface.sql`.

- [ ] **Step 1: Write the migration file**

`supabase/migrations/20260422000004_scan_surface.sql`:

```sql
create table lots (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references stores(id),
  created_by_user_id uuid not null references auth.users(id),
  name text not null,
  notes text,
  status lot_status not null default 'open',
  vendor_name text,
  vendor_contact text,
  offered_total_cents bigint,
  margin_rule_id uuid,
  transaction_stamp jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index lots_store_id on lots(store_id);
create index lots_store_status on lots(store_id, status);

create table scans (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references stores(id),
  lot_id uuid not null references lots(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  grader grader not null,
  cert_number text not null,
  grade text,
  -- graded_card_identity_id and graded_card_id FKs added by Plan 2
  -- after the tcgcsv graded-table migration has landed.
  status scan_status not null default 'pending_validation',
  ocr_raw_text text,
  ocr_confidence real,
  captured_photo_url text,
  offer_cents bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index scans_lot_id on scans(lot_id);
create index scans_store_status on scans(store_id, status);
create unique index scans_cert_per_lot on scans(lot_id, grader, cert_number);
```

- [ ] **Step 2: Apply and verify**

```bash
cd /Users/dixoncider/slabbist
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\d lots" -c "\d scans"
```

Expected: `lots` and `scans` with all columns and three indexes on `scans` including the unique composite `scans_cert_per_lot`.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add supabase/migrations/20260422000004_scan_surface.sql
git commit -m "Plan 1 / T6: add lots + scans tables"
```

---

## Task 7: [REMOVED]

Previously: "Migration — comp_snapshots (schema only)." **This concept is replaced by tcgcsv's `graded_market` + `graded_market_sales` tables.** See `tcgcsv/docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md`.

Plan 3 (comp engine + UI) will add the iOS-side `GradedMarketSnapshot` SwiftData model that caches `/price-comp` responses locally. Plan 1 does not create any comp-related schema.

---

## Task 8: Migration — RLS policies

**Files:** Create `supabase/migrations/20260422000006_rls_policies.sql`.

- [ ] **Step 1: Write the migration file**

`supabase/migrations/20260422000006_rls_policies.sql`:

```sql
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
```

- [ ] **Step 2: Apply and verify RLS is enabled**

```bash
cd /Users/dixoncider/slabbist
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "
select tablename, rowsecurity
from pg_tables
where schemaname = 'public' and tablename in ('stores','store_members','lots','scans')
order by tablename;
"
```

Expected: all four tables with `rowsecurity = t`.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add supabase/migrations/20260422000006_rls_policies.sql
git commit -m "Plan 1 / T8: enable RLS + tenant-isolation policies"
```

---

## Task 9: Migration — auto-create store on signup

**Files:** Create `supabase/migrations/20260422000007_signup_bootstrap.sql`.

- [ ] **Step 1: Write the migration file**

`supabase/migrations/20260422000007_signup_bootstrap.sql`:

```sql
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
```

- [ ] **Step 2: Apply and verify the trigger exists**

```bash
cd /Users/dixoncider/slabbist
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "
select tgname, tgrelid::regclass
from pg_trigger
where tgname = 'on_auth_user_created';
"
```

Expected: one row showing `on_auth_user_created | auth.users`.

- [ ] **Step 3: Smoke-test the trigger by creating an auth user via the CLI**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres <<'SQL'
-- Simulate a signup by inserting directly (only works because we're postgres-user here).
insert into auth.users (id, email, raw_user_meta_data, aud, role)
values (gen_random_uuid(), 'trigger-test@example.com', '{"store_name":"Trigger Test Shop"}'::jsonb, 'authenticated', 'authenticated');

select s.name, sm.role
from store_members sm
join stores s on s.id = sm.store_id
where s.owner_user_id = (select id from auth.users where email = 'trigger-test@example.com');
SQL
```

Expected: one row, `name = 'Trigger Test Shop'`, `role = 'owner'`.

- [ ] **Step 4: Clean up the smoke-test user and commit**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "delete from auth.users where email = 'trigger-test@example.com';"
cd /Users/dixoncider/slabbist
git add supabase/migrations/20260422000007_signup_bootstrap.sql
git commit -m "Plan 1 / T9: auto-create store + owner membership on signup"
```

---

## Task 10: RLS policy tests (pgTAP)

**Files:** Create `supabase/tests/rls_tenant_isolation.sql`.

- [ ] **Step 1: Enable pgTAP in the test database**

Append to `supabase/migrations/20260422000006_rls_policies.sql` is wrong — pgTAP lives in a separate test path. Instead, create `supabase/tests/rls_tenant_isolation.sql`:

```sql
begin;
select plan(5);

-- pgTAP is installed into the test database by `supabase test db`.
create extension if not exists pgtap;

-- Create two users and impersonate them via the JWT-claims setter used by Supabase RLS.
insert into auth.users (id, email, aud, role)
values
  ('00000000-0000-0000-0000-000000000001', 'a@test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000000002', 'b@test', 'authenticated', 'authenticated');

-- Triggers created their stores and owner memberships.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

-- As user A, count visible stores = 1
select is((select count(*)::int from stores), 1, 'user A sees exactly their own store');

-- Switch to user B
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);

-- As user B, count visible stores = 1 (different one)
select is((select count(*)::int from stores), 1, 'user B sees exactly their own store');

-- User B inserting a lot into user A's store should fail.
select throws_ok($$
  insert into lots (store_id, created_by_user_id, name)
  select id, '00000000-0000-0000-0000-000000000002', 'Should not work'
  from stores
  where owner_user_id = '00000000-0000-0000-0000-000000000001';
$$, NULL, 'user B cannot insert a lot in user A''s store');

-- Positive: user B can insert a lot in their own store.
select lives_ok($$
  insert into lots (store_id, created_by_user_id, name)
  select id, '00000000-0000-0000-0000-000000000002', 'B lot'
  from stores
  where owner_user_id = '00000000-0000-0000-0000-000000000002';
$$, 'user B can insert a lot in their own store');

-- User A should not see user B's lot.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is((select count(*)::int from lots where name = 'B lot'), 0, 'user A cannot see user B''s lot');

select * from finish();
rollback;
```

**Graded-table RLS tests live with the tcgcsv sub-project** — this plan does not test policies on tables it does not own.

- [ ] **Step 2: Run the RLS test suite**

```bash
cd /Users/dixoncider/slabbist
supabase test db
```

Expected: `5/5 tests passed`. If any fail, inspect the message and fix the corresponding policy in `20260422000006_rls_policies.sql`.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add supabase/tests/rls_tenant_isolation.sql
git commit -m "Plan 1 / T10: pgTAP tests for tenant isolation + catalog read access"
```

---

## Task 11: Add AppEnvironment and inject Supabase credentials

**Files:** Create `ios/slabbist/slabbist/Core/Config/AppEnvironment.swift` and an xcconfig file.

- [ ] **Step 1: Create the xcconfig holding local Supabase config**

Create `ios/slabbist/slabbist/Supabase.local.xcconfig`:

```
// Local Supabase configuration. Copy `Supabase.local.xcconfig` to
// `Supabase.xcconfig` and adjust for each environment.
SUPABASE_URL = http:/$()/127.0.0.1:54321
SUPABASE_ANON_KEY = REPLACE_WITH_ANON_KEY_FROM_SUPABASE_START_OUTPUT
```

The `/$()/` is Xcode's required escaping of `//` inside an xcconfig value.

- [ ] **Step 2: Replace `REPLACE_WITH_ANON_KEY...` with the real key from Task 1, Step 2**

Open the xcconfig, paste the `anon key` value from the `supabase start` output on a single line.

- [ ] **Step 3: Add xcconfig to the Xcode project**

In Xcode (open `slabbist.xcodeproj`):
1. Select the `slabbist` project in the navigator → **Info** tab → **Configurations** section.
2. For both Debug and Release, under `slabbist` (the app target), set **Based on Configuration File** to `Supabase.local.xcconfig`.
3. In the project navigator, right-click `slabbist` group → **Add Files to "slabbist"…** → select `Supabase.local.xcconfig` → ensure target membership is the app target.

- [ ] **Step 4: Expose the values in Info.plist**

Open `slabbist/Info.plist` (or the project's "Info" configuration). Add two keys:

```xml
<key>SUPABASE_URL</key>
<string>$(SUPABASE_URL)</string>
<key>SUPABASE_ANON_KEY</key>
<string>$(SUPABASE_ANON_KEY)</string>
```

If the project uses Xcode's new target "Info" config (no Info.plist file), add these under **Target → Info → Custom iOS Target Properties**.

- [ ] **Step 5: Create `AppEnvironment.swift`**

`ios/slabbist/slabbist/Core/Config/AppEnvironment.swift`:

```swift
import Foundation

enum AppEnvironment {
    static let supabaseURL: URL = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: raw) else {
            fatalError("SUPABASE_URL missing or invalid in Info.plist. Did you set Supabase.local.xcconfig?")
        }
        return url
    }()

    static let supabaseAnonKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty else {
            fatalError("SUPABASE_ANON_KEY missing in Info.plist. Did you set Supabase.local.xcconfig?")
        }
        return key
    }()
}
```

- [ ] **Step 6: Gitignore the local xcconfig and add a template**

Add to `/Users/dixoncider/slabbist/.gitignore`:

```
ios/slabbist/slabbist/Supabase.local.xcconfig
```

Create `ios/slabbist/slabbist/Supabase.local.xcconfig.example` with the same content as the real file but with the anon key replaced by `REPLACE_ME`:

```
SUPABASE_URL = http:/$()/127.0.0.1:54321
SUPABASE_ANON_KEY = REPLACE_ME
```

- [ ] **Step 7: Build to verify**

Build the app target (⌘B in Xcode, or `xcodebuild -scheme slabbist -destination "generic/platform=iOS" build` from CLI). Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
cd /Users/dixoncider/slabbist
git add .gitignore \
  ios/slabbist/slabbist/Core/Config/AppEnvironment.swift \
  ios/slabbist/slabbist/Supabase.local.xcconfig.example \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T11: wire Supabase URL + anon key through xcconfig + AppEnvironment"
```

---

## Task 12: Strip the default SwiftUI template

**Files:** Delete default scaffolding; create minimal `slabbistApp.swift`.

- [ ] **Step 1: Delete the template files**

```bash
cd /Users/dixoncider/slabbist/ios/slabbist
rm slabbist/ContentView.swift
rm slabbist/Item.swift
rm slabbistTests/slabbistTests.swift
rm slabbistUITests/slabbistUITestsLaunchTests.swift
```

- [ ] **Step 2: Rewrite `slabbistApp.swift` to a minimal app entry**

`ios/slabbist/slabbist/slabbistApp.swift`:

```swift
import SwiftUI

@main
struct SlabbistApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Slabbist — bootstrapping…")
                .padding()
        }
    }
}
```

(Real DI + auth gate go in Task 21 once auth exists.)

- [ ] **Step 3: Remove stale references from the Xcode project**

Open `slabbist.xcodeproj` in Xcode. In the navigator, the deleted files will appear as red "missing" entries — right-click each and choose **Delete → Remove Reference**. Keep the deletions for:
- `ContentView.swift`
- `Item.swift`
- `slabbistTests.swift`
- `slabbistUITestsLaunchTests.swift`

- [ ] **Step 4: Build to verify**

Build the app (⌘B in Xcode). Expected: clean build, no errors. The app launches on simulator but shows the placeholder text.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add -A ios/slabbist
git commit -m "Plan 1 / T12: strip default template, replace with minimal app entry"
```

---

## Task 13: Add Supabase Swift SDK and create SupabaseClient wrapper

**Files:** Modify `slabbist.xcodeproj/project.pbxproj` (SPM); create `Core/Networking/SupabaseClient.swift`.

- [ ] **Step 1: Add Supabase SPM package**

In Xcode:
1. **File → Add Package Dependencies…**
2. Enter `https://github.com/supabase/supabase-swift`
3. Dependency rule: **Up to Next Major Version**, starting from the latest stable.
4. Add these products to the `slabbist` app target: **Supabase**.
5. Wait for package resolution. `Package.resolved` gets written automatically.

- [ ] **Step 2: Create `SupabaseClient.swift`**

`ios/slabbist/slabbist/Core/Networking/SupabaseClient.swift`:

```swift
import Foundation
import Supabase

/// A single process-wide Supabase client. Holds the auth session and exposes
/// the Postgrest + Auth surfaces we need app-wide.
final class AppSupabase {
    static let shared = AppSupabase()

    let client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: AppEnvironment.supabaseURL,
            supabaseKey: AppEnvironment.supabaseAnonKey
        )
    }
}
```

- [ ] **Step 3: Verify it compiles**

Build (⌘B). Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist.xcodeproj/project.pbxproj \
  ios/slabbist/slabbist.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved \
  ios/slabbist/slabbist/Core/Networking/SupabaseClient.swift
git commit -m "Plan 1 / T13: add Supabase Swift SDK + AppSupabase singleton"
```

---

## Task 14: SwiftData models mirroring Postgres

**Files:** Create six `@Model` files under `Core/Models/`.

- [ ] **Step 1: Create `Store.swift`**

`ios/slabbist/slabbist/Core/Models/Store.swift`:

```swift
import Foundation
import SwiftData

@Model
final class Store {
    @Attribute(.unique) var id: UUID
    var name: String
    var ownerUserId: UUID
    var createdAt: Date

    init(id: UUID, name: String, ownerUserId: UUID, createdAt: Date) {
        self.id = id
        self.name = name
        self.ownerUserId = ownerUserId
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 2: Create `StoreMember.swift`**

`ios/slabbist/slabbist/Core/Models/StoreMember.swift`:

```swift
import Foundation
import SwiftData

enum StoreRole: String, Codable, CaseIterable {
    case owner, manager, associate
}

@Model
final class StoreMember {
    var storeId: UUID
    var userId: UUID
    var role: StoreRole
    var createdAt: Date

    init(storeId: UUID, userId: UUID, role: StoreRole, createdAt: Date) {
        self.storeId = storeId
        self.userId = userId
        self.role = role
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 3: [SKIP — Card.swift removed from Plan 1]**

The `Card` SwiftData model used to live here. It's superseded by `GradedCardIdentity` + `GradedCard` + `GradedMarketSnapshot` (mirrors of tcgcsv-owned tables), which arrive in Plan 2 (cert validation) and Plan 3 (comp engine). Do not create `Card.swift` in Plan 1. Continue to Step 4.

- [ ] **Step 4: Create `Lot.swift`**

`ios/slabbist/slabbist/Core/Models/Lot.swift`:

```swift
import Foundation
import SwiftData

enum LotStatus: String, Codable, CaseIterable {
    case open, closed, converted
}

@Model
final class Lot {
    @Attribute(.unique) var id: UUID
    var storeId: UUID
    var createdByUserId: UUID
    var name: String
    var notes: String?
    var status: LotStatus
    var vendorName: String?
    var vendorContact: String?
    var offeredTotalCents: Int64?
    var marginRuleId: UUID?
    var transactionStamp: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        storeId: UUID,
        createdByUserId: UUID,
        name: String,
        notes: String? = nil,
        status: LotStatus = .open,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.storeId = storeId
        self.createdByUserId = createdByUserId
        self.name = name
        self.notes = notes
        self.status = status
        self.vendorName = nil
        self.vendorContact = nil
        self.offeredTotalCents = nil
        self.marginRuleId = nil
        self.transactionStamp = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 5: Create `Scan.swift`**

`ios/slabbist/slabbist/Core/Models/Scan.swift`:

```swift
import Foundation
import SwiftData

enum Grader: String, Codable, CaseIterable {
    case PSA, BGS, CGC, SGC, TAG
}

enum ScanStatus: String, Codable, CaseIterable {
    case pendingValidation = "pending_validation"
    case validated
    case validationFailed = "validation_failed"
    case manualEntry = "manual_entry"
}

@Model
final class Scan {
    @Attribute(.unique) var id: UUID
    var storeId: UUID
    var lotId: UUID
    var userId: UUID
    var grader: Grader
    var certNumber: String
    var grade: String?
    var cardId: UUID?
    var status: ScanStatus
    var ocrRawText: String?
    var ocrConfidence: Double?
    var capturedPhotoURL: String?
    var offerCents: Int64?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        storeId: UUID,
        lotId: UUID,
        userId: UUID,
        grader: Grader,
        certNumber: String,
        status: ScanStatus = .pendingValidation,
        ocrRawText: String? = nil,
        ocrConfidence: Double? = nil,
        capturedPhotoURL: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.storeId = storeId
        self.lotId = lotId
        self.userId = userId
        self.grader = grader
        self.certNumber = certNumber
        self.grade = nil
        self.cardId = nil
        self.status = status
        self.ocrRawText = ocrRawText
        self.ocrConfidence = ocrConfidence
        self.capturedPhotoURL = capturedPhotoURL
        self.offerCents = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 6: [SKIP — CompSnapshot.swift removed from Plan 1]**

The `CompSnapshot` SwiftData model used to live here. It's replaced by `GradedMarketSnapshot`, which mirrors the `/price-comp` response shape and arrives in Plan 3 (comp engine). Do not create `CompSnapshot.swift` in Plan 1. Continue to Step 7.

- [ ] **Step 7: Build to verify**

⌘B. Expected: succeeds.

- [ ] **Step 8: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/Models/ \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T14: SwiftData @Model mirrors (tenant tables only; graded mirrors arrive in Plan 2/3)"
```

---

## Task 15: ModelContainer wiring

**Files:** Create `Core/Persistence/ModelContainer.swift`.

- [ ] **Step 1: Create `ModelContainer.swift`**

`ios/slabbist/slabbist/Core/Persistence/ModelContainer.swift`:

```swift
import Foundation
import SwiftData

enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            Store.self,
            StoreMember.self,
            Lot.self,
            Scan.self,
            OutboxItem.self
            // Plan 2 adds: GradedCardIdentity, GradedCard
            // Plan 3 adds: GradedMarketSnapshot
        ])
        let config = ModelConfiguration("slabbist", schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    /// In-memory container for tests and previews.
    static func inMemory() -> ModelContainer {
        let schema = Schema([
            Store.self, StoreMember.self, Lot.self,
            Scan.self, OutboxItem.self
        ])
        let config = ModelConfiguration("slabbist-tests", schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
```

- [ ] **Step 2: Wire the container into the app root (temporary stub — Task 21 replaces this)**

Update `slabbistApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct SlabbistApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Slabbist — bootstrapping…")
                .padding()
        }
        .modelContainer(AppModelContainer.shared)
    }
}
```

- [ ] **Step 3: Build (the container depends on `OutboxItem` which Task 16 creates — DEFER this step until after Task 16.)**

Build will not succeed until Task 16 defines `OutboxItem`. Skip to Task 16 without committing the `slabbistApp.swift` or `ModelContainer.swift` changes yet — they're staged but uncommitted until the build passes.

---

## Task 16: OutboxItem + OutboxKind

**Files:** Create `Core/Persistence/Outbox/OutboxKind.swift`, `Core/Persistence/Outbox/OutboxItem.swift`, and `slabbistTests/Core/OutboxItemTests.swift`.

- [ ] **Step 1: Write the failing test first**

`ios/slabbist/slabbistTests/Core/OutboxItemTests.swift`:

```swift
import Foundation
import Testing
import SwiftData
@testable import slabbist

@Suite("OutboxItem")
struct OutboxItemTests {
    @Test("round-trips kind, payload, and status through SwiftData")
    func roundTrip() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let payload = try JSONEncoder().encode(["scanId": "abc"])
        let item = OutboxItem(
            id: UUID(),
            kind: .insertScan,
            payload: payload,
            status: .pending,
            attempts: 0,
            createdAt: Date(),
            nextAttemptAt: Date()
        )

        context.insert(item)
        try context.save()

        let fetch = FetchDescriptor<OutboxItem>()
        let loaded = try context.fetch(fetch)

        #expect(loaded.count == 1)
        #expect(loaded[0].kind == .insertScan)
        #expect(loaded[0].status == .pending)
        #expect(loaded[0].payload == payload)
    }

    @Test("priority ordering favors validation jobs")
    func priorityOrdering() {
        #expect(OutboxKind.certLookupJob.priority > OutboxKind.priceCompJob.priority)
        #expect(OutboxKind.priceCompJob.priority > OutboxKind.insertScan.priority)
        #expect(OutboxKind.insertScan.priority > OutboxKind.updateScan.priority)
    }
}
```

- [ ] **Step 2: Run the tests — they must FAIL to compile**

Run: `xcodebuild -scheme slabbist -destination "platform=iOS Simulator,name=iPhone 15" test -only-testing:slabbistTests/OutboxItemTests 2>&1 | tail -20`

Expected: build failure because `OutboxItem` and `OutboxKind` don't exist.

- [ ] **Step 3: Create `OutboxKind.swift`**

`ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxKind.swift`:

```swift
import Foundation

enum OutboxKind: String, Codable, CaseIterable {
    case insertScan
    case updateScan
    case insertLot
    case updateLot
    case certLookupJob
    case priceCompJob

    /// Higher priority = dispatched first. See design spec: validation
    /// unblocks comp; writes happen in natural order behind them.
    var priority: Int {
        switch self {
        case .certLookupJob:  return 40
        case .priceCompJob:   return 30
        case .insertScan:     return 20
        case .insertLot:      return 15
        case .updateScan:     return 10
        case .updateLot:      return 5
        }
    }
}

enum OutboxStatus: String, Codable, CaseIterable {
    case pending, inFlight, completed, failed
}
```

- [ ] **Step 4: Create `OutboxItem.swift`**

`ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxItem.swift`:

```swift
import Foundation
import SwiftData

@Model
final class OutboxItem {
    @Attribute(.unique) var id: UUID
    var kind: OutboxKind
    var payload: Data
    var status: OutboxStatus
    var attempts: Int
    var lastError: String?
    var createdAt: Date
    var nextAttemptAt: Date

    init(
        id: UUID,
        kind: OutboxKind,
        payload: Data,
        status: OutboxStatus = .pending,
        attempts: Int = 0,
        lastError: String? = nil,
        createdAt: Date,
        nextAttemptAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.status = status
        self.attempts = attempts
        self.lastError = lastError
        self.createdAt = createdAt
        self.nextAttemptAt = nextAttemptAt
    }
}
```

- [ ] **Step 5: Run the tests — they must PASS**

Run: `xcodebuild -scheme slabbist -destination "platform=iOS Simulator,name=iPhone 15" test -only-testing:slabbistTests/OutboxItemTests 2>&1 | tail -20`

Expected: `Test Suite 'OutboxItemTests' passed.`

- [ ] **Step 6: Commit (now includes the Task 15 stash)**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/Persistence/ \
  ios/slabbist/slabbist/slabbistApp.swift \
  ios/slabbist/slabbistTests/Core/OutboxItemTests.swift \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T15+16: ModelContainer + OutboxItem/Kind + test round-trip"
```

---

## Task 17: Reachability wrapper

**Files:** Create `Core/Sync/Reachability.swift` and `slabbistTests/Core/ReachabilityTests.swift`.

- [ ] **Step 1: Write the failing test**

`ios/slabbist/slabbistTests/Core/ReachabilityTests.swift`:

```swift
import Foundation
import Testing
@testable import slabbist

@Suite("Reachability")
struct ReachabilityTests {
    @Test("default status is .unknown before first path callback")
    func defaultStatusIsUnknown() {
        let r = Reachability()
        #expect(r.status == .unknown)
    }

    @Test("applying a path updates status to the mapped value")
    func appliesPathStatus() {
        let r = Reachability()
        r.applyForTesting(status: .online)
        #expect(r.status == .online)

        r.applyForTesting(status: .offline)
        #expect(r.status == .offline)
    }
}
```

- [ ] **Step 2: Run and observe compile failure**

Run the test target. Expected: fails to compile (`Reachability` not found).

- [ ] **Step 3: Create `Reachability.swift`**

`ios/slabbist/slabbist/Core/Sync/Reachability.swift`:

```swift
import Foundation
import Network
import Observation

enum ReachabilityStatus: Equatable {
    case unknown
    case online
    case offline
}

@Observable
final class Reachability {
    private(set) var status: ReachabilityStatus = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.slabbist.reachability")

    init(start: Bool = false) {
        if start { self.start() }
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.apply(path: path)
        }
        monitor.start(queue: queue)
    }

    /// Test seam — feeds a status directly without spinning up NWPathMonitor.
    func applyForTesting(status: ReachabilityStatus) {
        DispatchQueue.main.async {
            self.status = status
        }
        // For immediate test observation, also write synchronously:
        self.status = status
    }

    private func apply(path: NWPath) {
        let next: ReachabilityStatus = (path.status == .satisfied) ? .online : .offline
        DispatchQueue.main.async {
            self.status = next
        }
    }
}
```

- [ ] **Step 4: Run the tests — they must PASS**

Run: `xcodebuild -scheme slabbist -destination "platform=iOS Simulator,name=iPhone 15" test -only-testing:slabbistTests/ReachabilityTests 2>&1 | tail -20`

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/Sync/Reachability.swift \
  ios/slabbist/slabbistTests/Core/ReachabilityTests.swift \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T17: Reachability wrapper + tests"
```

---

## Task 18: Design system tokens

**Files:** Create `Core/DesignSystem/Tokens.swift`.

- [ ] **Step 1: Create `Tokens.swift`**

`ios/slabbist/slabbist/Core/DesignSystem/Tokens.swift`:

```swift
import SwiftUI

enum Spacing {
    static let xs: CGFloat = 4
    static let s:  CGFloat = 8
    static let m:  CGFloat = 16
    static let l:  CGFloat = 24
    static let xl: CGFloat = 32
}

enum Radius {
    static let s: CGFloat = 6
    static let m: CGFloat = 12
    static let l: CGFloat = 20
}

enum AppColor {
    static let surface    = Color(.systemBackground)
    static let surfaceAlt = Color(.secondarySystemBackground)
    static let accent     = Color.accentColor
    static let success    = Color.green
    static let warning    = Color.orange
    static let danger     = Color.red
}
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/DesignSystem/Tokens.swift \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T18: design system tokens (spacing, radius, colors)"
```

---

## Task 19: Currency formatting helper

**Files:** Create `Core/Utilities/Currency.swift` and `slabbistTests/Core/CurrencyTests.swift`.

- [ ] **Step 1: Write the failing test first**

`ios/slabbist/slabbistTests/Core/CurrencyTests.swift`:

```swift
import Testing
@testable import slabbist

@Suite("Currency")
struct CurrencyTests {
    @Test("formats USD cents as dollar amount")
    func formatsUSD() {
        #expect(Currency.displayUSD(cents: 12_050) == "$120.50")
        #expect(Currency.displayUSD(cents: 0) == "$0.00")
        #expect(Currency.displayUSD(cents: 31_000_00) == "$31,000.00")
    }

    @Test("handles nil with em-dash placeholder")
    func formatsNil() {
        #expect(Currency.displayUSD(cents: nil) == "—")
    }
}
```

- [ ] **Step 2: Run — fails to compile**

Expected: `Currency` is not defined.

- [ ] **Step 3: Create `Currency.swift`**

`ios/slabbist/slabbist/Core/Utilities/Currency.swift`:

```swift
import Foundation

enum Currency {
    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    static func displayUSD(cents: Int64?) -> String {
        guard let cents else { return "—" }
        let dollars = Decimal(cents) / 10
        let divided = Decimal(cents) / Decimal(100)
        return usdFormatter.string(from: divided as NSDecimalNumber) ?? "—"
        // (The `dollars` line above is a vestigial no-op guard; remove in T19.4 cleanup.)
    }
}
```

- [ ] **Step 4: Run — the tests pass, but fix the dead `dollars` line**

Simplify `displayUSD` to:

```swift
static func displayUSD(cents: Int64?) -> String {
    guard let cents else { return "—" }
    let divided = Decimal(cents) / Decimal(100)
    return usdFormatter.string(from: divided as NSDecimalNumber) ?? "—"
}
```

Re-run: `xcodebuild -scheme slabbist -destination "platform=iOS Simulator,name=iPhone 15" test -only-testing:slabbistTests/CurrencyTests 2>&1 | tail -15`

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/Utilities/Currency.swift \
  ios/slabbist/slabbistTests/Core/CurrencyTests.swift \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T19: Currency.displayUSD + tests"
```

---

## Task 20: Logger

**Files:** Create `Core/Utilities/Logger.swift`.

- [ ] **Step 1: Create `Logger.swift`**

`ios/slabbist/slabbist/Core/Utilities/Logger.swift`:

```swift
import Foundation
import OSLog

enum AppLog {
    static let subsystem = "com.slabbist"

    static let app       = Logger(subsystem: subsystem, category: "app")
    static let auth      = Logger(subsystem: subsystem, category: "auth")
    static let sync      = Logger(subsystem: subsystem, category: "sync")
    static let outbox    = Logger(subsystem: subsystem, category: "outbox")
    static let camera    = Logger(subsystem: subsystem, category: "camera")
    static let ocr       = Logger(subsystem: subsystem, category: "ocr")
    static let lots      = Logger(subsystem: subsystem, category: "lots")
    static let scans     = Logger(subsystem: subsystem, category: "scans")
    static let network   = Logger(subsystem: subsystem, category: "network")
}
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Core/Utilities/Logger.swift \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T20: OSLog categories scaffolded"
```

---

## Task 21: Auth — SessionStore + AuthView + wire into app entry

**Files:** Create `Features/Auth/SessionStore.swift`, `Features/Auth/AuthViewModel.swift`, `Features/Auth/AuthView.swift`; modify `slabbistApp.swift`.

- [ ] **Step 1: Create `SessionStore.swift`**

`ios/slabbist/slabbist/Features/Auth/SessionStore.swift`:

```swift
import Foundation
import Observation
import Supabase

@Observable
final class SessionStore {
    private(set) var userId: UUID?
    private(set) var isLoading = false

    private let client: SupabaseClient
    private var authTask: Task<Void, Never>?

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
    }

    func bootstrap() {
        authTask?.cancel()
        authTask = Task { [weak self] in
            guard let self else { return }
            for await change in self.client.auth.authStateChanges {
                await MainActor.run {
                    self.userId = change.session?.user.id
                }
            }
        }

        Task { [weak self] in
            guard let self else { return }
            let session = try? await self.client.auth.session
            await MainActor.run {
                self.userId = session?.user.id
            }
        }
    }

    var isSignedIn: Bool { userId != nil }
}
```

- [ ] **Step 2: Create `AuthViewModel.swift`**

`ios/slabbist/slabbist/Features/Auth/AuthViewModel.swift`:

```swift
import Foundation
import Observation
import Supabase

@Observable
final class AuthViewModel {
    enum Mode { case signIn, signUp }

    var email: String = ""
    var password: String = ""
    var storeName: String = ""
    var mode: Mode = .signIn
    var errorMessage: String?
    var isSubmitting = false

    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
    }

    @MainActor
    func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            switch mode {
            case .signIn:
                _ = try await client.auth.signIn(email: email, password: password)
            case .signUp:
                let metadata: [String: AnyJSON] = storeName.isEmpty
                    ? [:]
                    : ["store_name": .string(storeName)]
                _ = try await client.auth.signUp(
                    email: email,
                    password: password,
                    data: metadata
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            AppLog.auth.error("auth submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func toggleMode() {
        mode = (mode == .signIn) ? .signUp : .signIn
        errorMessage = nil
    }
}
```

- [ ] **Step 3: Create `AuthView.swift`**

`ios/slabbist/slabbist/Features/Auth/AuthView.swift`:

```swift
import SwiftUI

struct AuthView: View {
    @State private var viewModel = AuthViewModel()

    var body: some View {
        VStack(spacing: Spacing.l) {
            Text("Slabbist")
                .font(.largeTitle.bold())

            Picker("Mode", selection: $viewModel.mode) {
                Text("Sign In").tag(AuthViewModel.Mode.signIn)
                Text("Sign Up").tag(AuthViewModel.Mode.signUp)
            }
            .pickerStyle(.segmented)

            VStack(spacing: Spacing.m) {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)

                SecureField("Password", text: $viewModel.password)
                    .textContentType(viewModel.mode == .signIn ? .password : .newPassword)

                if viewModel.mode == .signUp {
                    TextField("Store name (optional)", text: $viewModel.storeName)
                }
            }
            .textFieldStyle(.roundedBorder)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(AppColor.danger)
            }

            Button {
                Task { await viewModel.submit() }
            } label: {
                if viewModel.isSubmitting {
                    ProgressView()
                } else {
                    Text(viewModel.mode == .signIn ? "Sign in" : "Create account")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.email.isEmpty || viewModel.password.isEmpty || viewModel.isSubmitting)
        }
        .padding(Spacing.l)
    }
}

#Preview {
    AuthView()
}
```

- [ ] **Step 4: Update `slabbistApp.swift` to gate on auth**

`ios/slabbist/slabbist/slabbistApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct SlabbistApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .onAppear { session.bootstrap() }
        }
        .modelContainer(AppModelContainer.shared)
    }
}

private struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.isSignedIn {
            // Real home screen lands in Task 23.
            Text("Signed in as \(session.userId?.uuidString ?? "unknown")")
                .padding()
        } else {
            AuthView()
        }
    }
}
```

- [ ] **Step 5: Manual smoke test — create an account**

1. Build and run on iPhone 15 simulator.
2. App opens to `AuthView`.
3. Switch to **Sign Up**, enter `me@test.local`, password `12345678`, store name `Corner Card Shop`.
4. Tap **Create account**.
5. Expected: screen transitions to the signed-in placeholder showing the user ID.
6. Verify in Supabase Studio (`http://127.0.0.1:54323`) → **Table Editor** → `stores` — a row with name "Corner Card Shop" exists.
7. In `store_members`, a row linking this user with `role = 'owner'` exists.

- [ ] **Step 6: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Auth/ \
  ios/slabbist/slabbist/slabbistApp.swift \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T21: Supabase auth + SessionStore + AuthView wired into app root"
```

---

## Task 22: Add camera usage description

**Files:** Modify `slabbist/Info.plist` (or target Info).

- [ ] **Step 1: Add `NSCameraUsageDescription`**

In Xcode → target `slabbist` → **Info** tab → **Custom iOS Target Properties** → add:

```
Privacy - Camera Usage Description = "Slabbist uses the camera to scan graded slab cert numbers."
```

If the project uses a physical `Info.plist` file, add:

```xml
<key>NSCameraUsageDescription</key>
<string>Slabbist uses the camera to scan graded slab cert numbers.</string>
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist.xcodeproj/project.pbxproj \
  ios/slabbist/slabbist/Info.plist 2>/dev/null || true
git commit -m "Plan 1 / T22: add NSCameraUsageDescription"
```

---

## Task 23: Lots — list + create + viewmodel + tests

**Files:** Create `Features/Lots/LotsViewModel.swift`, `LotsListView.swift`, `NewLotSheet.swift`; create `slabbistTests/Features/LotsViewModelTests.swift`.

- [ ] **Step 1: Write the failing test first**

`ios/slabbist/slabbistTests/Features/LotsViewModelTests.swift`:

```swift
import Foundation
import Testing
import SwiftData
@testable import slabbist

@Suite("LotsViewModel")
struct LotsViewModelTests {
    @Test("createLot inserts a Lot and outbox insertLot item in one transaction")
    func createsLotAndOutboxItem() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let vm = LotsViewModel(context: context, currentUserId: userId, currentStoreId: storeId)

        let lot = try vm.createLot(name: "Test Lot")

        #expect(lot.name == "Test Lot")
        #expect(lot.storeId == storeId)
        #expect(lot.createdByUserId == userId)
        #expect(lot.status == .open)

        let lots = try context.fetch(FetchDescriptor<Lot>())
        #expect(lots.count == 1)

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.count == 1)
        #expect(outbox[0].kind == .insertLot)
        #expect(outbox[0].status == .pending)

        let payload = try JSONDecoder().decode([String: String].self, from: outbox[0].payload)
        #expect(payload["id"] == lot.id.uuidString)
        #expect(payload["name"] == "Test Lot")
    }

    @Test("listOpenLots returns only open lots for the current store, newest first")
    func listsOpenLotsNewestFirst() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let otherStoreId = UUID()

        let older = Lot(id: UUID(), storeId: storeId, createdByUserId: userId, name: "older",
                        createdAt: Date(timeIntervalSinceNow: -1000), updatedAt: Date())
        let newer = Lot(id: UUID(), storeId: storeId, createdByUserId: userId, name: "newer",
                        createdAt: Date(), updatedAt: Date())
        let closed = Lot(id: UUID(), storeId: storeId, createdByUserId: userId, name: "closed",
                         status: .closed, createdAt: Date(), updatedAt: Date())
        let otherStore = Lot(id: UUID(), storeId: otherStoreId, createdByUserId: userId, name: "other",
                             createdAt: Date(), updatedAt: Date())

        [older, newer, closed, otherStore].forEach(context.insert)
        try context.save()

        let vm = LotsViewModel(context: context, currentUserId: userId, currentStoreId: storeId)
        let lots = try vm.listOpenLots()

        #expect(lots.map(\.name) == ["newer", "older"])
    }
}
```

- [ ] **Step 2: Run — fails to compile**

Expected: `LotsViewModel` is not defined.

- [ ] **Step 3: Create `LotsViewModel.swift`**

`ios/slabbist/slabbist/Features/Lots/LotsViewModel.swift`:

```swift
import Foundation
import SwiftData

@MainActor
@Observable
final class LotsViewModel {
    private let context: ModelContext
    let currentUserId: UUID
    let currentStoreId: UUID

    init(context: ModelContext, currentUserId: UUID, currentStoreId: UUID) {
        self.context = context
        self.currentUserId = currentUserId
        self.currentStoreId = currentStoreId
    }

    @discardableResult
    func createLot(name: String, notes: String? = nil) throws -> Lot {
        let now = Date()
        let lot = Lot(
            id: UUID(),
            storeId: currentStoreId,
            createdByUserId: currentUserId,
            name: name,
            notes: notes,
            createdAt: now,
            updatedAt: now
        )
        context.insert(lot)

        let payload: [String: String] = [
            "id": lot.id.uuidString,
            "store_id": lot.storeId.uuidString,
            "created_by_user_id": lot.createdByUserId.uuidString,
            "name": lot.name,
            "status": lot.status.rawValue,
            "created_at": ISO8601DateFormatter().string(from: lot.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: lot.updatedAt)
        ]
        let encoded = try JSONEncoder().encode(payload)

        let outboxItem = OutboxItem(
            id: UUID(),
            kind: .insertLot,
            payload: encoded,
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        )
        context.insert(outboxItem)

        try context.save()
        return lot
    }

    func listOpenLots() throws -> [Lot] {
        let storeId = currentStoreId
        var descriptor = FetchDescriptor<Lot>(
            predicate: #Predicate<Lot> { $0.storeId == storeId && $0.status == .open },
            sortBy: [SortDescriptor(\Lot.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        return try context.fetch(descriptor)
    }
}
```

- [ ] **Step 4: Run — tests pass**

Run: `xcodebuild -scheme slabbist -destination "platform=iOS Simulator,name=iPhone 15" test -only-testing:slabbistTests/LotsViewModelTests 2>&1 | tail -25`

Expected: both tests pass.

- [ ] **Step 5: Create `NewLotSheet.swift`**

`ios/slabbist/slabbist/Features/Lots/NewLotSheet.swift`:

```swift
import SwiftUI

struct NewLotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = defaultName()
    @State private var error: String?

    let onCreate: (String) throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Lot name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(AppColor.danger)
                    }
                }
            }
            .navigationTitle("New bulk scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start scanning") {
                        do {
                            try onCreate(name.trimmingCharacters(in: .whitespaces))
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private static func defaultName() -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return "Bulk – \(fmt.string(from: Date()))"
    }
}
```

- [ ] **Step 6: Create `LotsListView.swift`**

`ios/slabbist/slabbist/Features/Lots/LotsListView.swift`:

```swift
import SwiftUI
import SwiftData

struct LotsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session

    @State private var showingNewLot = false
    @State private var lots: [Lot] = []
    @State private var selectedLot: Lot?
    @State private var viewModel: LotsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if lots.isEmpty {
                    emptyState
                } else {
                    List(lots) { lot in
                        Button {
                            selectedLot = lot
                        } label: {
                            row(for: lot)
                        }
                    }
                }
            }
            .navigationTitle("Lots")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewLot = true
                    } label: {
                        Label("New bulk scan", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewLot) {
                if let viewModel {
                    NewLotSheet { name in
                        let lot = try viewModel.createLot(name: name)
                        refresh()
                        selectedLot = lot
                    }
                }
            }
            .navigationDestination(item: $selectedLot) { lot in
                // Real target: BulkScanView(lot: lot) — Task 27 wires this up.
                Text("Scan screen for \(lot.name)")
            }
            .onAppear {
                bootstrapViewModel()
                refresh()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No lots yet").font(.title3.weight(.semibold))
            Text("Start your first bulk scan to see it here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New bulk scan") { showingNewLot = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(Spacing.xl)
    }

    private func row(for lot: Lot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(lot.name).font(.headline)
            HStack {
                Text(lot.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(lot.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bootstrapViewModel() {
        guard viewModel == nil else { return }
        guard let userId = session.userId else { return }

        // Plan 1 MVP: single store per user. Fetch the first store the user owns.
        let ownerId = userId
        var descriptor = FetchDescriptor<Store>(
            predicate: #Predicate<Store> { $0.ownerUserId == ownerId }
        )
        descriptor.fetchLimit = 1

        if let store = try? context.fetch(descriptor).first {
            viewModel = LotsViewModel(context: context, currentUserId: userId, currentStoreId: store.id)
        } else {
            // Store row hasn't synced yet. For Plan 1, fall back to a placeholder;
            // Plan 2 introduces a store-fetch sync on session establishment.
            AppLog.lots.warning("no local Store for user \(userId, privacy: .public); view model deferred")
        }
    }

    private func refresh() {
        guard let viewModel else {
            lots = []
            return
        }
        do {
            lots = try viewModel.listOpenLots()
        } catch {
            AppLog.lots.error("listOpenLots failed: \(error.localizedDescription, privacy: .public)")
            lots = []
        }
    }
}
```

- [ ] **Step 7: Replace the signed-in placeholder in `slabbistApp.swift`**

Update `RootView`:

```swift
private struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.isSignedIn {
            LotsListView()
        } else {
            AuthView()
        }
    }
}
```

- [ ] **Step 8: Manual smoke test — create a lot**

1. Build and run on simulator with a signed-in session (from Task 21 — if logged out, sign back in).
2. Home shows empty state.
3. Tap **New bulk scan**, accept default name, tap **Start scanning**.
4. Expected: sheet dismisses, row appears in the list showing the new lot, and the app navigates into the placeholder "Scan screen for …" view.
5. Back out; the lot still appears in the list.
6. In Supabase Studio, verify the `lots` table is still empty (the outbox hasn't flushed yet — that's expected; Plan 2 adds the worker).
7. In the iOS simulator's file system (via `xcrun simctl get_app_container booted com.slabbist.slabbist data`), inspect the SwiftData store to confirm `OutboxItem` has `kind = .insertLot`.

- [ ] **Step 9: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Lots/ \
  ios/slabbist/slabbist/slabbistApp.swift \
  ios/slabbist/slabbistTests/Features/LotsViewModelTests.swift \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T23: Lots list + create flow + outbox enqueue + tests"
```

---

## Task 24: CameraSession wrapper

**Files:** Create `Features/Scanning/Camera/CameraSession.swift`.

- [ ] **Step 1: Create `CameraSession.swift`**

`ios/slabbist/slabbist/Features/Scanning/Camera/CameraSession.swift`:

```swift
import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class CameraSession: NSObject {
    enum Authorization: Equatable {
        case notDetermined, authorized, denied, restricted
    }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var isRunning: Bool = false

    let captureSession = AVCaptureSession()

    private let sampleQueue = DispatchQueue(label: "com.slabbist.camera.samples")
    private let videoOutput = AVCaptureVideoDataOutput()

    /// Callback fired on the sample queue. Kept minimal — actual OCR
    /// orchestration happens in Task 25's recognizer.
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    func requestAuthorization() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:     authorization = .authorized
        case .denied:         authorization = .denied
        case .restricted:     authorization = .restricted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorization = granted ? .authorized : .denied
        @unknown default:
            authorization = .denied
        }
    }

    func configure() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "CameraSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "No rear camera"])
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw NSError(domain: "CameraSession", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"])
        }
        captureSession.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        guard captureSession.canAddOutput(videoOutput) else {
            throw NSError(domain: "CameraSession", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot add video output"])
        }
        captureSession.addOutput(videoOutput)
    }

    func start() {
        guard !captureSession.isRunning else { return }
        Task.detached(priority: .userInitiated) {
            self.captureSession.startRunning()
            await MainActor.run { self.isRunning = true }
        }
    }

    func stop() {
        guard captureSession.isRunning else { return }
        Task.detached(priority: .userInitiated) {
            self.captureSession.stopRunning()
            await MainActor.run { self.isRunning = false }
        }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        Task { @MainActor in
            self.onSampleBuffer?(sampleBuffer)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: succeeds. (This file is exercised by manual smoke test in Task 27; its unit tests would require the simulator to have camera hardware, so we cover it via the OCR tests that use still-frame fixtures instead.)

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Scanning/Camera/CameraSession.swift \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T24: CameraSession AVCaptureSession wrapper"
```

---

## Task 25: CertOCRRecognizer — regex + stability gate

**Files:** Create `Features/Scanning/Camera/CertOCRRecognizer.swift` (logic), then Task 26 adds tests.

- [ ] **Step 1: Create `CertOCRRecognizer.swift`**

`ios/slabbist/slabbist/Features/Scanning/Camera/CertOCRRecognizer.swift`:

```swift
import Foundation
import Vision

/// Result of a single frame's recognition pass.
struct CertCandidate: Equatable {
    let grader: Grader
    let certNumber: String
    let confidence: Double
    let rawText: String
}

enum CertOCRConfig {
    static let stableFrameCount: Int = 3
    static let stableWindowMillis: Int = 200
    static let stableConfidenceThreshold: Double = 0.85
    static let fallbackConfidenceThreshold: Double = 0.50
}

/// Identifies a grader + cert number from text recognition candidates.
/// The stability gate (N matching reads in T ms) is applied upstream by
/// `CertOCRRecognizer.ingest`.
enum CertOCRPatterns {
    /// One pattern per grader. Each pattern captures the cert digits
    /// into group 1. Keyword proximity check runs separately.
    static let patterns: [(grader: Grader, keyword: String, regex: NSRegularExpression)] = {
        func compile(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        return [
            (.PSA, "PSA",     compile(#"\b(\d{8,9})\b"#)),
            (.BGS, "BGS",     compile(#"\b(\d{10})\b"#)),
            (.BGS, "BECKETT", compile(#"\b(\d{10})\b"#)),
            (.CGC, "CGC",     compile(#"\b(\d{10})\b"#)),
            (.SGC, "SGC",     compile(#"\b(\d{7,8})\b"#)),
            (.TAG, "TAG",     compile(#"\b([A-Z0-9]{10,12})\b"#))
        ]
    }()

    static func match(in text: String) -> CertCandidate? {
        let upper = text.uppercased()
        for (grader, keyword, regex) in patterns {
            guard upper.contains(keyword) else { continue }
            let range = NSRange(upper.startIndex..<upper.endIndex, in: upper)
            guard let match = regex.firstMatch(in: upper, options: [], range: range) else { continue }
            guard match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: upper) else { continue }
            let cert = String(upper[r])
            return CertCandidate(grader: grader, certNumber: cert, confidence: 1.0, rawText: text)
        }
        return nil
    }
}

@MainActor
final class CertOCRRecognizer {
    private struct SeenRead {
        let candidate: CertCandidate
        let at: Date
    }

    private var recent: [SeenRead] = []
    private let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    /// Feed the recognizer a single frame's text candidates (e.g. from Vision).
    /// Returns a "stable" candidate if the same `(grader, certNumber)` has
    /// appeared `stableFrameCount` times in the last `stableWindowMillis`.
    func ingest(textCandidates: [String], visionConfidence: Double) -> CertCandidate? {
        guard visionConfidence >= CertOCRConfig.fallbackConfidenceThreshold else {
            return nil
        }

        let now = clock()
        for text in textCandidates {
            guard let cand = CertOCRPatterns.match(in: text) else { continue }
            recent.append(SeenRead(candidate: cand, at: now))
        }

        let windowStart = now.addingTimeInterval(-Double(CertOCRConfig.stableWindowMillis) / 1000.0)
        recent.removeAll { $0.at < windowStart }

        let grouped = Dictionary(grouping: recent) { "\($0.candidate.grader.rawValue)|\($0.candidate.certNumber)" }
        guard let stable = grouped.first(where: { $0.value.count >= CertOCRConfig.stableFrameCount }),
              let first = stable.value.first else { return nil }

        guard visionConfidence >= CertOCRConfig.stableConfidenceThreshold else {
            return nil
        }

        // Reset so we don't keep re-firing on the same stable window.
        recent.removeAll()
        return CertCandidate(
            grader: first.candidate.grader,
            certNumber: first.candidate.certNumber,
            confidence: visionConfidence,
            rawText: first.candidate.rawText
        )
    }
}
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Scanning/Camera/CertOCRRecognizer.swift \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T25: CertOCRRecognizer + per-grader patterns + stability gate"
```

---

## Task 26: CertOCRRecognizer tests

**Files:** Create `slabbistTests/Features/CertOCRRecognizerTests.swift`.

- [ ] **Step 1: Write comprehensive pattern tests**

`ios/slabbist/slabbistTests/Features/CertOCRRecognizerTests.swift`:

```swift
import Foundation
import Testing
@testable import slabbist

@Suite("CertOCRPatterns")
struct CertOCRPatternTests {
    @Test("matches a PSA 9-digit cert near 'PSA' keyword")
    func matchesPSA() {
        let sample = "PSA MINT 9 — 12345678\nPOKEMON — CHARIZARD"
        let match = CertOCRPatterns.match(in: sample)
        #expect(match?.grader == .PSA)
        #expect(match?.certNumber == "12345678")
    }

    @Test("matches BGS 10-digit cert near 'BECKETT'")
    func matchesBGS() {
        let sample = "BECKETT GRADING SERVICE 9.5 GEM MINT 0123456789"
        let match = CertOCRPatterns.match(in: sample)
        #expect(match?.grader == .BGS)
        #expect(match?.certNumber == "0123456789")
    }

    @Test("matches CGC 10-digit cert near 'CGC'")
    func matchesCGC() {
        let sample = "CGC TRADING CARDS\n9876543210\nPERFECT 10"
        let match = CertOCRPatterns.match(in: sample)
        #expect(match?.grader == .CGC)
        #expect(match?.certNumber == "9876543210")
    }

    @Test("matches SGC 8-digit cert near 'SGC'")
    func matchesSGC() {
        let sample = "SGC 10 PRISTINE 00112233"
        let match = CertOCRPatterns.match(in: sample)
        #expect(match?.grader == .SGC)
        #expect(match?.certNumber == "00112233")
    }

    @Test("matches TAG cert near 'TAG'")
    func matchesTAG() {
        let sample = "TAG GRADING A1B2C3D4E5F6"
        let match = CertOCRPatterns.match(in: sample)
        #expect(match?.grader == .TAG)
        #expect(match?.certNumber == "A1B2C3D4E5F6")
    }

    @Test("does not match a digit sequence without a grader keyword")
    func rejectsUnlabeledDigits() {
        let sample = "POKEMON TCG BASE SET 1999 — 12345678"
        let match = CertOCRPatterns.match(in: sample)
        #expect(match == nil)
    }
}

@Suite("CertOCRRecognizer stability gate")
struct CertOCRRecognizerStabilityTests {
    @Test("does not fire on a single confident read")
    func singleReadNoFire() {
        var now = Date(timeIntervalSince1970: 1_000)
        let r = CertOCRRecognizer(clock: { now })
        let result = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)
        #expect(result == nil)

        now = now.addingTimeInterval(0.010)
        #expect(r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95) == nil)
    }

    @Test("fires on three confident reads of the same cert within window")
    func firesOnStableReads() {
        var now = Date(timeIntervalSince1970: 2_000)
        let r = CertOCRRecognizer(clock: { now })

        _ = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)
        now = now.addingTimeInterval(0.040)
        _ = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)
        now = now.addingTimeInterval(0.040)
        let result = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)

        #expect(result?.grader == .PSA)
        #expect(result?.certNumber == "12345678")
    }

    @Test("does not fire below the stable confidence threshold")
    func skipsLowConfidence() {
        var now = Date(timeIntervalSince1970: 3_000)
        let r = CertOCRRecognizer(clock: { now })
        _ = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.70)
        now = now.addingTimeInterval(0.040)
        _ = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.70)
        now = now.addingTimeInterval(0.040)
        let result = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.70)
        #expect(result == nil)
    }

    @Test("skips ingestion entirely below fallback confidence threshold")
    func skipsBelowFallback() {
        let now = Date(timeIntervalSince1970: 4_000)
        let r = CertOCRRecognizer(clock: { now })
        let result = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.30)
        #expect(result == nil)
    }

    @Test("does not fire when reads fall outside the stable window")
    func windowExpires() {
        var now = Date(timeIntervalSince1970: 5_000)
        let r = CertOCRRecognizer(clock: { now })

        _ = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)
        now = now.addingTimeInterval(0.5)   // beyond 200ms window
        _ = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)
        now = now.addingTimeInterval(0.5)
        let result = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Run the tests**

Run: `xcodebuild -scheme slabbist -destination "platform=iOS Simulator,name=iPhone 15" test -only-testing:slabbistTests/CertOCRPatternTests -only-testing:slabbistTests/CertOCRRecognizerStabilityTests 2>&1 | tail -30`

Expected: all 11 tests pass.

- [ ] **Step 3: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbistTests/Features/CertOCRRecognizerTests.swift \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T26: CertOCR pattern + stability gate tests"
```

---

## Task 27: BulkScanView + ViewModel + ScanQueueView

**Files:** Create `Features/Scanning/BulkScan/BulkScanViewModel.swift`, `BulkScanView.swift`, `ScanQueueView.swift`; create tests.

- [ ] **Step 1: Write the failing test for the view model**

`ios/slabbist/slabbistTests/Features/BulkScanViewModelTests.swift`:

```swift
import Foundation
import Testing
import SwiftData
@testable import slabbist

@Suite("BulkScanViewModel")
struct BulkScanViewModelTests {
    @Test("recordCapture inserts Scan + outbox item in the correct lot")
    func recordsCapture() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let lot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId,
                      name: "Test", createdAt: Date(), updatedAt: Date())
        context.insert(lot)
        try context.save()

        let vm = BulkScanViewModel(context: context, lot: lot, currentUserId: userId)
        let candidate = CertCandidate(grader: .PSA, certNumber: "12345678",
                                      confidence: 0.92, rawText: "PSA MINT 12345678")
        try vm.record(candidate: candidate)

        let scans = try context.fetch(FetchDescriptor<Scan>())
        #expect(scans.count == 1)
        #expect(scans[0].grader == .PSA)
        #expect(scans[0].certNumber == "12345678")
        #expect(scans[0].status == .pendingValidation)
        #expect(scans[0].lotId == lot.id)
        #expect(scans[0].storeId == storeId)
        #expect(scans[0].userId == userId)

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.count == 1)
        #expect(outbox[0].kind == .insertScan)
    }

    @Test("recordCapture is idempotent for duplicate cert in same lot (unique constraint simulation)")
    func duplicateCertInLot() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let lot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId,
                      name: "Test", createdAt: Date(), updatedAt: Date())
        context.insert(lot)
        try context.save()

        let vm = BulkScanViewModel(context: context, lot: lot, currentUserId: userId)
        let c = CertCandidate(grader: .PSA, certNumber: "12345678", confidence: 0.95, rawText: "PSA 12345678")
        try vm.record(candidate: c)
        try vm.record(candidate: c)

        let scans = try context.fetch(FetchDescriptor<Scan>())
        #expect(scans.count == 1)   // second call is a no-op locally
    }
}
```

- [ ] **Step 2: Run — fails to compile**

Expected: `BulkScanViewModel` not defined.

- [ ] **Step 3: Create `BulkScanViewModel.swift`**

`ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanViewModel.swift`:

```swift
import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class BulkScanViewModel {
    private let context: ModelContext
    let lot: Lot
    let currentUserId: UUID

    private(set) var recentScans: [Scan] = []

    init(context: ModelContext, lot: Lot, currentUserId: UUID) {
        self.context = context
        self.lot = lot
        self.currentUserId = currentUserId
        refreshRecent()
    }

    func record(candidate: CertCandidate) throws {
        if try isDuplicateLocally(grader: candidate.grader, certNumber: candidate.certNumber) {
            AppLog.scans.info("duplicate cert in lot — ignoring capture")
            return
        }

        let now = Date()
        let scan = Scan(
            id: UUID(),
            storeId: lot.storeId,
            lotId: lot.id,
            userId: currentUserId,
            grader: candidate.grader,
            certNumber: candidate.certNumber,
            status: .pendingValidation,
            ocrRawText: candidate.rawText,
            ocrConfidence: candidate.confidence,
            createdAt: now,
            updatedAt: now
        )
        context.insert(scan)

        let payload: [String: String] = [
            "id": scan.id.uuidString,
            "store_id": scan.storeId.uuidString,
            "lot_id": scan.lotId.uuidString,
            "user_id": scan.userId.uuidString,
            "grader": scan.grader.rawValue,
            "cert_number": scan.certNumber,
            "status": scan.status.rawValue,
            "ocr_raw_text": scan.ocrRawText ?? "",
            "ocr_confidence": String(scan.ocrConfidence ?? 0),
            "created_at": ISO8601DateFormatter().string(from: scan.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: scan.updatedAt)
        ]
        let encoded = try JSONEncoder().encode(payload)

        let outboxItem = OutboxItem(
            id: UUID(),
            kind: .insertScan,
            payload: encoded,
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        )
        context.insert(outboxItem)

        try context.save()
        refreshRecent()
    }

    private func isDuplicateLocally(grader: Grader, certNumber: String) throws -> Bool {
        let lotId = lot.id
        var descriptor = FetchDescriptor<Scan>(
            predicate: #Predicate<Scan> {
                $0.lotId == lotId && $0.grader == grader && $0.certNumber == certNumber
            }
        )
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    private func refreshRecent() {
        let lotId = lot.id
        var descriptor = FetchDescriptor<Scan>(
            predicate: #Predicate<Scan> { $0.lotId == lotId },
            sortBy: [SortDescriptor(\Scan.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        recentScans = (try? context.fetch(descriptor)) ?? []
    }
}
```

- [ ] **Step 4: Run — tests pass**

Run: `xcodebuild -scheme slabbist -destination "platform=iOS Simulator,name=iPhone 15" test -only-testing:slabbistTests/BulkScanViewModelTests 2>&1 | tail -25`

Expected: both tests pass.

- [ ] **Step 5: Create `ScanQueueView.swift`**

`ios/slabbist/slabbist/Features/Scanning/BulkScan/ScanQueueView.swift`:

```swift
import SwiftUI

struct ScanQueueView: View {
    let scans: [Scan]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(scans) { scan in
                    scanChip(for: scan)
                }
            }
            .padding(.horizontal, Spacing.m)
        }
        .frame(height: 88)
    }

    private func scanChip(for scan: Scan) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(scan.grader.rawValue)
                .font(.caption.bold())
                .foregroundStyle(AppColor.accent)
            Text(scan.certNumber)
                .font(.caption2.monospaced())
                .lineLimit(1)
            statusBadge(for: scan.status)
        }
        .padding(Spacing.s)
        .frame(width: 92)
        .background(AppColor.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.m))
    }

    private func statusBadge(for status: ScanStatus) -> some View {
        let text: String
        let color: Color
        switch status {
        case .pendingValidation: text = "pending"; color = AppColor.warning
        case .validated:         text = "validated"; color = AppColor.success
        case .validationFailed:  text = "failed"; color = AppColor.danger
        case .manualEntry:       text = "manual"; color = AppColor.accent
        }
        return Text(text)
            .font(.caption2)
            .foregroundStyle(color)
    }
}
```

- [ ] **Step 6: Create `BulkScanView.swift`**

`ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanView.swift`:

```swift
import SwiftUI
import SwiftData
import AVFoundation
import Vision

struct BulkScanView: View {
    let lot: Lot
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session

    @State private var cameraSession = CameraSession()
    @State private var recognizer = CertOCRRecognizer()
    @State private var viewModel: BulkScanViewModel?
    @State private var lastCaptureFlash = false

    var body: some View {
        VStack(spacing: 0) {
            cameraArea
                .overlay(alignment: .center) {
                    if lastCaptureFlash {
                        Color.white.opacity(0.35)
                            .allowsHitTesting(false)
                    }
                }

            if let viewModel {
                VStack(spacing: Spacing.s) {
                    ScanQueueView(scans: viewModel.recentScans)
                    summaryLine(for: viewModel)
                }
                .padding(.vertical, Spacing.s)
                .background(AppColor.surface)
            }
        }
        .navigationTitle(lot.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            bootstrapViewModel()
            Task { await configureCamera() }
        }
        .onDisappear {
            cameraSession.stop()
        }
    }

    @ViewBuilder
    private var cameraArea: some View {
        switch cameraSession.authorization {
        case .authorized:
            CameraPreview(session: cameraSession.captureSession)
                .ignoresSafeArea(edges: [])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied, .restricted:
            VStack(spacing: Spacing.m) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Camera access is required to scan slabs.")
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.surfaceAlt)
        case .notDetermined:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summaryLine(for viewModel: BulkScanViewModel) -> some View {
        Text("\(viewModel.recentScans.count) scanned")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func bootstrapViewModel() {
        guard viewModel == nil, let userId = session.userId else { return }
        viewModel = BulkScanViewModel(context: context, lot: lot, currentUserId: userId)
    }

    private func configureCamera() async {
        await cameraSession.requestAuthorization()
        guard cameraSession.authorization == .authorized else { return }
        do {
            try cameraSession.configure()
            cameraSession.onSampleBuffer = { buffer in
                handle(buffer: buffer)
            }
            cameraSession.start()
        } catch {
            AppLog.camera.error("camera configure failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(buffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        let request = VNRecognizeTextRequest { request, _ in
            guard let results = request.results as? [VNRecognizedTextObservation] else { return }
            let topCandidates: [(String, Double)] = results.compactMap { obs in
                guard let cand = obs.topCandidates(1).first else { return nil }
                return (cand.string, Double(cand.confidence))
            }
            guard !topCandidates.isEmpty else { return }
            let maxConfidence = topCandidates.map(\.1).max() ?? 0
            let texts = topCandidates.map(\.0)

            Task { @MainActor in
                guard let cert = recognizer.ingest(textCandidates: texts,
                                                    visionConfidence: maxConfidence) else { return }
                do {
                    try viewModel?.record(candidate: cert)
                    await flash()
                } catch {
                    AppLog.scans.error("record capture failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])
    }

    @MainActor
    private func flash() async {
        lastCaptureFlash = true
        try? await Task.sleep(for: .milliseconds(120))
        lastCaptureFlash = false
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
```

- [ ] **Step 7: Wire `LotsListView` to navigate into `BulkScanView`**

Modify `LotsListView.swift`'s `.navigationDestination` block:

```swift
.navigationDestination(item: $selectedLot) { lot in
    BulkScanView(lot: lot)
}
```

- [ ] **Step 8: Build & manual smoke test on a physical device**

**The camera only works on a real device** — simulator cannot run AVFoundation. Before running:
1. Ensure the `slabbist` target is signed with a personal team.
2. Deploy to a real iPhone (Lightning/USB-C).
3. Sign in, create a lot, tap into it.
4. Point the camera at any PSA/BGS/CGC/SGC/TAG slab.
5. Expected: a brief white flash when a cert is detected; a chip appears in the queue with the cert number and "pending" badge.
6. Verify: kill the app and reopen; lot + scan still visible (SwiftData persistence).

If no physical device is available, skip the on-device smoke test and verify via the unit test suite; document the gap in the PR.

- [ ] **Step 9: Commit**

```bash
cd /Users/dixoncider/slabbist
git add ios/slabbist/slabbist/Features/Scanning/ \
  ios/slabbist/slabbist/Features/Lots/LotsListView.swift \
  ios/slabbist/slabbistTests/Features/BulkScanViewModelTests.swift \
  ios/slabbist/slabbist.xcodeproj/project.pbxproj
git commit -m "Plan 1 / T27: BulkScanView + ViewModel + ScanQueueView — walking skeleton complete"
```

---

## Task 28: Final integration smoke test & plan closeout

- [ ] **Step 1: Run the full unit test suite**

Run: `xcodebuild -scheme slabbist -destination "platform=iOS Simulator,name=iPhone 15" test 2>&1 | tail -30`

Expected: all suites pass — OutboxItemTests, ReachabilityTests, CurrencyTests, LotsViewModelTests, CertOCRPatternTests, CertOCRRecognizerStabilityTests, BulkScanViewModelTests.

- [ ] **Step 2: Run the Supabase pgTAP suite**

```bash
cd /Users/dixoncider/slabbist
supabase test db
```

Expected: 5/5 tests passed.

- [ ] **Step 3: Manually verify the end-to-end walking skeleton on device**

1. Fresh install of the app on a physical iPhone.
2. Sign up with a new email and a custom store name.
3. Verify in Supabase Studio that the store + store_members row exist.
4. Create a lot named "Device smoke test".
5. Point the camera at a PSA slab; cert appears in the queue as "pending".
6. Kill the app; reopen; the lot and scan are still present (SwiftData).
7. In Supabase Studio, the `lots` and `scans` tables are still empty — expected, because Plan 1 does not include the outbox worker that flushes to Supabase. The outbox row is visible via SwiftData introspection and confirms the write path is correct.

- [ ] **Step 4: Write a brief closeout note**

Append to the bottom of `docs/superpowers/plans/2026-04-22-bulk-scan-plan-1-walking-skeleton.md`:

```markdown
---

## Plan 1 closeout

**Status:** Completed on YYYY-MM-DD.

**What shipped:**
- Supabase tenant schema (stores, store_members, lots, scans) + RLS + signup trigger + pgTAP tests (5/5)
- iOS auth flow with auto-created store
- SwiftData models + outbox data structure (tenant tables only — graded mirrors land in Plan 2/3)
- Lots list + create flow (writes to outbox)
- Camera + Vision OCR + per-grader pattern recognition + stability gate
- Bulk scan screen with live queue
- Unit test coverage: OCR patterns, stability gate, LotsViewModel, BulkScanViewModel, Reachability, Currency

**Known gaps (addressed in later plans):**
- Outbox worker not yet implemented — local writes never reach Supabase (Plan 2)
- No cert validation against grader APIs (Plan 2 — imports tcgcsv graded libraries)
- No price comps (Plan 3 — reads from tcgcsv's `graded_market`)
- No lot review / export / permission-denied UX polish (Plan 4)

**Notes for Plan 2:**
- The `/cert-lookup` Edge Function imports `src/graded/sources/<service>.ts` and `src/graded/identity.ts` from the tcgcsv repo (workspace dep or equivalent). It upserts `graded_card_identities` + `graded_cards` via service-role client.
- Plan 2's first migration adds `scans.graded_card_identity_id uuid references graded_card_identities(id)` and `scans.graded_card_id uuid references graded_cards(id)`. This requires the tcgcsv graded-table migration to have landed first — coordinate via the shared `supabase/migrations/` directory and its timestamp ordering.
- `OutboxWorker` needs to collapse duplicate `certLookupJob` entries for the same `(grader, certNumber)`.
- A small "scan sync" indicator on BulkScanView is the first visible signal the user gets that the worker is alive.
```

- [ ] **Step 5: Commit the closeout note**

```bash
cd /Users/dixoncider/slabbist
git add docs/superpowers/plans/2026-04-22-bulk-scan-plan-1-walking-skeleton.md
git commit -m "Plan 1 / T28: closeout note"
```

- [ ] **Step 6: Optionally open a PR**

If the work happened on a feature branch:

```bash
cd /Users/dixoncider/slabbist
git push -u origin <branch>
gh pr create --title "Plan 1 — Walking skeleton (bulk scan + auth + schema)" --body "$(cat <<'EOF'
## Summary
- Supabase schema, RLS policies, and signup trigger for auto-created stores
- iOS auth flow, lots list, bulk scan camera + OCR pipeline (walking skeleton — no sync yet)

## Test plan
- [ ] `xcodebuild test` passes all suites
- [ ] `supabase test db` passes 5/5
- [ ] End-to-end smoke on physical device per Task 28 Step 3

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Ask the user before pushing/opening the PR — not every team wants a PR-per-plan.

---

## Plan 1 closeout

**Status:** Completed on 2026-04-22.

**Branch:** `plan-1-walking-skeleton` (feature branch, in-place on the primary repo). Not yet merged to main.

**What shipped:**
- Supabase tenant schema (`stores`, `store_members`, `lots`, `scans`) + RLS + signup trigger + pgTAP tests (5/5)
- iOS auth flow with auto-created store
- SwiftData models + outbox data structure (tenant tables only — graded mirrors land in Plan 2/3)
- Lots list + create flow (writes to outbox, pending sync)
- Camera + Vision OCR + per-grader pattern recognition + stability gate
- Bulk scan screen with live queue
- Unit test coverage: OCR patterns, stability gate, LotsViewModel, BulkScanViewModel, Reachability, Currency, OutboxItem — 23/23 passing

**Known gaps (addressed in later plans):**
- Outbox worker not yet implemented — local writes never reach Supabase (Plan 2)
- No cert validation against grader APIs (Plan 2 — imports tcgcsv graded libraries)
- No price comps (Plan 3 — reads from tcgcsv's `graded_market`)
- No lot review / export / permission-denied UX polish (Plan 4)
- No on-device smoke test run — physical-iPhone verification deferred. Unit tests and simulator build cover everything testable without real camera hardware.
- `LotsListView` depends on a local `Store` row existing for the signed-in user; no store-fetch sync on sign-in yet. Plan 2 introduces that.

**Learned-during-implementation observations (carry forward to later plans):**
- This Xcode project uses `PBXFileSystemSynchronizedRootGroup` — new Swift files drop into the source tree with no pbxproj edits required.
- Swift 6 strict concurrency required `@MainActor` on `SessionStore`, `AuthViewModel`, `LotsViewModel`, `BulkScanViewModel`, and `CertOCRRecognizer`.
- SwiftData's `#Predicate` macro does not support enum comparisons (`$0.status == .open`, `$0.grader == grader`). Both `LotsViewModel.listOpenLots()` and `BulkScanViewModel.isDuplicateLocally()` work around this by filtering enums in-memory after a simpler predicate-based fetch. Plan 2's outbox worker will hit the same issue if it wants to query `status == .pending`; either wait for SwiftData to support it or continue the filter-in-memory pattern.
- `xcodebuild -destination "generic/platform=iOS Simulator"` fails on this project/Xcode combo ("Supported platforms ... empty"). Use a concrete simulator name like `"platform=iOS Simulator,name=iPhone 17"`.
- The T10 pgTAP test of `lots_insert_members` had to use a temp table to carry store IDs across the role switch, because as user B, RLS on `stores` hides user A's store before the cross-tenant INSERT can even reach `lots`' insert-check policy.
- Supabase CLI 2.90.0 does NOT generate `supabase/seed.sql` from `supabase init` — the plan originally expected it. Committed `supabase/.gitignore` instead.
- `stores.owner_user_id` lacks `ON DELETE CASCADE`; deleting an `auth.users` row fails the FK. Not a Plan 1 bug, but worth fixing before multi-user/admin-delete flows.

**Notes for Plan 2:**
- The `/cert-lookup` Edge Function imports `src/graded/sources/<service>.ts` and `src/graded/identity.ts` from the tcgcsv repo. It upserts `graded_card_identities` + `graded_cards` via service-role client.
- Plan 2's first migration adds `scans.graded_card_identity_id uuid references graded_card_identities(id)` and `scans.graded_card_id uuid references graded_cards(id)`. Requires the tcgcsv graded-table migration to have landed first — coordinate via the shared `supabase/migrations/` directory and its timestamp ordering.
- `OutboxWorker` needs to collapse duplicate `certLookupJob` entries for the same `(grader, certNumber)`.
- A small "scan sync" indicator on BulkScanView is the first visible signal the user gets that the worker is alive.
- `BulkScanView.handle(buffer:)` runs Vision synchronously on the main actor for every frame. Fine for a walking-skeleton demo, but Plan 2 or later should move Vision to a background-isolated processor.

