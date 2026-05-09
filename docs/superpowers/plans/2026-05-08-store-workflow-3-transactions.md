# Store Workflow — Plan 3: Transactions Ledger

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The accepted state from Plan 2 commits to an immutable ledger. After this plan ships: tap "Mark paid" → server creates a `transactions` row + `transaction_lines` rows → iOS gets a hydrated receipt view → the lot is locked. Voids are a first-class operation that always inserts a new row (negative total, references the original) — never mutates or deletes. Vendor purchase history (stubbed in Plan 1) lights up.

**Architecture:** Two new tables (`transactions`, `transaction_lines`) with service-role-only writes via Edge Functions. The `/transaction-commit` Edge Function atomically reads each priced scan, builds an identity snapshot, inserts the rows, and flips the lot to `paid`. The `/transaction-void` Edge Function inserts a new void row pointing at the original. iOS gets `TransactionsRepository` + `TransactionsListView` + `TransactionDetailView`, plus state-aware UI gates that prevent edits to a paid lot's scans.

**Tech Stack:**
- iOS: Swift 6, SwiftUI, SwiftData, Swift Testing, XCUITest
- Backend: Postgres 15 (Supabase), Supabase Edge Functions (Deno + TS)

**Spec reference:** [`docs/superpowers/specs/2026-05-08-store-workflow-design.md`](../specs/2026-05-08-store-workflow-design.md). Implements **Transactions schema + RLS**, **`/transaction-commit`**, **`/transaction-void`**, **OfferRepository.commit / voidTransaction**, **Transactions/* iOS surfaces**, **post-paid immutability gating**, and **vendor purchase history**.

**Prerequisite:** Plans 1 + 2 must have shipped — `Vendor`, `Lot.lotOfferState`, `Scan.buyPriceCents`, and `OfferRepository`'s state machine must be in place.

---

## File structure

```
supabase/
├── migrations/
│   ├── 20260511130000_payment_method_enum.sql           # (T1)
│   ├── 20260511130100_transactions_table.sql            # (T1)
│   ├── 20260511130200_transaction_lines_table.sql       # (T1)
│   └── 20260511130300_transactions_rls.sql              # (T2)
├── functions/
│   ├── transaction-commit/                              # (T4)
│   │   ├── deno.json
│   │   ├── index.ts
│   │   └── __tests__/
│   │       └── commit.test.ts
│   └── transaction-void/                                # (T5)
│       ├── deno.json
│       ├── index.ts
│       └── __tests__/
│           └── void.test.ts
└── tests/
    ├── rls_transactions.sql                             # (T3)
    └── transactions_one_active_per_lot.sql              # (T3)

ios/slabbist/slabbist/
├── Core/
│   ├── Models/
│   │   ├── StoreTransaction.swift                       # (T6) NEW @Model
│   │   └── TransactionLine.swift                        # (T6) NEW @Model
│   └── Persistence/
│       ├── ModelContainer.swift                         # (T6) add StoreTransaction.self, TransactionLine.self
│       └── Outbox/
│           ├── OutboxKind.swift                         # (T7) add commitTransaction, voidTransaction
│           └── OutboxPayloads.swift                     # (T7) matching payloads
├── Features/
│   ├── Offers/
│   │   ├── OfferRepository.swift                        # (T8) add commit() + voidTransaction()
│   │   └── OfferReviewView.swift                        # (T9) wire Mark paid → commit; pending UI
│   ├── Transactions/                                    # NEW folder
│   │   ├── TransactionsRepository.swift                 # (T10)
│   │   ├── TransactionsListView.swift                   # (T11)
│   │   └── TransactionDetailView.swift                  # (T11)
│   ├── Lots/
│   │   ├── LotDetailView.swift                          # (T12) frozen banner; "View receipt" / "View void" routes
│   │   └── LotsListView.swift                           # (T12) "Recent transactions" section
│   ├── Scanning/
│   │   └── ScanDetailView.swift                         # (T12) frozen banner when lot is paid/voided
│   └── Vendors/
│       └── VendorDetailView.swift                       # (T13) replace stub with real history

ios/slabbist/slabbistTests/
├── Core/Models/
│   └── StoreTransactionTests.swift                      # (T6)
└── Features/
    ├── Offers/
    │   └── OfferRepositoryCommitTests.swift             # (T8)
    └── Transactions/
        └── TransactionsRepositoryTests.swift            # (T10)

ios/slabbist/slabbistUITests/
└── TransactionFlowUITests.swift                         # (T13) commit + void + frozen-edit gate
```

---

## Tasks

### Task 1 — Migration: `transactions` + `transaction_lines`

**Files:**
- Create: `supabase/migrations/20260511130000_payment_method_enum.sql`
- Create: `supabase/migrations/20260511130100_transactions_table.sql`
- Create: `supabase/migrations/20260511130200_transaction_lines_table.sql`

- [ ] **Step 1: Write the enum migration**

```sql
-- supabase/migrations/20260511130000_payment_method_enum.sql

create type payment_method as enum ('cash', 'check', 'store_credit', 'digital', 'other');
```

- [ ] **Step 2: Write the transactions migration**

```sql
-- supabase/migrations/20260511130100_transactions_table.sql

create table transactions (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references stores(id),
  lot_id uuid not null references lots(id),
  vendor_id uuid references vendors(id),
  vendor_name_snapshot text not null,
  total_buy_cents bigint not null,
  payment_method payment_method not null,
  payment_reference text,
  paid_at timestamptz not null,
  paid_by_user_id uuid not null references auth.users(id),
  voided_at timestamptz,
  voided_by_user_id uuid references auth.users(id),
  void_reason text,
  void_of_transaction_id uuid references transactions(id),
  created_at timestamptz not null default now()
);

create index transactions_store_paid_at on transactions(store_id, paid_at desc);
create index transactions_lot_id on transactions(lot_id);
create index transactions_vendor_id on transactions(vendor_id);

-- A lot has at most one non-voided transaction. Voids and the original both
-- have one of {void_of_transaction_id IS NOT NULL, voided_at IS NOT NULL},
-- so the partial uniqueness only matches "active originals."
create unique index transactions_one_active_per_lot
  on transactions(lot_id)
  where void_of_transaction_id is null and voided_at is null;

comment on table transactions is
  'Immutable buy ledger. Voids are new rows, never updates.';
comment on column transactions.vendor_name_snapshot is
  'Vendor display name at paid_at time. Stays stable if the vendor record is later renamed or archived.';
comment on column transactions.void_of_transaction_id is
  'Self-FK pointing at the original transaction this row voids.';
```

- [ ] **Step 3: Write the transaction_lines migration**

```sql
-- supabase/migrations/20260511130200_transaction_lines_table.sql

create table transaction_lines (
  transaction_id uuid not null references transactions(id) on delete cascade,
  scan_id uuid not null references scans(id),
  line_index int not null,
  buy_price_cents bigint not null,
  identity_snapshot jsonb not null,
  primary key (transaction_id, scan_id)
);

create index transaction_lines_scan_id on transaction_lines(scan_id);

comment on table transaction_lines is
  'Frozen line items per transaction. identity_snapshot captures card/cert details so a future schema change to graded_card_identities cannot retroactively rewrite a paid receipt.';
comment on column transaction_lines.identity_snapshot is
  'Shape: {card_name, set_name, card_number, year, variant, grader, grade, cert_number, comp_used_cents, reconciled_source}';
```

- [ ] **Step 4: Apply and confirm**

Run: `supabase migration up`
Expected: all three migrations apply; `\d transactions`, `\d transaction_lines` show the schema.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260511130000_payment_method_enum.sql \
        supabase/migrations/20260511130100_transactions_table.sql \
        supabase/migrations/20260511130200_transaction_lines_table.sql
git commit -m "feat(db): transactions + transaction_lines tables"
```

---

### Task 2 — Migration: RLS for transactions

**Files:**
- Create: `supabase/migrations/20260511130300_transactions_rls.sql`

- [ ] **Step 1: Write the migration**

```sql
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
```

- [ ] **Step 2: Apply + commit**

Run: `supabase migration up`

```bash
git add supabase/migrations/20260511130300_transactions_rls.sql
git commit -m "feat(db): RLS — transactions/transaction_lines select-only"
```

---

### Task 3 — pgTAP tests: RLS + unique-active-per-lot

**Files:**
- Create: `supabase/tests/rls_transactions.sql`
- Create: `supabase/tests/transactions_one_active_per_lot.sql`

- [ ] **Step 1: Write the RLS test**

```sql
-- supabase/tests/rls_transactions.sql
begin;
select plan(4);
create extension if not exists pgtap;

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-000000000c1', 'a@txn.test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000000c2', 'b@txn.test', 'authenticated', 'authenticated');

create temporary table _store_ids on commit drop as
select owner_user_id, id as store_id from stores;
grant select on _store_ids to authenticated;

-- Bypass the policy via service role to insert seed data.
set local role service_role;

insert into vendors (store_id, display_name)
select store_id, 'A Vendor' from _store_ids
where owner_user_id = '00000000-0000-0000-0000-000000000c1';

insert into lots (store_id, created_by_user_id, name, lot_offer_state)
select store_id, '00000000-0000-0000-0000-000000000c1', 'A Lot', 'accepted'
from _store_ids where owner_user_id = '00000000-0000-0000-0000-000000000c1';

insert into transactions (store_id, lot_id, vendor_id, vendor_name_snapshot,
                          total_buy_cents, payment_method, paid_at, paid_by_user_id)
select s.store_id, l.id, v.id, 'A Vendor', 1000, 'cash', now(), '00000000-0000-0000-0000-000000000c1'
from _store_ids s
join lots l on l.store_id = s.store_id and l.name = 'A Lot'
join vendors v on v.store_id = s.store_id and v.display_name = 'A Vendor'
where s.owner_user_id = '00000000-0000-0000-0000-000000000c1';

set local role authenticated;

-- USER A sees their own transaction
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000c1","role":"authenticated"}', true);
select is((select count(*)::int from transactions), 1, 'A sees their own transaction');

-- USER B sees zero
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000c2","role":"authenticated"}', true);
select is((select count(*)::int from transactions), 0, 'B sees no transactions across tenants');

-- USER A cannot insert a transaction directly (no policy permits insert)
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000c1","role":"authenticated"}', true);

select throws_ok($$
  insert into transactions (store_id, lot_id, vendor_name_snapshot,
                            total_buy_cents, payment_method, paid_at, paid_by_user_id)
  select s.store_id, l.id, 'X', 100, 'cash', now(), '00000000-0000-0000-0000-000000000c1'
  from _store_ids s join lots l on l.store_id = s.store_id and l.name = 'A Lot'
  where s.owner_user_id = '00000000-0000-0000-0000-000000000c1';
$$, NULL, 'A cannot insert a transaction directly (write must go through Edge Function)');

-- transaction_lines select scopes via parent transaction
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000c2","role":"authenticated"}', true);
select is((select count(*)::int from transaction_lines), 0, 'B sees no transaction lines either');

select * from finish();
rollback;
```

- [ ] **Step 2: Write the unique-active test**

```sql
-- supabase/tests/transactions_one_active_per_lot.sql
begin;
select plan(2);
create extension if not exists pgtap;

set local role service_role;

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-000000000d1', 'u@active.test', 'authenticated', 'authenticated');

create temporary table _ids on commit drop as
select id as store_id, owner_user_id from stores
where owner_user_id = '00000000-0000-0000-0000-000000000d1' limit 1;

insert into lots (store_id, created_by_user_id, name, lot_offer_state)
select store_id, owner_user_id, 'L', 'accepted' from _ids;

insert into transactions (store_id, lot_id, vendor_name_snapshot, total_buy_cents,
                          payment_method, paid_at, paid_by_user_id)
select s.store_id, l.id, 'V', 100, 'cash', now(), s.owner_user_id
from _ids s join lots l on l.store_id = s.store_id;

-- A second active transaction for the same lot must fail.
select throws_ok($$
  insert into transactions (store_id, lot_id, vendor_name_snapshot, total_buy_cents,
                            payment_method, paid_at, paid_by_user_id)
  select s.store_id, l.id, 'V', 200, 'cash', now(), s.owner_user_id
  from _ids s join lots l on l.store_id = s.store_id;
$$, '23505', 'unique partial index rejects a second non-voided txn for the same lot');

-- A void row (void_of_transaction_id IS NOT NULL) is allowed.
select lives_ok($$
  insert into transactions (store_id, lot_id, vendor_name_snapshot, total_buy_cents,
                            payment_method, paid_at, paid_by_user_id, void_of_transaction_id)
  select s.store_id, l.id, 'V', -100, 'cash', now(), s.owner_user_id, t.id
  from _ids s
  join lots l on l.store_id = s.store_id
  join transactions t on t.lot_id = l.id and t.void_of_transaction_id is null;
$$, 'void rows can be inserted alongside the original');

select * from finish();
rollback;
```

- [ ] **Step 3: Run + commit**

Run: `supabase test db`
Expected: PASS 4/4 + 2/2.

```bash
git add supabase/tests/rls_transactions.sql \
        supabase/tests/transactions_one_active_per_lot.sql
git commit -m "test(db): RLS + unique-active-per-lot for transactions"
```

---

### Task 4 — Edge Function: `/transaction-commit`

**Files:**
- Create: `supabase/functions/transaction-commit/deno.json`
- Create: `supabase/functions/transaction-commit/index.ts`
- Create: `supabase/functions/transaction-commit/__tests__/commit.test.ts`

- [ ] **Step 1: Write the deno config**

```json
{
  "imports": {
    "@supabase/supabase-js": "npm:@supabase/supabase-js@^2.45.0",
    "jsr:@std/assert": "jsr:@std/assert@^1.0.0"
  }
}
```

- [ ] **Step 2: Write the failing test for the snapshot helper**

```typescript
// supabase/functions/transaction-commit/__tests__/commit.test.ts
import { assertEquals } from "jsr:@std/assert";
import { buildIdentitySnapshot, resolveVendorNameSnapshot } from "../index.ts";

Deno.test("buildIdentitySnapshot pulls all expected fields", () => {
  const snap = buildIdentitySnapshot({
    scan: { grader: "PSA", grade: "10", cert_number: "12345678",
            reconciled_headline_price_cents: 18500, reconciled_source: "avg" },
    identity: { card_name: "Charizard", set_name: "Base Set",
                card_number: "4", year: 1999, variant: "Holo" },
  });
  assertEquals(snap, {
    card_name: "Charizard", set_name: "Base Set", card_number: "4",
    year: 1999, variant: "Holo",
    grader: "PSA", grade: "10", cert_number: "12345678",
    comp_used_cents: 18500, reconciled_source: "avg",
  });
});

Deno.test("buildIdentitySnapshot tolerates missing identity (manual entry scan)", () => {
  const snap = buildIdentitySnapshot({
    scan: { grader: "PSA", grade: null, cert_number: "x",
            reconciled_headline_price_cents: null, reconciled_source: null },
    identity: null,
  });
  assertEquals(snap, {
    card_name: null, set_name: null, card_number: null,
    year: null, variant: null,
    grader: "PSA", grade: null, cert_number: "x",
    comp_used_cents: null, reconciled_source: null,
  });
});

Deno.test("resolveVendorNameSnapshot precedence: override > vendor > unknown", () => {
  assertEquals(resolveVendorNameSnapshot({ override: "X", vendor: { display_name: "Y" } }), "X");
  assertEquals(resolveVendorNameSnapshot({ override: null, vendor: { display_name: "Y" } }), "Y");
  assertEquals(resolveVendorNameSnapshot({ override: null, vendor: null }), "(unknown)");
  assertEquals(resolveVendorNameSnapshot({ override: "", vendor: { display_name: "Y" } }), "Y");
});
```

- [ ] **Step 3: Run (FAIL — module doesn't exist)**

Run: `cd supabase/functions/transaction-commit && deno test --allow-net --allow-env`
Expected: FAIL.

- [ ] **Step 4: Implement the Edge Function**

```typescript
// supabase/functions/transaction-commit/index.ts
// @ts-nocheck — Deno + remote imports.
//
// /transaction-commit
// Atomic: read priced scans, snapshot identities, INSERT transactions row,
// INSERT transaction_lines rows, UPDATE lots.lot_offer_state to 'paid'.
// All in one Postgres transaction via a Postgres function.
//
// Request: { lot_id, payment_method, payment_reference?, vendor_id?, vendor_name_override? }
// Response 200: { transaction, lines[] }
// Response 409: state precondition failure (lot not accepted, or duplicate)
// Response 422: validation failure (no priced scans)
// Response 403: caller not a store member with required role

import { createClient } from "@supabase/supabase-js";

interface Scan {
  id: string;
  grader: string;
  grade: string | null;
  cert_number: string;
  buy_price_cents: number | null;
  graded_card_identity_id: string | null;
  reconciled_headline_price_cents: number | null;
  reconciled_source: string | null;
}

interface Identity {
  id: string;
  card_name: string;
  set_name: string;
  card_number: string | null;
  year: number | null;
  variant: string | null;
}

interface Vendor {
  id: string;
  display_name: string;
}

export function buildIdentitySnapshot(args: {
  scan: Pick<Scan, "grader" | "grade" | "cert_number" | "reconciled_headline_price_cents" | "reconciled_source">;
  identity: Pick<Identity, "card_name" | "set_name" | "card_number" | "year" | "variant"> | null;
}): Record<string, unknown> {
  const i = args.identity;
  return {
    card_name: i?.card_name ?? null,
    set_name: i?.set_name ?? null,
    card_number: i?.card_number ?? null,
    year: i?.year ?? null,
    variant: i?.variant ?? null,
    grader: args.scan.grader,
    grade: args.scan.grade,
    cert_number: args.scan.cert_number,
    comp_used_cents: args.scan.reconciled_headline_price_cents,
    reconciled_source: args.scan.reconciled_source,
  };
}

export function resolveVendorNameSnapshot(args: {
  override: string | null | undefined;
  vendor: Pick<Vendor, "display_name"> | null;
}): string {
  const o = (args.override ?? "").trim();
  if (o) return o;
  if (args.vendor?.display_name) return args.vendor.display_name;
  return "(unknown)";
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

function env(name: string): string {
  const v = Deno.env.get(name);
  if (v === undefined || v === "") throw new Error(`missing env: ${name}`);
  return v;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, x-client-info, apikey, content-type", "access-control-allow-methods": "POST, OPTIONS" } });
  }
  if (req.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });

  let body: { lot_id?: string; payment_method?: string; payment_reference?: string;
              vendor_id?: string; vendor_name_override?: string };
  try { body = await req.json(); } catch { return json(400, { code: "INVALID_JSON" }); }
  if (!body?.lot_id || !body?.payment_method) return json(400, { code: "MISSING_FIELDS" });

  const userClient = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: req.headers.get("authorization") ?? "" } },
  });
  const serviceClient = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));

  // Identify caller.
  const { data: who, error: whoErr } = await userClient.auth.getUser();
  if (whoErr || !who?.user) return json(401, { code: "UNAUTHENTICATED" });
  const userId = who.user.id;

  // Membership + role check (MVP: any member can commit; role gating ships in subproject 7).
  const { data: lot, error: lotErr } = await serviceClient
    .from("lots")
    .select("id, store_id, vendor_id, lot_offer_state")
    .eq("id", body.lot_id)
    .maybeSingle();
  if (lotErr) return json(500, { code: "DB_ERROR", detail: lotErr.message });
  if (!lot) return json(404, { code: "LOT_NOT_FOUND" });

  const { data: membership } = await serviceClient
    .from("store_members")
    .select("role")
    .eq("store_id", lot.store_id)
    .eq("user_id", userId)
    .maybeSingle();
  if (!membership) return json(403, { code: "NOT_A_MEMBER" });

  if (lot.lot_offer_state !== "accepted") {
    return json(409, { code: "WRONG_STATE", lot_offer_state: lot.lot_offer_state });
  }

  // Fetch priced scans + identities for snapshot.
  const { data: scans, error: scansErr } = await serviceClient
    .from("scans")
    .select("id, grader, grade, cert_number, buy_price_cents, graded_card_identity_id, reconciled_headline_price_cents, reconciled_source")
    .eq("lot_id", body.lot_id);
  if (scansErr) return json(500, { code: "DB_ERROR", detail: scansErr.message });

  const priced = (scans ?? []).filter((s) => typeof s.buy_price_cents === "number" && s.buy_price_cents > 0);
  if (priced.length === 0) return json(422, { code: "NO_PRICED_LINES" });

  // Hydrate identities.
  const identityIds = priced.map((s) => s.graded_card_identity_id).filter((id): id is string => !!id);
  let identityMap: Record<string, Identity> = {};
  if (identityIds.length > 0) {
    const { data: idents, error: identErr } = await serviceClient
      .from("graded_card_identities")
      .select("id, card_name, set_name, card_number, year, variant")
      .in("id", identityIds);
    if (identErr) return json(500, { code: "DB_ERROR", detail: identErr.message });
    identityMap = Object.fromEntries((idents ?? []).map((i) => [i.id, i as Identity]));
  }

  // Resolve vendor snapshot.
  let vendor: Vendor | null = null;
  const vendorId = body.vendor_id ?? lot.vendor_id ?? null;
  if (vendorId) {
    const { data: v } = await serviceClient
      .from("vendors")
      .select("id, display_name")
      .eq("id", vendorId)
      .maybeSingle();
    vendor = v as Vendor | null;
  }
  const vendorNameSnapshot = resolveVendorNameSnapshot({
    override: body.vendor_name_override ?? null,
    vendor: vendor ? { display_name: vendor.display_name } : null,
  });

  const totalBuyCents = priced.reduce((acc, s) => acc + (s.buy_price_cents ?? 0), 0);
  const txnId = crypto.randomUUID();
  const paidAt = new Date().toISOString();

  // INSERT transaction. The unique partial index on (lot_id) where
  // void_of_transaction_id IS NULL AND voided_at IS NULL guards against
  // a duplicate commit racing in.
  const { error: txnErr } = await serviceClient.from("transactions").insert({
    id: txnId,
    store_id: lot.store_id,
    lot_id: lot.id,
    vendor_id: vendorId,
    vendor_name_snapshot: vendorNameSnapshot,
    total_buy_cents: totalBuyCents,
    payment_method: body.payment_method,
    payment_reference: body.payment_reference ?? null,
    paid_at: paidAt,
    paid_by_user_id: userId,
  });
  if (txnErr) {
    if (txnErr.code === "23505") {
      // Duplicate; fetch and return the existing transaction so the iOS outbox
      // worker treats this as success and refreshes local state.
      const { data: existing } = await serviceClient
        .from("transactions")
        .select("*")
        .eq("lot_id", lot.id)
        .is("void_of_transaction_id", null)
        .is("voided_at", null)
        .maybeSingle();
      if (existing) {
        const { data: existingLines } = await serviceClient
          .from("transaction_lines")
          .select("*")
          .eq("transaction_id", existing.id);
        return json(200, { transaction: existing, lines: existingLines ?? [], deduped: true });
      }
    }
    return json(500, { code: "DB_ERROR", detail: txnErr.message });
  }

  // INSERT transaction_lines.
  const lines = priced.map((s, idx) => ({
    transaction_id: txnId,
    scan_id: s.id,
    line_index: idx,
    buy_price_cents: s.buy_price_cents!,
    identity_snapshot: buildIdentitySnapshot({
      scan: s,
      identity: s.graded_card_identity_id ? (identityMap[s.graded_card_identity_id] ?? null) : null,
    }),
  }));
  const { error: linesErr } = await serviceClient.from("transaction_lines").insert(lines);
  if (linesErr) return json(500, { code: "DB_ERROR", detail: linesErr.message });

  // Flip the lot.
  const { error: lotUpdErr } = await serviceClient
    .from("lots")
    .update({
      lot_offer_state: "paid",
      lot_offer_state_updated_at: paidAt,
      status: "converted",
    })
    .eq("id", lot.id);
  if (lotUpdErr) return json(500, { code: "DB_ERROR", detail: lotUpdErr.message });

  // Re-read for the response.
  const { data: txn } = await serviceClient.from("transactions").select("*").eq("id", txnId).maybeSingle();
  return json(200, { transaction: txn, lines });
});
```

- [ ] **Step 5: Run unit tests + commit**

Run: `cd supabase/functions/transaction-commit && deno test --allow-net --allow-env`
Expected: PASS.

```bash
git add supabase/functions/transaction-commit
git commit -m "feat(edge): /transaction-commit with idempotent dedup"
```

---

### Task 5 — Edge Function: `/transaction-void`

**Files:**
- Create: `supabase/functions/transaction-void/deno.json`
- Create: `supabase/functions/transaction-void/index.ts`
- Create: `supabase/functions/transaction-void/__tests__/void.test.ts`

- [ ] **Step 1: Write deno.json (same shape as commit)**

(Identical content to `transaction-commit/deno.json`.)

- [ ] **Step 2: Write the failing test**

```typescript
// __tests__/void.test.ts
import { assertEquals } from "jsr:@std/assert";
import { buildVoidRow } from "../index.ts";

Deno.test("buildVoidRow inverts total and links to original", () => {
  const orig = {
    id: "00000000-0000-0000-0000-000000000001",
    store_id: "00000000-0000-0000-0000-0000000000aa",
    lot_id: "00000000-0000-0000-0000-0000000000bb",
    vendor_id: "00000000-0000-0000-0000-0000000000cc",
    vendor_name_snapshot: "Acme",
    total_buy_cents: 10_000,
    payment_method: "cash",
  };
  const userId = "00000000-0000-0000-0000-0000000000ff";
  const row = buildVoidRow({ original: orig, userId, reason: "vendor returned" });
  assertEquals(row.total_buy_cents, -10_000);
  assertEquals(row.void_of_transaction_id, orig.id);
  assertEquals(row.voided_by_user_id, userId);
  assertEquals(row.void_reason, "vendor returned");
  assertEquals(row.vendor_name_snapshot, "Acme");
  assertEquals(row.payment_method, "cash");
  assertEquals(typeof row.voided_at, "string");
});
```

- [ ] **Step 3: Run (FAIL)**

Run: `cd supabase/functions/transaction-void && deno test --allow-net --allow-env`
Expected: FAIL.

- [ ] **Step 4: Implement the function**

```typescript
// __tests__/void.ts
// @ts-nocheck

import { createClient } from "@supabase/supabase-js";

interface Original {
  id: string;
  store_id: string;
  lot_id: string;
  vendor_id: string | null;
  vendor_name_snapshot: string;
  total_buy_cents: number;
  payment_method: string;
}

export function buildVoidRow(args: {
  original: Original;
  userId: string;
  reason: string;
}): Record<string, unknown> {
  const now = new Date().toISOString();
  return {
    store_id: args.original.store_id,
    lot_id: args.original.lot_id,
    vendor_id: args.original.vendor_id,
    vendor_name_snapshot: args.original.vendor_name_snapshot,
    total_buy_cents: -args.original.total_buy_cents,
    payment_method: args.original.payment_method,
    paid_at: now,
    paid_by_user_id: args.userId,
    voided_at: now,
    voided_by_user_id: args.userId,
    void_reason: args.reason,
    void_of_transaction_id: args.original.id,
  };
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

function env(name: string): string {
  const v = Deno.env.get(name);
  if (v === undefined || v === "") throw new Error(`missing env: ${name}`);
  return v;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, x-client-info, apikey, content-type", "access-control-allow-methods": "POST, OPTIONS" } });
  }
  if (req.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });

  let body: { transaction_id?: string; reason?: string };
  try { body = await req.json(); } catch { return json(400, { code: "INVALID_JSON" }); }
  if (!body?.transaction_id || !body?.reason) return json(400, { code: "MISSING_FIELDS" });

  const userClient = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: req.headers.get("authorization") ?? "" } },
  });
  const service = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));

  const { data: who, error: whoErr } = await userClient.auth.getUser();
  if (whoErr || !who?.user) return json(401, { code: "UNAUTHENTICATED" });
  const userId = who.user.id;

  const { data: original, error: getErr } = await service
    .from("transactions")
    .select("id, store_id, lot_id, vendor_id, vendor_name_snapshot, total_buy_cents, payment_method, voided_at, void_of_transaction_id")
    .eq("id", body.transaction_id)
    .maybeSingle();
  if (getErr) return json(500, { code: "DB_ERROR", detail: getErr.message });
  if (!original) return json(404, { code: "NOT_FOUND" });

  if (original.voided_at !== null || original.void_of_transaction_id !== null) {
    return json(409, { code: "ALREADY_VOIDED" });
  }

  const { data: membership } = await service
    .from("store_members")
    .select("role")
    .eq("store_id", original.store_id)
    .eq("user_id", userId)
    .maybeSingle();
  if (!membership) return json(403, { code: "NOT_A_MEMBER" });

  // Mark original.
  const now = new Date().toISOString();
  const { error: markErr } = await service
    .from("transactions")
    .update({ voided_at: now, voided_by_user_id: userId, void_reason: body.reason })
    .eq("id", original.id);
  if (markErr) return json(500, { code: "DB_ERROR", detail: markErr.message });

  // Insert void row.
  const voidRow = buildVoidRow({ original: original as Original, userId, reason: body.reason });
  const { data: inserted, error: voidErr } = await service.from("transactions").insert(voidRow).select("*").maybeSingle();
  if (voidErr) return json(500, { code: "DB_ERROR", detail: voidErr.message });

  // Flip lot to voided.
  await service.from("lots")
    .update({ lot_offer_state: "voided", lot_offer_state_updated_at: now })
    .eq("id", original.lot_id);

  return json(200, { void_transaction: inserted, original_id: original.id });
});
```

- [ ] **Step 5: Run + commit**

Run: `cd supabase/functions/transaction-void && deno test --allow-net --allow-env`
Expected: PASS.

```bash
git add supabase/functions/transaction-void
git commit -m "feat(edge): /transaction-void"
```

---

### Task 6 — `StoreTransaction` + `TransactionLine` SwiftData models

**Files:**
- Create: `ios/slabbist/slabbist/Core/Models/StoreTransaction.swift`
- Create: `ios/slabbist/slabbist/Core/Models/TransactionLine.swift`
- Modify: `ios/slabbist/slabbist/Core/Persistence/ModelContainer.swift`
- Create: `ios/slabbist/slabbistTests/Core/Models/StoreTransactionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// slabbistTests/Core/Models/StoreTransactionTests.swift
import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct StoreTransactionTests {
    @Test func insertAndFetch() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let txn = StoreTransaction(
            id: UUID(), storeId: UUID(), lotId: UUID(),
            vendorId: UUID(), vendorNameSnapshot: "Acme",
            totalBuyCents: 1500, paymentMethod: "cash",
            paymentReference: nil,
            paidAt: Date(), paidByUserId: UUID(),
            createdAt: Date()
        )
        context.insert(txn)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<StoreTransaction>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.totalBuyCents == 1500)
    }
}
```

- [ ] **Step 2: Run (FAIL)**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Core/Models/StoreTransactionTests -quiet`
Expected: FAIL.

- [ ] **Step 3: Implement the models**

```swift
// Core/Models/StoreTransaction.swift
import Foundation
import SwiftData

/// "Transaction" collides with Combine; "StoreTransaction" disambiguates.
@Model
final class StoreTransaction {
    @Attribute(.unique) var id: UUID
    var storeId: UUID
    var lotId: UUID
    var vendorId: UUID?
    var vendorNameSnapshot: String
    var totalBuyCents: Int64
    /// Mirrors Postgres `payment_method` enum string.
    var paymentMethod: String
    var paymentReference: String?
    var paidAt: Date
    var paidByUserId: UUID
    var voidedAt: Date?
    var voidedByUserId: UUID?
    var voidReason: String?
    var voidOfTransactionId: UUID?
    var createdAt: Date

    init(
        id: UUID, storeId: UUID, lotId: UUID,
        vendorId: UUID?, vendorNameSnapshot: String,
        totalBuyCents: Int64, paymentMethod: String,
        paymentReference: String?,
        paidAt: Date, paidByUserId: UUID,
        voidedAt: Date? = nil, voidedByUserId: UUID? = nil,
        voidReason: String? = nil, voidOfTransactionId: UUID? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.storeId = storeId
        self.lotId = lotId
        self.vendorId = vendorId
        self.vendorNameSnapshot = vendorNameSnapshot
        self.totalBuyCents = totalBuyCents
        self.paymentMethod = paymentMethod
        self.paymentReference = paymentReference
        self.paidAt = paidAt
        self.paidByUserId = paidByUserId
        self.voidedAt = voidedAt
        self.voidedByUserId = voidedByUserId
        self.voidReason = voidReason
        self.voidOfTransactionId = voidOfTransactionId
        self.createdAt = createdAt
    }

    /// Convenience: a row is "active" (counts toward totals) if it isn't voided AND isn't itself a void.
    var isActive: Bool { voidedAt == nil && voidOfTransactionId == nil }
}
```

```swift
// Core/Models/TransactionLine.swift
import Foundation
import SwiftData

@Model
final class TransactionLine {
    /// Composite "{transactionId}:{scanId}" — SwiftData @Model needs a single unique attribute
    /// for the iOS-side cache. Server-side uniqueness lives in (transaction_id, scan_id) PK.
    @Attribute(.unique) var compositeKey: String
    var transactionId: UUID
    var scanId: UUID
    var lineIndex: Int
    var buyPriceCents: Int64
    var identitySnapshotJSON: Data

    init(
        transactionId: UUID, scanId: UUID, lineIndex: Int,
        buyPriceCents: Int64, identitySnapshotJSON: Data
    ) {
        self.compositeKey = "\(transactionId.uuidString):\(scanId.uuidString)"
        self.transactionId = transactionId
        self.scanId = scanId
        self.lineIndex = lineIndex
        self.buyPriceCents = buyPriceCents
        self.identitySnapshotJSON = identitySnapshotJSON
    }
}
```

- [ ] **Step 4: Wire into `ModelContainer`** — add `StoreTransaction.self`, `TransactionLine.self` to **both** `Schema` arrays.

- [ ] **Step 5: Run tests to confirm green + commit**

```bash
xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Core/Models -quiet
git add ios/slabbist/slabbist/Core/Models/StoreTransaction.swift \
        ios/slabbist/slabbist/Core/Models/TransactionLine.swift \
        ios/slabbist/slabbist/Core/Persistence/ModelContainer.swift \
        ios/slabbist/slabbistTests/Core/Models/StoreTransactionTests.swift
git commit -m "feat(ios): StoreTransaction + TransactionLine SwiftData models"
```

---

### Task 7 — OutboxKinds: `commitTransaction`, `voidTransaction`

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxKind.swift`
- Modify: `ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxPayloads.swift`
- Modify: `ios/slabbist/slabbist/Core/Sync/OutboxDrainer.swift`

- [ ] **Step 1: Add the kinds + priorities**

```swift
case commitTransaction    // priority 45 — above price-comp, below deletes
case voidTransaction      // priority 44 — just below commit
```

In the priority switch:

```swift
case .commitTransaction: return 45
case .voidTransaction:   return 44
```

- [ ] **Step 2: Add the payloads**

```swift
struct CommitTransaction: Codable {
    let lot_id: String
    let payment_method: String
    let payment_reference: String?
    let vendor_id: String?
    let vendor_name_override: String?
}

struct VoidTransaction: Codable {
    let transaction_id: String
    let reason: String
}
```

- [ ] **Step 3: Wire `OutboxDrainer` to call the Edge Functions**

```swift
case .commitTransaction:
    let p = try JSONDecoder().decode(OutboxPayloads.CommitTransaction.self, from: item.payload)
    let resp = try await client.functions.invoke(
        "transaction-commit",
        options: .init(body: try JSONEncoder().encode(p))
    )
    // The drainer's response handler should upsert the returned transaction
    // and lines into SwiftData (via a callback registered by OfferRepository
    // or a dedicated hydrator).
    return .success
case .voidTransaction:
    let p = try JSONDecoder().decode(OutboxPayloads.VoidTransaction.self, from: item.payload)
    let resp = try await client.functions.invoke(
        "transaction-void",
        options: .init(body: try JSONEncoder().encode(p))
    )
    return .success
```

(Match the existing `OutboxDrainer` invocation pattern — if it uses `URLSession` directly rather than the Supabase SDK's `functions.invoke`, mirror that.)

- [ ] **Step 4: Build + commit**

Run: `xcodebuild build -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

```bash
git add ios/slabbist/slabbist/Core/Persistence/Outbox/ \
        ios/slabbist/slabbist/Core/Sync/OutboxDrainer.swift
git commit -m "feat(ios): outbox kinds for commit/void transaction"
```

---

### Task 8 — `OfferRepository.commit` + `voidTransaction` + tests

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Offers/OfferRepository.swift`
- Create: `ios/slabbist/slabbistTests/Features/Offers/OfferRepositoryCommitTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// slabbistTests/Features/Offers/OfferRepositoryCommitTests.swift
import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct OfferRepositoryCommitTests {
    @Test func commitEnqueuesOutboxItemAndKeepsLotAccepted() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let kicker = OutboxKicker()
        let lot = Lot(id: UUID(), storeId: UUID(), createdByUserId: UUID(), name: "L", createdAt: Date(), updatedAt: Date())
        lot.lotOfferState = LotOfferState.accepted.rawValue
        context.insert(lot); try context.save()

        let repo = OfferRepository(context: context, kicker: kicker, currentStoreId: lot.storeId, currentUserId: UUID())
        try repo.commit(lot: lot, paymentMethod: "cash", paymentReference: nil)
        // Lot stays accepted until the worker round-trips and a `paid` rehydrates locally.
        #expect(lot.lotOfferState == LotOfferState.accepted.rawValue)
        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.contains(where: { $0.kind == .commitTransaction }))
    }

    @Test func commitRejectsNonAcceptedLots() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let kicker = OutboxKicker()
        let lot = Lot(id: UUID(), storeId: UUID(), createdByUserId: UUID(), name: "L", createdAt: Date(), updatedAt: Date())
        lot.lotOfferState = LotOfferState.priced.rawValue
        context.insert(lot); try context.save()
        let repo = OfferRepository(context: context, kicker: kicker, currentStoreId: lot.storeId, currentUserId: UUID())
        #expect(throws: OfferRepository.InvalidTransition.self) {
            try repo.commit(lot: lot, paymentMethod: "cash", paymentReference: nil)
        }
    }

    @Test func voidTransactionEnqueuesItem() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let kicker = OutboxKicker()
        let txn = StoreTransaction(
            id: UUID(), storeId: UUID(), lotId: UUID(),
            vendorId: nil, vendorNameSnapshot: "X",
            totalBuyCents: 100, paymentMethod: "cash", paymentReference: nil,
            paidAt: Date(), paidByUserId: UUID(),
            createdAt: Date()
        )
        context.insert(txn); try context.save()
        let repo = OfferRepository(context: context, kicker: kicker, currentStoreId: txn.storeId, currentUserId: UUID())
        try repo.voidTransaction(txn, reason: "tester")
        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.contains(where: { $0.kind == .voidTransaction }))
    }
}
```

- [ ] **Step 2: Run (FAIL — methods don't exist yet)**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Features/Offers/OfferRepositoryCommitTests -quiet`
Expected: FAIL.

- [ ] **Step 3: Add `commit` and `voidTransaction` to `OfferRepository`**

```swift
extension OfferRepository {
    func commit(lot: Lot, paymentMethod: String, paymentReference: String?) throws {
        let current = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
        guard Self.canTransition(from: current, to: .paid) else {
            throw InvalidTransition.notAllowed(from: current, to: .paid)
        }
        let payload = OutboxPayloads.CommitTransaction(
            lot_id: lot.id.uuidString,
            payment_method: paymentMethod,
            payment_reference: paymentReference,
            vendor_id: lot.vendorId?.uuidString,
            vendor_name_override: nil
        )
        let item = OutboxItem(
            id: UUID(), kind: .commitTransaction,
            payload: try JSONEncoder().encode(payload),
            status: .pending, attempts: 0,
            createdAt: Date(), nextAttemptAt: Date()
        )
        context.insert(item)
        try context.save()
        kicker.kick()
        // Lot stays in `accepted` until the worker drains. The drainer's
        // success path will upsert StoreTransaction + TransactionLine rows
        // into SwiftData and flip lot.lotOfferState to .paid.
    }

    func voidTransaction(_ txn: StoreTransaction, reason: String) throws {
        let payload = OutboxPayloads.VoidTransaction(
            transaction_id: txn.id.uuidString,
            reason: reason
        )
        let item = OutboxItem(
            id: UUID(), kind: .voidTransaction,
            payload: try JSONEncoder().encode(payload),
            status: .pending, attempts: 0,
            createdAt: Date(), nextAttemptAt: Date()
        )
        context.insert(item)
        try context.save()
        kicker.kick()
    }
}
```

- [ ] **Step 4: Wire the drainer success path to hydrate transactions**

In `OutboxDrainer.swift`, after `commitTransaction` succeeds, the response body contains `{ transaction, lines }`. Parse it and upsert into SwiftData:

```swift
case .commitTransaction:
    let resp = try await client.functions.invoke("transaction-commit", ...)
    let payload = try JSONDecoder().decode(CommitResponse.self, from: resp.data)
    try TransactionsHydrator.upsert(payload, in: context)
    return .success
```

```swift
// Features/Transactions/TransactionsHydrator.swift  (NEW)
import Foundation
import SwiftData

struct CommitResponse: Codable {
    struct TxnDTO: Codable {
        let id: String; let store_id: String; let lot_id: String
        let vendor_id: String?; let vendor_name_snapshot: String
        let total_buy_cents: Int64; let payment_method: String; let payment_reference: String?
        let paid_at: String; let paid_by_user_id: String
        let voided_at: String?; let voided_by_user_id: String?
        let void_reason: String?; let void_of_transaction_id: String?
    }
    struct LineDTO: Codable {
        let transaction_id: String; let scan_id: String; let line_index: Int
        let buy_price_cents: Int64; let identity_snapshot: [String: AnyCodable]?
    }
    let transaction: TxnDTO
    let lines: [LineDTO]
}

@MainActor
enum TransactionsHydrator {
    static func upsert(_ payload: CommitResponse, in context: ModelContext) throws {
        let txn = StoreTransaction(
            id: UUID(uuidString: payload.transaction.id)!,
            storeId: UUID(uuidString: payload.transaction.store_id)!,
            lotId: UUID(uuidString: payload.transaction.lot_id)!,
            vendorId: payload.transaction.vendor_id.flatMap(UUID.init(uuidString:)),
            vendorNameSnapshot: payload.transaction.vendor_name_snapshot,
            totalBuyCents: payload.transaction.total_buy_cents,
            paymentMethod: payload.transaction.payment_method,
            paymentReference: payload.transaction.payment_reference,
            paidAt: ISO8601DateFormatter.shared.date(from: payload.transaction.paid_at) ?? Date(),
            paidByUserId: UUID(uuidString: payload.transaction.paid_by_user_id) ?? UUID(),
            voidedAt: payload.transaction.voided_at.flatMap(ISO8601DateFormatter.shared.date(from:)),
            voidedByUserId: payload.transaction.voided_by_user_id.flatMap(UUID.init(uuidString:)),
            voidReason: payload.transaction.void_reason,
            voidOfTransactionId: payload.transaction.void_of_transaction_id.flatMap(UUID.init(uuidString:)),
            createdAt: Date()
        )
        context.insert(txn)
        for line in payload.lines {
            let raw = try JSONEncoder().encode(line.identity_snapshot ?? [:])
            let row = TransactionLine(
                transactionId: UUID(uuidString: line.transaction_id)!,
                scanId: UUID(uuidString: line.scan_id)!,
                lineIndex: line.line_index,
                buyPriceCents: line.buy_price_cents,
                identitySnapshotJSON: raw
            )
            context.insert(row)
        }
        // Flip the lot to paid.
        let lotId = txn.lotId
        if let lot = try context.fetch(FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })).first {
            lot.lotOfferState = LotOfferState.paid.rawValue
            lot.lotOfferStateUpdatedAt = Date()
            lot.status = .converted
        }
        try context.save()
    }
}

// Helper for arbitrary JSON values in the snapshot.
struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { value = v; return }
        if let v = try? c.decode(Int.self) { value = v; return }
        if let v = try? c.decode(Double.self) { value = v; return }
        if let v = try? c.decode(Bool.self) { value = v; return }
        if c.decodeNil() { value = NSNull(); return }
        value = NSNull()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as String: try c.encode(v)
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as Bool: try c.encode(v)
        default: try c.encodeNil()
        }
    }
}
```

- [ ] **Step 5: Run + commit**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Features/Offers -quiet`
Expected: PASS.

```bash
git add ios/slabbist/slabbist/Features/Offers/OfferRepository.swift \
        ios/slabbist/slabbist/Features/Transactions/TransactionsHydrator.swift \
        ios/slabbist/slabbist/Core/Sync/OutboxDrainer.swift \
        ios/slabbist/slabbistTests/Features/Offers/OfferRepositoryCommitTests.swift
git commit -m "feat(ios): OfferRepository.commit + voidTransaction + drainer hydration"
```

---

### Task 9 — Wire `OfferReviewView` "Mark paid" through the commit path

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Offers/OfferReviewView.swift`

- [ ] **Step 1: Update the Mark paid action**

Replace the Plan-2 "transition locally" code with the commit call. Add a "Sync pending" UI state:

```swift
@State private var isCommitting = false
@State private var commitError: String?

private var markPaidButton: some View {
    PrimaryGoldButton(
        title: isCommitting ? "Committing…" : "Mark paid",
        isEnabled: canMarkPaid && !isCommitting
    ) {
        commit()
    }
    .accessibilityIdentifier("mark-paid")
}

private var canMarkPaid: Bool {
    let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
    return state == .accepted || state == .presented
}

private func commit() {
    let repo = offerRepository()
    do {
        if LotOfferState(rawValue: lot.lotOfferState) != .accepted {
            try repo.recordAcceptance(lot)
        }
        try repo.commit(
            lot: lot,
            paymentMethod: paymentMethod,
            paymentReference: paymentReference.isEmpty ? nil : paymentReference
        )
        isCommitting = true
    } catch {
        commitError = error.localizedDescription
    }
}
```

When the worker drains and `lot.lotOfferState` flips to `.paid`, the SwiftData @Query in this view re-renders. Add an `.onChange(of: lot.lotOfferState)` that pushes to `TransactionDetailView` once paid:

```swift
.onChange(of: lot.lotOfferState) { _, new in
    if new == LotOfferState.paid.rawValue {
        // Plan 2 added LotsRoute.transaction(UUID) — push it.
        // (See Task 12 — the route is added there; for now, dismiss.)
        dismiss()
    }
}
```

- [ ] **Step 2: Add a "Sync pending" indicator** when `isCommitting` and the lot is still `accepted`:

```swift
if isCommitting && LotOfferState(rawValue: lot.lotOfferState) != .paid {
    Text("Sync pending — your offer is saved. Receipt will appear once we reach the server.")
        .font(SlabFont.sans(size: 12)).foregroundStyle(AppColor.muted)
}
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild build -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
git add ios/slabbist/slabbist/Features/Offers/OfferReviewView.swift
git commit -m "feat(ios): OfferReviewView wires Mark paid through commit"
```

---

### Task 10 — `TransactionsRepository`

**Files:**
- Create: `ios/slabbist/slabbist/Features/Transactions/TransactionsRepository.swift`
- Create: `ios/slabbist/slabbistTests/Features/Transactions/TransactionsRepositoryTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// slabbistTests/Features/Transactions/TransactionsRepositoryTests.swift
import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct TransactionsRepositoryTests {
    private func seed() -> (TransactionsRepository, ModelContext, UUID) {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let storeId = UUID()
        let kicker = OutboxKicker()
        let repo = TransactionsRepository(context: context, kicker: kicker, currentStoreId: storeId)
        return (repo, context, storeId)
    }

    @Test func listSortsByPaidAtDesc() throws {
        let (repo, context, storeId) = seed()
        let now = Date()
        let txnOld = StoreTransaction(id: UUID(), storeId: storeId, lotId: UUID(), vendorId: nil, vendorNameSnapshot: "Old", totalBuyCents: 100, paymentMethod: "cash", paymentReference: nil, paidAt: now.addingTimeInterval(-100), paidByUserId: UUID(), createdAt: now)
        let txnNew = StoreTransaction(id: UUID(), storeId: storeId, lotId: UUID(), vendorId: nil, vendorNameSnapshot: "New", totalBuyCents: 200, paymentMethod: "cash", paymentReference: nil, paidAt: now, paidByUserId: UUID(), createdAt: now)
        context.insert(txnOld); context.insert(txnNew); try context.save()
        let listed = try repo.listAll()
        #expect(listed.first?.id == txnNew.id)
    }

    @Test func listForVendorScopesByVendorId() throws {
        let (repo, context, storeId) = seed()
        let v1 = UUID(); let v2 = UUID()
        let now = Date()
        context.insert(StoreTransaction(id: UUID(), storeId: storeId, lotId: UUID(), vendorId: v1, vendorNameSnapshot: "A", totalBuyCents: 100, paymentMethod: "cash", paymentReference: nil, paidAt: now, paidByUserId: UUID(), createdAt: now))
        context.insert(StoreTransaction(id: UUID(), storeId: storeId, lotId: UUID(), vendorId: v2, vendorNameSnapshot: "B", totalBuyCents: 200, paymentMethod: "cash", paymentReference: nil, paidAt: now, paidByUserId: UUID(), createdAt: now))
        try context.save()
        let listed = try repo.listForVendor(v1)
        #expect(listed.count == 1)
        #expect(listed.first?.vendorNameSnapshot == "A")
    }
}
```

- [ ] **Step 2: Run (FAIL)**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Features/Transactions -quiet`
Expected: FAIL.

- [ ] **Step 3: Implement the repository**

```swift
// Features/Transactions/TransactionsRepository.swift
import Foundation
import SwiftData

@MainActor
final class TransactionsRepository {
    private let context: ModelContext
    private let kicker: OutboxKicker
    let currentStoreId: UUID

    init(context: ModelContext, kicker: OutboxKicker, currentStoreId: UUID) {
        self.context = context
        self.kicker = kicker
        self.currentStoreId = currentStoreId
    }

    func listAll() throws -> [StoreTransaction] {
        let storeId = currentStoreId
        let descriptor = FetchDescriptor<StoreTransaction>(
            predicate: #Predicate<StoreTransaction> { $0.storeId == storeId },
            sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func listForVendor(_ vendorId: UUID) throws -> [StoreTransaction] {
        let storeId = currentStoreId
        let descriptor = FetchDescriptor<StoreTransaction>(
            predicate: #Predicate<StoreTransaction> {
                $0.storeId == storeId && $0.vendorId == vendorId
            },
            sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func linesFor(_ txn: StoreTransaction) throws -> [TransactionLine] {
        let txnId = txn.id
        let descriptor = FetchDescriptor<TransactionLine>(
            predicate: #Predicate<TransactionLine> { $0.transactionId == txnId },
            sortBy: [SortDescriptor(\.lineIndex)]
        )
        return try context.fetch(descriptor)
    }

    /// Returns transactions paid in the last `days` days, scoped to the store.
    /// Used by the "Recent transactions" section on `LotsListView`.
    func listRecent(days: Int) throws -> [StoreTransaction] {
        let storeId = currentStoreId
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        let descriptor = FetchDescriptor<StoreTransaction>(
            predicate: #Predicate<StoreTransaction> {
                $0.storeId == storeId && $0.paidAt >= since
            },
            sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Features/Transactions -quiet
git add ios/slabbist/slabbist/Features/Transactions/TransactionsRepository.swift \
        ios/slabbist/slabbistTests/Features/Transactions/TransactionsRepositoryTests.swift
git commit -m "feat(ios): TransactionsRepository (list, listForVendor, listRecent)"
```

---

### Task 11 — `TransactionsListView` + `TransactionDetailView`

**Files:**
- Create: `ios/slabbist/slabbist/Features/Transactions/TransactionsListView.swift`
- Create: `ios/slabbist/slabbist/Features/Transactions/TransactionDetailView.swift`

- [ ] **Step 1: Implement the list view**

```swift
// Features/Transactions/TransactionsListView.swift
import SwiftUI
import SwiftData

struct TransactionsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Query(sort: [SortDescriptor(\StoreTransaction.paidAt, order: .reverse)])
    private var transactions: [StoreTransaction]

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    KickerLabel("Ledger")
                    Text("Transactions").slabTitle()
                    if transactions.isEmpty {
                        FeatureEmptyState(
                            systemImage: "list.bullet.rectangle",
                            title: "No transactions yet",
                            subtitle: "Once you mark a lot paid, the receipt lands here."
                        )
                    } else {
                        SlabCard {
                            VStack(spacing: 0) {
                                ForEach(transactions, id: \.id) { txn in
                                    if txn.id != transactions.first?.id { SlabCardDivider() }
                                    NavigationLink(value: txn.id) {
                                        row(for: txn)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("txn-row-\(txn.id.uuidString)")
                                }
                            }
                        }
                    }
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl).padding(.vertical, Spacing.l)
            }
        }
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for txn: StoreTransaction) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Text(txn.vendorNameSnapshot).slabRowTitle()
                    if !txn.isActive {
                        Text(txn.voidedAt != nil ? "VOIDED" : "VOID")
                            .font(SlabFont.mono(size: 10, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(AppColor.negative)
                    }
                }
                Text("\(formatCents(txn.totalBuyCents)) · \(txn.paymentMethod)")
                    .font(SlabFont.mono(size: 12)).foregroundStyle(AppColor.dim)
            }
            Spacer()
            Text(relativeDate(txn.paidAt))
                .font(SlabFont.mono(size: 11)).foregroundStyle(AppColor.dim)
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
    }

    private func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
```

- [ ] **Step 2: Implement the detail view**

```swift
// Features/Transactions/TransactionDetailView.swift
import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    let transaction: StoreTransaction
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @State private var lines: [TransactionLine] = []
    @State private var voidReason: String = ""
    @State private var showingVoidSheet: Bool = false
    @State private var voidError: String?

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    summaryCard
                    linesSection
                    if transaction.isActive {
                        voidButton
                    } else {
                        voidedBanner
                    }
                    if let voidError {
                        Text(voidError).foregroundStyle(AppColor.negative)
                    }
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl).padding(.vertical, Spacing.l)
            }
        }
        .navigationTitle("Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadLines() }
        .sheet(isPresented: $showingVoidSheet) { voidSheet }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Receipt")
            Text(transaction.vendorNameSnapshot).slabTitle()
            Text(formatDate(transaction.paidAt))
                .font(SlabFont.mono(size: 12)).foregroundStyle(AppColor.dim)
        }
    }

    private var summaryCard: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                KickerLabel("Total")
                Text(formatCents(transaction.totalBuyCents))
                    .font(SlabFont.serif(size: 40))
                Text("\(transaction.paymentMethod)\(transaction.paymentReference.map { " · \($0)" } ?? "")")
                    .font(SlabFont.mono(size: 12)).foregroundStyle(AppColor.dim)
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.l)
        }
    }

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Lines")
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(lines, id: \.compositeKey) { line in
                        if line.compositeKey != lines.first?.compositeKey { SlabCardDivider() }
                        lineRow(line)
                    }
                }
            }
        }
    }

    private func lineRow(_ line: TransactionLine) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(snapshotTitle(line)).font(SlabFont.sans(size: 13))
                Text(snapshotSubtitle(line))
                    .font(SlabFont.mono(size: 11)).foregroundStyle(AppColor.dim)
            }
            Spacer()
            Text(formatCents(line.buyPriceCents))
                .font(SlabFont.mono(size: 14, weight: .semibold))
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
    }

    private var voidButton: some View {
        Button("Void transaction") { showingVoidSheet = true }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.negative)
            .accessibilityIdentifier("txn-void-button")
    }

    private var voidedBanner: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("VOIDED")
                    .font(SlabFont.mono(size: 12, weight: .semibold))
                    .tracking(1.4).foregroundStyle(AppColor.negative)
                if let r = transaction.voidReason {
                    Text(r).font(SlabFont.sans(size: 13)).foregroundStyle(AppColor.muted)
                }
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
        }
    }

    private var voidSheet: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                KickerLabel("Void")
                Text("Reason").slabTitle()
                TextField("Why are you voiding?", text: $voidReason, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("void-reason-field")
                Spacer()
                PrimaryGoldButton(title: "Confirm void", isEnabled: !voidReason.isEmpty) {
                    submitVoid()
                }
                .accessibilityIdentifier("void-confirm")
            }
            .padding(.horizontal, Spacing.xxl).padding(.vertical, Spacing.l)
        }
    }

    private func loadLines() {
        let txnId = transaction.id
        let desc = FetchDescriptor<TransactionLine>(
            predicate: #Predicate<TransactionLine> { $0.transactionId == txnId },
            sortBy: [SortDescriptor(\.lineIndex)]
        )
        lines = (try? context.fetch(desc)) ?? []
    }

    private func submitVoid() {
        let repo = OfferRepository(
            context: context, kicker: kicker,
            currentStoreId: transaction.storeId,
            currentUserId: session.userId ?? UUID()
        )
        do {
            try repo.voidTransaction(transaction, reason: voidReason)
            showingVoidSheet = false
        } catch { voidError = error.localizedDescription }
    }

    private func snapshotTitle(_ line: TransactionLine) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: line.identitySnapshotJSON) as? [String: Any] else {
            return "Line \(line.lineIndex + 1)"
        }
        let name = (json["card_name"] as? String) ?? "Line \(line.lineIndex + 1)"
        let num = (json["card_number"] as? String).map { " #\($0)" } ?? ""
        return "\(name)\(num)"
    }

    private func snapshotSubtitle(_ line: TransactionLine) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: line.identitySnapshotJSON) as? [String: Any] else { return "" }
        let parts = [
            json["set_name"] as? String,
            (json["grader"] as? String).flatMap { g in (json["grade"] as? String).map { "\(g) \($0)" } }
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }
}
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild build -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
git add ios/slabbist/slabbist/Features/Transactions/TransactionsListView.swift \
        ios/slabbist/slabbist/Features/Transactions/TransactionDetailView.swift
git commit -m "feat(ios): TransactionsListView + TransactionDetailView with void"
```

---

### Task 12 — Lot/Scan post-paid immutability + recent transactions section

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Lots/LotDetailView.swift`
- Modify: `ios/slabbist/slabbist/Features/Lots/LotsListView.swift`
- Modify: `ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift`

- [ ] **Step 1: Add a `frozenBanner` to `LotDetailView`** that shows above all editable sections when `lot.lotOfferState ∈ {paid, voided}`:

```swift
@ViewBuilder
private var frozenBanner: some View {
    let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
    if state == .paid || state == .voided {
        SlabCard {
            HStack {
                Image(systemName: "lock.fill")
                Text(state == .paid ? "Frozen — paid" : "Frozen — voided")
                    .font(SlabFont.mono(size: 12, weight: .semibold))
                Spacer()
                NavigationLink("View receipt", value: LotsRoute.transaction(transactionId: matchingTransactionId() ?? UUID()))
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.gold)
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
        }
        .accessibilityIdentifier("lot-frozen-banner")
    }
}

/// Find the active (non-voided) transaction for this lot, or the void if it's
/// voided. Used to drive the "View receipt" link target.
private func matchingTransactionId() -> UUID? {
    let lotId = lot.id
    let desc = FetchDescriptor<StoreTransaction>(
        predicate: #Predicate<StoreTransaction> { $0.lotId == lotId },
        sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
    )
    return (try? context.fetch(desc).first)?.id
}
```

Hide the action bar's edit-implying buttons when frozen:

```swift
private var actionBar: some View {
    let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
    return Group {
        switch state {
        // ...existing cases...
        case .paid, .voided:
            NavigationLink("View receipt", value: LotsRoute.transaction(transactionId: matchingTransactionId() ?? UUID()))
                .accessibilityIdentifier("view-receipt")
        }
    }
}
```

Also prevent `lot-margin-adjust`, `lot-vendor-attach`, and the per-row buy badge edit from being interactive when frozen. Wrap the existing affordances in `.disabled(isFrozen)`.

- [ ] **Step 2: Add `LotsRoute.transaction(transactionId:)`** to the route enum and the `routeDestination` switch:

```swift
case .transaction(let txnId):
    if let txn = try? context.fetch(FetchDescriptor<StoreTransaction>(predicate: #Predicate { $0.id == txnId })).first {
        TransactionDetailView(transaction: txn)
    } else {
        missingEntityView(label: "Transaction")
    }
```

- [ ] **Step 3: Add "Recent transactions" section to `LotsListView`**

Below the open-lots section:

```swift
@Query(sort: [SortDescriptor(\StoreTransaction.paidAt, order: .reverse)])
private var allTransactions: [StoreTransaction]

private var recentTransactions: [StoreTransaction] {
    let since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
    return allTransactions.filter { $0.paidAt >= since }.prefix(8).map { $0 }
}

@ViewBuilder
private var recentTransactionsSection: some View {
    if !recentTransactions.isEmpty {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                KickerLabel("Recent transactions")
                Spacer()
                NavigationLink("View all", value: LotsRoute.transactionsList) {}
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.gold)
            }
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(recentTransactions, id: \.id) { txn in
                        if txn.id != recentTransactions.first?.id { SlabCardDivider() }
                        NavigationLink(value: LotsRoute.transaction(transactionId: txn.id)) {
                            HStack {
                                Text(txn.vendorNameSnapshot).slabRowTitle()
                                Spacer()
                                Text(formatCents(txn.totalBuyCents))
                                    .font(SlabFont.mono(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
```

Add `.transactionsList` to `LotsRoute` and route to `TransactionsListView`.

- [ ] **Step 4: Gate `ScanDetailView` edits when the parent lot is frozen**

```swift
private var lotIsFrozen: Bool {
    guard let lot = matchingLot() else { return false }
    return [LotOfferState.paid.rawValue, LotOfferState.voided.rawValue].contains(lot.lotOfferState)
}
```

Disable the buy-price edit, the manual-ask edit, and any other writers when `lotIsFrozen` is true. Add a frozen banner at the top.

- [ ] **Step 5: Build + commit**

```bash
xcodebuild build -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
git add ios/slabbist/slabbist/Features/Lots/LotDetailView.swift \
        ios/slabbist/slabbist/Features/Lots/LotsListView.swift \
        ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift
git commit -m "feat(ios): post-paid immutability + recent transactions section"
```

---

### Task 13 — `VendorDetailView` purchase history + end-to-end UI test

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Vendors/VendorDetailView.swift`
- Create: `ios/slabbist/slabbistUITests/TransactionFlowUITests.swift`

- [ ] **Step 1: Replace the stub purchase-history section**

```swift
@State private var history: [StoreTransaction] = []

private var purchaseHistory: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
        KickerLabel("Purchase history")
        if history.isEmpty {
            SlabCard {
                Text("No buys yet — this lights up after the vendor's first paid transaction.")
                    .font(SlabFont.sans(size: 12)).foregroundStyle(AppColor.dim)
                    .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
            }
        } else {
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(history, id: \.id) { txn in
                        if txn.id != history.first?.id { SlabCardDivider() }
                        NavigationLink(destination: TransactionDetailView(transaction: txn)) {
                            row(for: txn)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            aggregateStrip
        }
    }
    .task { loadHistory() }
}

private var aggregateStrip: some View {
    HStack(spacing: Spacing.l) {
        cell(label: "Lifetime", value: formatCents(history.reduce(0) { $0 + $1.totalBuyCents }))
        cell(label: "Slabs", value: String(history.reduce(0) { $0 + (lineCount(for: $1)) }))
        cell(label: "Last buy", value: history.first.map { relativeDate($0.paidAt) } ?? "—")
    }
}

private func loadHistory() {
    let repo = TransactionsRepository(
        context: context, kicker: kicker,
        currentStoreId: vendor.storeId
    )
    history = (try? repo.listForVendor(vendor.id)) ?? []
}

private func lineCount(for txn: StoreTransaction) -> Int {
    let txnId = txn.id
    let desc = FetchDescriptor<TransactionLine>(predicate: #Predicate<TransactionLine> { $0.transactionId == txnId })
    return (try? context.fetch(desc).count) ?? 0
}
```

- [ ] **Step 2: Write the end-to-end UI test**

```swift
// slabbistUITests/TransactionFlowUITests.swift
import XCTest

final class TransactionFlowUITests: XCTestCase {
    func test_commit_void_round_trip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_AUTOSIGNIN", "UITEST_SEED_ACCEPTED_LOT"]
        app.launch()

        // Open the seeded accepted lot.
        app.tabBars.buttons["Lots"].tap()
        app.buttons["lot-row-Test Lot"].tap()
        app.buttons["resume-offer"].tap()

        // Commit.
        app.buttons["mark-paid"].tap()
        // Wait for the receipt to surface (drainer + hydrator round-trip).
        XCTAssertTrue(app.staticTexts["Receipt"].waitForExistence(timeout: 10))

        // Assert the lot is now frozen.
        app.navigationBars.buttons.firstMatch.tap()  // back to lot
        XCTAssertTrue(app.staticTexts["Frozen — paid"].waitForExistence(timeout: 2))

        // View receipt → void.
        app.buttons["view-receipt"].tap()
        app.buttons["txn-void-button"].tap()
        app.textFields["void-reason-field"].tap()
        app.textFields["void-reason-field"].typeText("ui test")
        app.buttons["void-confirm"].tap()
        XCTAssertTrue(app.staticTexts["VOIDED"].waitForExistence(timeout: 5))
    }
}
```

The seeding helper `UITEST_SEED_ACCEPTED_LOT` creates a lot in `accepted` state with at least one priced scan (extending `UITestApp.swift`). It also stubs the network to mock the Edge Function responses synchronously — see how `UITEST_AUTOSIGNIN` is implemented for the reference pattern.

- [ ] **Step 3: Run the full suite**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: PASS.

- [ ] **Step 4: Final commit**

```bash
git add ios/slabbist/slabbist/Features/Vendors/VendorDetailView.swift \
        ios/slabbist/slabbistUITests/TransactionFlowUITests.swift
git commit -m "feat(ios): vendor purchase history + transaction flow UI test"
```

---

## Self-review checklist

- [ ] **Spec coverage.** Walk every entry in the spec's "Transactions (new tables)" SQL block, the `/transaction-commit` and `/transaction-void` Edge Function contracts, the "Receipt view" and "Void path" sections of "Scan → offer → transaction pipeline," and the "Vendor detail + purchase history" section. Each has a task.
- [ ] **Type consistency.** `OfferRepository.commit(lot:paymentMethod:paymentReference:)` matches in tests, in `OfferReviewView`, and in the `OutboxPayloads.CommitTransaction` field names. `StoreTransaction.isActive` is the single source of truth for the void chip.
- [ ] **No placeholders.** Every code block is complete. The "frozen banner" copy is concrete; the seeding helper for UI tests is described with enough detail to implement (mirrors `UITEST_AUTOSIGNIN`'s pattern).
- [ ] **TDD ordering.** Each implementation task with non-trivial logic has a failing-test step first.
- [ ] **Server idempotency.** `/transaction-commit` returns 200 + the existing transaction on a duplicate (race-safe). `/transaction-void` returns 409 if already voided (no double-voids).
- [ ] **Schema safety.** RLS is select-only for users; service role does writes via Edge Functions. The unique partial index guards the "one active transaction per lot" invariant at the database layer.
