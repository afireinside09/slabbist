# Store Workflow — Plan 1: Vendor DB Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Operators can create, edit, archive, and pick vendors scoped to their store, fully offline-first via the existing outbox. The vendor record is the foundation for Plan 2 (attaching a vendor to a lot's offer) and Plan 3 (vendor purchase history). At the end of this plan, vendors are usable as a standalone CRUD surface — no offer or transaction integration yet.

**Architecture:** New `vendors` table with `pg_trgm`-backed fuzzy search, RLS scoped by `store_id` via the existing `is_store_member()` helper. iOS gets a `Vendor` SwiftData model, two new outbox kinds (`upsertVendor`, `archiveVendor`), a `VendorsRepository` that mirrors the existing `LotsViewModel` outbox-write pattern, and four screens (`VendorsListView`, `VendorDetailView`, `VendorEditSheet`, `VendorPicker`) wired into a new "Vendors" entry under the Settings tab.

**Tech Stack:**
- iOS: Swift 6, SwiftUI, SwiftData, Swift Testing (unit), XCUITest (UI)
- Backend: Postgres 15 (Supabase), `pg_trgm` extension, pgTAP for RLS tests

**Spec reference:** [`docs/superpowers/specs/2026-05-08-store-workflow-design.md`](../specs/2026-05-08-store-workflow-design.md). This plan implements the **Vendors** sub-section (Postgres schema + iOS surfaces) plus the `stores.default_margin_pct` column (foundational for Plan 2).

**Branch strategy:** Execute on a feature branch or worktree. Commits per task; messages reference "Store WF Plan 1 / Task N".

---

## File structure

```
supabase/
├── migrations/
│   ├── 20260509130000_pg_trgm_and_default_margin.sql   # (T1)
│   ├── 20260509130100_vendors_table.sql                # (T2)
│   └── 20260509130200_vendors_rls.sql                  # (T2)
└── tests/
    └── rls_vendors.sql                                  # (T3)

ios/slabbist/slabbist/
├── Core/
│   ├── Models/
│   │   ├── Store.swift                                  # (T1)  add `defaultMarginPct`
│   │   └── Vendor.swift                                 # (T4)  NEW @Model
│   ├── Persistence/
│   │   ├── ModelContainer.swift                         # (T4)  add Vendor.self
│   │   └── Outbox/
│   │       ├── OutboxKind.swift                         # (T5)  add upsertVendor, archiveVendor
│   │       └── OutboxPayloads.swift                     # (T5)  add UpsertVendor, ArchiveVendor
│   └── Sync/
│       └── OutboxDrainer.swift                          # (T5)  dispatch the new kinds
├── Features/
│   ├── Vendors/                                         # (T6–T9) NEW folder
│   │   ├── VendorsRepository.swift                      # (T6)
│   │   ├── VendorsViewModel.swift                       # (T6)
│   │   ├── VendorEditSheet.swift                        # (T7)
│   │   ├── VendorPicker.swift                           # (T8)
│   │   ├── VendorsListView.swift                        # (T9)
│   │   └── VendorDetailView.swift                       # (T9)
│   └── Settings/
│       └── SettingsView.swift                           # (T10) add a "Vendors" row
└── slabbistApp.swift                                    # (T10) register VendorsRoute (if needed)

ios/slabbist/slabbistTests/
├── Core/
│   ├── Models/
│   │   └── VendorTests.swift                            # (T4)
│   └── Persistence/
│       └── OutboxKindTests.swift                        # (T5)  add cases
└── Features/
    └── Vendors/                                         # NEW folder
        ├── VendorsRepositoryTests.swift                 # (T6)
        └── VendorEditSheetParseTests.swift              # (T7)

ios/slabbist/slabbistUITests/
└── VendorsFlowUITests.swift                             # (T10)
```

---

## Tasks

### Task 1 — Migration: pg_trgm + `stores.default_margin_pct`

**Files:**
- Create: `supabase/migrations/20260509130000_pg_trgm_and_default_margin.sql`
- Modify: `ios/slabbist/slabbist/Core/Models/Store.swift`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260509130000_pg_trgm_and_default_margin.sql
--
-- Foundation for sub-project #6: enables `pg_trgm` for vendor fuzzy search
-- (used by Plan 1's `VendorPicker`) and adds `stores.default_margin_pct`
-- so each new lot can snapshot the store's default offer percentage.
-- See spec: docs/superpowers/specs/2026-05-08-store-workflow-design.md#stores-existing-table--column-added

create extension if not exists pg_trgm;

alter table stores
  add column default_margin_pct numeric(5,4) not null default 0.6000
  check (default_margin_pct >= 0 and default_margin_pct <= 1);

comment on column stores.default_margin_pct is
  'Per-store default offer pct (0..1). Snapshotted to lots.margin_pct_snapshot at lot creation.';
```

- [ ] **Step 2: Apply the migration locally**

Run: `supabase db reset` (or `supabase migration up` if the local stack already has prior migrations applied).
Expected: migration applies cleanly; existing stores all have `default_margin_pct = 0.6000`.

- [ ] **Step 3: Add the matching SwiftData property**

Modify `ios/slabbist/slabbist/Core/Models/Store.swift`. Add the property and an init parameter (with default for backward compat in any constructor call sites):

```swift
@Model
final class Store {
    @Attribute(.unique) var id: UUID
    var ownerUserId: UUID
    var name: String
    var defaultMarginPct: Double  // NEW — 0.0...1.0; mirrors stores.default_margin_pct
    var createdAt: Date

    init(
        id: UUID,
        ownerUserId: UUID,
        name: String,
        defaultMarginPct: Double = 0.6,
        createdAt: Date
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.name = name
        self.defaultMarginPct = defaultMarginPct
        self.createdAt = createdAt
    }
}
```

(If the existing `Store.swift` already has additional properties or a different shape, preserve them — only add the new property + init arg. SwiftData lightweight migration handles the new column when a default is supplied.)

- [ ] **Step 4: Run unit tests to confirm nothing else broke**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Core/Models -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260509130000_pg_trgm_and_default_margin.sql \
        ios/slabbist/slabbist/Core/Models/Store.swift
git commit -m "feat(db,ios): add pg_trgm + stores.default_margin_pct"
```

---

### Task 2 — Migration: `vendors` table + RLS

**Files:**
- Create: `supabase/migrations/20260509130100_vendors_table.sql`
- Create: `supabase/migrations/20260509130200_vendors_rls.sql`

- [ ] **Step 1: Write the table migration**

```sql
-- supabase/migrations/20260509130100_vendors_table.sql
--
-- Vendors directory scoped per store. Soft-archive (no hard delete) because
-- analytics needs the row even after a vendor stops doing business.

create type contact_method as enum ('phone', 'email', 'instagram', 'in_person', 'other');

create table vendors (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references stores(id) on delete cascade,
  display_name text not null,
  contact_method contact_method,
  contact_value text,
  notes text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index vendors_store_id on vendors(store_id);
create index vendors_store_active on vendors(store_id) where archived_at is null;
create index vendors_display_name_trgm on vendors using gin (display_name gin_trgm_ops);

comment on table vendors is
  'Per-store vendor directory. Soft-archive only.';
comment on column vendors.archived_at is
  'Soft-archive timestamp; non-null hides the row from active pickers but keeps it for ledger reads.';
```

- [ ] **Step 2: Write the RLS migration**

```sql
-- supabase/migrations/20260509130200_vendors_rls.sql
--
-- Vendors are tenant data; reuse the `is_store_member()` helper defined in
-- `20260422000006_rls_policies.sql`. No DELETE policy — archive only.

alter table vendors enable row level security;

create policy vendors_select_members
  on vendors for select
  using (is_store_member(store_id));

create policy vendors_insert_members
  on vendors for insert
  with check (is_store_member(store_id));

create policy vendors_update_members
  on vendors for update
  using (is_store_member(store_id))
  with check (is_store_member(store_id));
```

- [ ] **Step 3: Apply migrations and confirm**

Run: `supabase migration up` (or `supabase db reset` if working from a clean slate).
Expected: both files apply, no errors, `\d vendors` in `psql` shows the table + indexes + policies.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260509130100_vendors_table.sql \
        supabase/migrations/20260509130200_vendors_rls.sql
git commit -m "feat(db): add vendors table with per-store RLS"
```

---

### Task 3 — RLS test for vendors

**Files:**
- Create: `supabase/tests/rls_vendors.sql`

- [ ] **Step 1: Write the failing pgTAP test**

```sql
-- supabase/tests/rls_vendors.sql
--
-- pgTAP coverage for vendors RLS: store-A user can CRUD their own vendors,
-- store-B user cannot read or write store-A's vendors. Mirrors the pattern
-- in supabase/tests/rls_tenant_isolation.sql.

begin;
select plan(7);

create extension if not exists pgtap;

insert into auth.users (id, email, aud, role)
values
  ('00000000-0000-0000-0000-0000000000a1', 'a@vendors.test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b1', 'b@vendors.test', 'authenticated', 'authenticated');

-- Triggers from 20260422000007_signup_bootstrap.sql have already created a
-- store + owner membership for each user. Capture both store ids before
-- switching roles so the cross-tenant probe below has a valid id to attack.
create temporary table _store_ids on commit drop as
select owner_user_id, id as store_id from stores;
grant select on _store_ids to authenticated;

set local role authenticated;

-- USER A: insert + select
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

select lives_ok($$
  insert into vendors (store_id, display_name, contact_method, contact_value)
  select store_id, 'Acme Cards', 'phone', '555-0100'
  from _store_ids
  where owner_user_id = '00000000-0000-0000-0000-0000000000a1';
$$, 'A can insert a vendor in their own store');

select is((select count(*)::int from vendors), 1, 'A sees exactly one vendor');

-- USER B: cannot see A's vendors
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);

select is((select count(*)::int from vendors), 0, 'B sees zero vendors (RLS isolates)');

-- USER B: cannot insert into A's store
select throws_ok($$
  insert into vendors (store_id, display_name)
  select store_id, 'Sneaky'
  from _store_ids
  where owner_user_id = '00000000-0000-0000-0000-0000000000a1';
$$, NULL, 'B cannot insert a vendor into A''s store');

-- USER B: their own insert lives
select lives_ok($$
  insert into vendors (store_id, display_name)
  select store_id, 'B Vendor'
  from _store_ids
  where owner_user_id = '00000000-0000-0000-0000-0000000000b1';
$$, 'B can insert their own vendor');

-- USER B: cannot update A's vendor (returns 0 rows updated under RLS, no row matches USING)
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);

select is((
  with upd as (
    update vendors set display_name = 'pwned'
    where display_name = 'Acme Cards'
    returning 1
  )
  select count(*)::int from upd
), 0, 'B cannot update A''s vendor (RLS USING filters it out)');

-- USER A: archive (soft delete) works
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

select is((
  with upd as (
    update vendors set archived_at = now()
    where display_name = 'Acme Cards'
    returning 1
  )
  select count(*)::int from upd
), 1, 'A can archive their own vendor');

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `supabase test db`
Expected: `rls_vendors`: 7/7 PASS.

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/rls_vendors.sql
git commit -m "test(db): pgTAP coverage for vendors RLS"
```

---

### Task 4 — `Vendor` SwiftData model + ModelContainer wire-up

**Files:**
- Create: `ios/slabbist/slabbist/Core/Models/Vendor.swift`
- Modify: `ios/slabbist/slabbist/Core/Persistence/ModelContainer.swift`
- Create: `ios/slabbist/slabbistTests/Core/Models/VendorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// slabbistTests/Core/Models/VendorTests.swift
import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct VendorTests {
    @Test func insertAndFetchVendor() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let storeId = UUID()
        let vendor = Vendor(
            id: UUID(),
            storeId: storeId,
            displayName: "Acme Cards",
            contactMethod: "phone",
            contactValue: "555-0100",
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        context.insert(vendor)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Vendor>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.displayName == "Acme Cards")
        #expect(fetched.first?.archivedAt == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Core/Models/VendorTests -quiet`
Expected: FAIL — `Vendor` is not defined.

- [ ] **Step 3: Implement the model**

```swift
// Core/Models/Vendor.swift
import Foundation
import SwiftData

@Model
final class Vendor {
    @Attribute(.unique) var id: UUID
    var storeId: UUID
    var displayName: String
    /// Mirrors Postgres `contact_method` enum string; one of:
    /// "phone" | "email" | "instagram" | "in_person" | "other".
    /// Optional because contact info may be unknown at first capture.
    var contactMethod: String?
    var contactValue: String?
    var notes: String?
    /// Soft-archive timestamp. Active vendors have `archivedAt == nil`;
    /// archived vendors are excluded from pickers but readable for history.
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        storeId: UUID,
        displayName: String,
        contactMethod: String? = nil,
        contactValue: String? = nil,
        notes: String? = nil,
        archivedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.storeId = storeId
        self.displayName = displayName
        self.contactMethod = contactMethod
        self.contactValue = contactValue
        self.notes = notes
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 4: Wire `Vendor` into the model container**

Modify `ios/slabbist/slabbist/Core/Persistence/ModelContainer.swift`. Add `Vendor.self` to **both** `Schema` arrays — the persistent one and the in-memory one:

```swift
let schema = Schema([
    Store.self,
    StoreMember.self,
    Lot.self,
    Scan.self,
    Vendor.self,                  // ← add
    OutboxItem.self,
    GradedCardIdentity.self,
    GradedMarketSnapshot.self
])
```

(Repeat in `inMemory()`.)

- [ ] **Step 5: Run the test again to verify it passes**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Core/Models/VendorTests -quiet`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/slabbist/slabbist/Core/Models/Vendor.swift \
        ios/slabbist/slabbist/Core/Persistence/ModelContainer.swift \
        ios/slabbist/slabbistTests/Core/Models/VendorTests.swift
git commit -m "feat(ios): Vendor SwiftData model + container wire-up"
```

---

### Task 5 — New OutboxKinds: `upsertVendor`, `archiveVendor`

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxKind.swift`
- Modify: `ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxPayloads.swift`
- Modify: `ios/slabbist/slabbist/Core/Sync/OutboxDrainer.swift`
- Modify: `ios/slabbist/slabbistTests/Core/Persistence/OutboxKindTests.swift` (or create if absent)

- [ ] **Step 1: Write the failing test for the kinds + priorities**

In `slabbistTests/Core/OutboxItemTests.swift` (existing) or a new `OutboxKindTests.swift`:

```swift
import Testing
@testable import slabbist

struct OutboxKindStoreWorkflowTests {
    @Test func vendorKindsExistWithExpectedPriorities() {
        // Vendor writes are below scan/lot writes (less time-sensitive than
        // a slab landing) but above background recomputes.
        #expect(OutboxKind.upsertVendor.priority < OutboxKind.insertScan.priority)
        #expect(OutboxKind.archiveVendor.priority == OutboxKind.upsertVendor.priority)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Core/OutboxItemTests -quiet`
Expected: FAIL — `upsertVendor`, `archiveVendor` not defined.

- [ ] **Step 3: Add the new kinds**

Modify `OutboxKind.swift`:

```swift
nonisolated enum OutboxKind: String, Codable, CaseIterable {
    case insertScan
    case updateScan
    case updateScanOffer
    case deleteScan
    case insertLot
    case updateLot
    case deleteLot
    case certLookupJob
    case priceCompJob
    case upsertVendor          // ← add
    case archiveVendor         // ← add

    nonisolated var priority: Int {
        switch self {
        case .deleteScan:       return 50
        case .deleteLot:        return 50
        case .certLookupJob:    return 40
        case .priceCompJob:     return 30
        case .insertScan:       return 20
        case .insertLot:        return 15
        case .updateScan:       return 10
        case .updateScanOffer:  return 10
        case .updateLot:        return 5
        case .upsertVendor:     return 8     // ← below lots/scans, above .updateLot
        case .archiveVendor:    return 8
        }
    }
}
```

- [ ] **Step 4: Add the matching payloads**

Modify `OutboxPayloads.swift`. Append:

```swift
nonisolated extension OutboxPayloads {
    /// Insert-or-update for a vendor row. Sent on every save from the
    /// edit sheet — server-side resolves create vs update via `id`.
    struct UpsertVendor: Codable {
        let id: String
        let store_id: String
        let display_name: String
        let contact_method: String?
        let contact_value: String?
        let notes: String?
        let archived_at: String?      // null until archived; included so a
                                      // re-activate (clear) round-trips correctly
        let updated_at: String
    }

    /// Archive (soft-delete) a vendor. We could reuse `UpsertVendor` with
    /// `archived_at != nil`, but the dedicated payload makes the intent
    /// obvious in logs and lets the worker pick a different priority/dedup
    /// strategy if needed.
    struct ArchiveVendor: Codable {
        let id: String
        let archived_at: String
    }
}
```

- [ ] **Step 5: Wire the kinds through `OutboxDrainer`**

Modify `OutboxDrainer.swift`. Find the `switch` that dispatches on `kind` and add cases:

```swift
case .upsertVendor:
    let payload = try JSONDecoder().decode(OutboxPayloads.UpsertVendor.self, from: item.payload)
    try await client.from("vendors").upsert(payload, onConflict: "id").execute()
    return .success
case .archiveVendor:
    let payload = try JSONDecoder().decode(OutboxPayloads.ArchiveVendor.self, from: item.payload)
    try await client.from("vendors")
        .update(["archived_at": payload.archived_at])
        .eq("id", value: payload.id)
        .execute()
    return .success
```

(If the drainer's actual API differs — e.g., uses a custom request builder rather than the Supabase Swift SDK directly — match the existing pattern for `.insertLot` / `.insertScan`.)

- [ ] **Step 6: Run all outbox tests**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Core -quiet`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxKind.swift \
        ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxPayloads.swift \
        ios/slabbist/slabbist/Core/Sync/OutboxDrainer.swift \
        ios/slabbist/slabbistTests/Core/OutboxItemTests.swift
git commit -m "feat(ios): outbox kinds for upsert/archive vendor"
```

---

### Task 6 — `VendorsRepository` + `VendorsViewModel` + unit tests

**Files:**
- Create: `ios/slabbist/slabbist/Features/Vendors/VendorsRepository.swift`
- Create: `ios/slabbist/slabbist/Features/Vendors/VendorsViewModel.swift`
- Create: `ios/slabbist/slabbistTests/Features/Vendors/VendorsRepositoryTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// slabbistTests/Features/Vendors/VendorsRepositoryTests.swift
import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct VendorsRepositoryTests {
    private func makeRepo() -> (VendorsRepository, ModelContext, UUID) {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let storeId = UUID()
        let kicker = OutboxKicker()  // existing nonisolated type
        let repo = VendorsRepository(context: context, kicker: kicker, currentStoreId: storeId)
        return (repo, context, storeId)
    }

    @Test func upsertCreatesVendorAndOutboxItem() throws {
        let (repo, context, _) = makeRepo()
        let vendor = try repo.upsert(
            id: nil,
            displayName: "Acme",
            contactMethod: "phone",
            contactValue: "555-0100",
            notes: nil
        )
        #expect(vendor.displayName == "Acme")
        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.contains(where: { $0.kind == .upsertVendor }))
    }

    @Test func upsertUpdatesExistingByIdAndDoesNotDuplicate() throws {
        let (repo, context, _) = makeRepo()
        let v1 = try repo.upsert(id: nil, displayName: "Acme", contactMethod: nil, contactValue: nil, notes: nil)
        _ = try repo.upsert(id: v1.id, displayName: "Acme Cards LLC", contactMethod: "email", contactValue: "x@y", notes: nil)
        let vendors = try context.fetch(FetchDescriptor<Vendor>())
        #expect(vendors.count == 1)
        #expect(vendors.first?.displayName == "Acme Cards LLC")
        #expect(vendors.first?.contactMethod == "email")
    }

    @Test func archiveSetsArchivedAtAndEnqueuesItem() throws {
        let (repo, context, _) = makeRepo()
        let v = try repo.upsert(id: nil, displayName: "Acme", contactMethod: nil, contactValue: nil, notes: nil)
        try repo.archive(v)
        #expect(v.archivedAt != nil)
        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.contains(where: { $0.kind == .archiveVendor }))
    }

    @Test func listActiveExcludesArchived() throws {
        let (repo, _, _) = makeRepo()
        let active = try repo.upsert(id: nil, displayName: "Active", contactMethod: nil, contactValue: nil, notes: nil)
        let archived = try repo.upsert(id: nil, displayName: "Archived", contactMethod: nil, contactValue: nil, notes: nil)
        try repo.archive(archived)
        let listed = try repo.listActive()
        #expect(listed.contains(where: { $0.id == active.id }))
        #expect(!listed.contains(where: { $0.id == archived.id }))
    }

    @Test func listActiveSortsByDisplayNameAscending() throws {
        let (repo, _, _) = makeRepo()
        _ = try repo.upsert(id: nil, displayName: "Zeta", contactMethod: nil, contactValue: nil, notes: nil)
        _ = try repo.upsert(id: nil, displayName: "Alpha", contactMethod: nil, contactValue: nil, notes: nil)
        let listed = try repo.listActive()
        #expect(listed.first?.displayName == "Alpha")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Features/Vendors -quiet`
Expected: FAIL — `VendorsRepository` not defined.

- [ ] **Step 3: Implement `VendorsRepository`**

```swift
// Features/Vendors/VendorsRepository.swift
import Foundation
import SwiftData

@MainActor
final class VendorsRepository {
    private let context: ModelContext
    private let kicker: OutboxKicker
    let currentStoreId: UUID

    init(context: ModelContext, kicker: OutboxKicker, currentStoreId: UUID) {
        self.context = context
        self.kicker = kicker
        self.currentStoreId = currentStoreId
    }

    @discardableResult
    func upsert(
        id: UUID?,
        displayName: String,
        contactMethod: String?,
        contactValue: String?,
        notes: String?
    ) throws -> Vendor {
        let now = Date()
        let resolvedId = id ?? UUID()
        // Try fetch existing.
        let predicate = #Predicate<Vendor> { $0.id == resolvedId }
        let existing = try context.fetch(FetchDescriptor<Vendor>(predicate: predicate)).first
        let vendor: Vendor
        if let existing {
            existing.displayName = displayName
            existing.contactMethod = contactMethod
            existing.contactValue = contactValue
            existing.notes = notes
            existing.updatedAt = now
            vendor = existing
        } else {
            vendor = Vendor(
                id: resolvedId,
                storeId: currentStoreId,
                displayName: displayName,
                contactMethod: contactMethod,
                contactValue: contactValue,
                notes: notes,
                createdAt: now,
                updatedAt: now
            )
            context.insert(vendor)
        }
        try enqueueUpsert(vendor)
        try context.save()
        kicker.kick()
        return vendor
    }

    func archive(_ vendor: Vendor) throws {
        let now = Date()
        vendor.archivedAt = now
        vendor.updatedAt = now
        let payload = OutboxPayloads.ArchiveVendor(
            id: vendor.id.uuidString,
            archived_at: ISO8601DateFormatter.shared.string(from: now)
        )
        let item = OutboxItem(
            id: UUID(),
            kind: .archiveVendor,
            payload: try JSONEncoder().encode(payload),
            status: .pending,
            attempts: 0,
            createdAt: now,
            nextAttemptAt: now
        )
        context.insert(item)
        try context.save()
        kicker.kick()
    }

    func listActive() throws -> [Vendor] {
        let storeId = currentStoreId
        let descriptor = FetchDescriptor<Vendor>(
            predicate: #Predicate<Vendor> { $0.storeId == storeId && $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.displayName, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func listArchived() throws -> [Vendor] {
        let storeId = currentStoreId
        let descriptor = FetchDescriptor<Vendor>(
            predicate: #Predicate<Vendor> { $0.storeId == storeId && $0.archivedAt != nil },
            sortBy: [SortDescriptor(\.displayName, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func reactivate(_ vendor: Vendor) throws {
        vendor.archivedAt = nil
        vendor.updatedAt = Date()
        try enqueueUpsert(vendor)
        try context.save()
        kicker.kick()
    }

    // MARK: - Outbox encoding

    private func enqueueUpsert(_ v: Vendor) throws {
        let payload = OutboxPayloads.UpsertVendor(
            id: v.id.uuidString,
            store_id: v.storeId.uuidString,
            display_name: v.displayName,
            contact_method: v.contactMethod,
            contact_value: v.contactValue,
            notes: v.notes,
            archived_at: v.archivedAt.map { ISO8601DateFormatter.shared.string(from: $0) },
            updated_at: ISO8601DateFormatter.shared.string(from: v.updatedAt)
        )
        let item = OutboxItem(
            id: UUID(),
            kind: .upsertVendor,
            payload: try JSONEncoder().encode(payload),
            status: .pending,
            attempts: 0,
            createdAt: Date(),
            nextAttemptAt: Date()
        )
        context.insert(item)
    }
}
```

- [ ] **Step 4: Implement `VendorsViewModel` (thin wrapper for views)**

```swift
// Features/Vendors/VendorsViewModel.swift
import Foundation
import SwiftData

@MainActor
@Observable
final class VendorsViewModel {
    private let repo: VendorsRepository
    private(set) var active: [Vendor] = []
    private(set) var archived: [Vendor] = []

    init(repo: VendorsRepository) {
        self.repo = repo
    }

    static func resolve(context: ModelContext, kicker: OutboxKicker, session: SessionStore) -> VendorsViewModel? {
        guard let userId = session.userId else { return nil }
        let ownerId = userId
        var descriptor = FetchDescriptor<Store>(
            predicate: #Predicate<Store> { $0.ownerUserId == ownerId }
        )
        descriptor.fetchLimit = 1
        guard let store = try? context.fetch(descriptor).first else { return nil }
        let repo = VendorsRepository(context: context, kicker: kicker, currentStoreId: store.id)
        return VendorsViewModel(repo: repo)
    }

    func refresh() {
        active = (try? repo.listActive()) ?? []
        archived = (try? repo.listArchived()) ?? []
    }

    @discardableResult
    func upsert(id: UUID?, displayName: String, contactMethod: String?, contactValue: String?, notes: String?) throws -> Vendor {
        let v = try repo.upsert(id: id, displayName: displayName, contactMethod: contactMethod, contactValue: contactValue, notes: notes)
        refresh()
        return v
    }

    func archive(_ vendor: Vendor) throws {
        try repo.archive(vendor)
        refresh()
    }

    func reactivate(_ vendor: Vendor) throws {
        try repo.reactivate(vendor)
        refresh()
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Features/Vendors -quiet`
Expected: PASS (5/5).

- [ ] **Step 6: Commit**

```bash
git add ios/slabbist/slabbist/Features/Vendors/VendorsRepository.swift \
        ios/slabbist/slabbist/Features/Vendors/VendorsViewModel.swift \
        ios/slabbist/slabbistTests/Features/Vendors/VendorsRepositoryTests.swift
git commit -m "feat(ios): VendorsRepository + ViewModel with outbox writes"
```

---

### Task 7 — `VendorEditSheet`

**Files:**
- Create: `ios/slabbist/slabbist/Features/Vendors/VendorEditSheet.swift`
- Create: `ios/slabbist/slabbistTests/Features/Vendors/VendorEditSheetParseTests.swift`

- [ ] **Step 1: Write the failing parse-helper test**

The sheet has two non-trivial helpers worth testing in isolation: trimming the display name and validating that contact_value matches contact_method shape.

```swift
// slabbistTests/Features/Vendors/VendorEditSheetParseTests.swift
import Testing
@testable import slabbist

struct VendorEditSheetParseTests {
    @Test func trimsDisplayName() {
        #expect(VendorEditSheet.normalize(displayName: "  Acme  ") == "Acme")
    }

    @Test func rejectsEmptyDisplayName() {
        #expect(VendorEditSheet.normalize(displayName: "   ") == nil)
    }
}
```

- [ ] **Step 2: Run the test (will fail — type doesn't exist)**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Features/Vendors/VendorEditSheetParseTests -quiet`
Expected: FAIL.

- [ ] **Step 3: Implement the sheet**

```swift
// Features/Vendors/VendorEditSheet.swift
import SwiftUI

/// Sheet for creating or editing a vendor. Mirrors the visual language of
/// `ManualPriceSheet` (existing in Features/Scanning).
struct VendorEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: Vendor?
    let onSave: (UUID?, String, String?, String?, String?) throws -> Void

    @State private var displayName: String = ""
    @State private var contactMethod: String = "phone"
    @State private var contactValue: String = ""
    @State private var notes: String = ""
    @State private var error: String?

    private static let methods = ["phone", "email", "instagram", "in_person", "other"]

    init(initial: Vendor?, onSave: @escaping (UUID?, String, String?, String?, String?) throws -> Void) {
        self.initial = initial
        self.onSave = onSave
        _displayName = State(initialValue: initial?.displayName ?? "")
        _contactMethod = State(initialValue: initial?.contactMethod ?? "phone")
        _contactValue = State(initialValue: initial?.contactValue ?? "")
        _notes = State(initialValue: initial?.notes ?? "")
    }

    /// Public so unit tests can exercise the trim + empty-rejection rule.
    static func normalize(displayName: String) -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                topBar
                header
                form
                if let error {
                    Text(error)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.negative)
                        .accessibilityIdentifier("vendor-edit-error")
                }
                Spacer()
                PrimaryGoldButton(
                    title: initial == nil ? "Save vendor" : "Update vendor",
                    isEnabled: Self.normalize(displayName: displayName) != nil
                ) { submit() }
                .accessibilityIdentifier("vendor-edit-save")
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
    }

    private var topBar: some View {
        HStack {
            SecondaryIconButton(systemIcon: "xmark", accessibilityLabel: "Cancel") { dismiss() }
            Spacer()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel(initial == nil ? "New vendor" : "Edit vendor")
            Text(initial?.displayName ?? "Add a vendor").slabTitle()
        }
    }

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            field(label: "Display name", text: $displayName, identifier: "vendor-edit-name")
            Picker("Contact method", selection: $contactMethod) {
                ForEach(Self.methods, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("vendor-edit-method")
            field(label: "Contact value", text: $contactValue, identifier: "vendor-edit-value")
            field(label: "Notes", text: $notes, identifier: "vendor-edit-notes")
        }
    }

    private func field(label: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            KickerLabel(label)
            SlabCard {
                TextField(label, text: text)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
                    .accessibilityIdentifier(identifier)
            }
        }
    }

    private func submit() {
        guard let name = Self.normalize(displayName: displayName) else {
            error = "Enter a display name."
            return
        }
        do {
            try onSave(
                initial?.id,
                name,
                contactMethod,
                contactValue.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                notes.trimmingCharacters(in: .whitespaces).nilIfEmpty
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Features/Vendors/VendorEditSheetParseTests -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Vendors/VendorEditSheet.swift \
        ios/slabbist/slabbistTests/Features/Vendors/VendorEditSheetParseTests.swift
git commit -m "feat(ios): VendorEditSheet for create/edit"
```

---

### Task 8 — `VendorPicker`

**Files:**
- Create: `ios/slabbist/slabbist/Features/Vendors/VendorPicker.swift`

- [ ] **Step 1: Implement the picker**

```swift
// Features/Vendors/VendorPicker.swift
import SwiftUI
import SwiftData

/// Sheet that lets the operator pick a vendor (or create a new one).
/// Used by Plan 2's `LotDetailView` "Attach vendor" affordance, but
/// shipped here so it can be unit-tested independently.
struct VendorPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Vendor> { $0.archivedAt == nil },
           sort: [SortDescriptor(\Vendor.displayName)])
    private var allActive: [Vendor]
    @State private var search: String = ""
    @State private var creatingNew: Bool = false

    let storeId: UUID
    let onPick: (Vendor) -> Void
    let onCreate: (UUID?, String, String?, String?, String?) throws -> Vendor

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.l) {
                topBar
                searchField
                list
                Spacer()
                newButton
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .sheet(isPresented: $creatingNew) {
            VendorEditSheet(initial: nil) { id, name, method, value, notes in
                let created = try onCreate(id, name, method, value, notes)
                onPick(created)
                dismiss()
            }
        }
    }

    private var topBar: some View {
        HStack {
            SecondaryIconButton(systemIcon: "xmark", accessibilityLabel: "Cancel") { dismiss() }
            Spacer()
        }
    }

    private var searchField: some View {
        SlabCard {
            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppColor.dim)
                TextField("Search vendors", text: $search)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("vendor-picker-search")
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
        }
    }

    /// Active vendors filtered by the search text, scoped to the store.
    /// We'd use `pg_trgm` server-side for the same fuzzy match in larger
    /// vendor sets, but client-side substring is sufficient for the
    /// per-store list (typical vendor count: <500).
    private var filtered: [Vendor] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        let scoped = allActive.filter { $0.storeId == storeId }
        if trimmed.isEmpty { return scoped }
        return scoped.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    private var list: some View {
        SlabCard {
            VStack(spacing: 0) {
                if filtered.isEmpty {
                    Text(search.isEmpty ? "No vendors yet" : "No matches for \"\(search)\"")
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.dim)
                        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.l)
                } else {
                    ForEach(filtered, id: \.id) { vendor in
                        if vendor.id != filtered.first?.id { SlabCardDivider() }
                        Button {
                            onPick(vendor)
                            dismiss()
                        } label: {
                            HStack {
                                Text(vendor.displayName).slabRowTitle()
                                Spacer()
                                if let v = vendor.contactValue {
                                    Text(v).font(SlabFont.mono(size: 12))
                                        .foregroundStyle(AppColor.dim)
                                }
                            }
                            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("vendor-pick-\(vendor.displayName)")
                    }
                }
            }
        }
    }

    private var newButton: some View {
        PrimaryGoldButton(title: "+ New vendor", systemIcon: "plus") {
            creatingNew = true
        }
        .accessibilityIdentifier("vendor-picker-new")
    }
}
```

- [ ] **Step 2: Build and confirm there are no compile errors**

Run: `xcodebuild build -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/Vendors/VendorPicker.swift
git commit -m "feat(ios): VendorPicker sheet"
```

---

### Task 9 — `VendorsListView` + `VendorDetailView`

**Files:**
- Create: `ios/slabbist/slabbist/Features/Vendors/VendorsListView.swift`
- Create: `ios/slabbist/slabbist/Features/Vendors/VendorDetailView.swift`

- [ ] **Step 1: Implement `VendorsListView`**

```swift
// Features/Vendors/VendorsListView.swift
import SwiftUI
import SwiftData

struct VendorsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @State private var viewModel: VendorsViewModel?
    @State private var editingVendor: Vendor?
    @State private var presentingNew: Bool = false

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    PrimaryGoldButton(
                        title: "New vendor",
                        systemIcon: "plus",
                        isEnabled: viewModel != nil
                    ) { presentingNew = true }
                    .accessibilityIdentifier("vendor-list-new")
                    activeSection
                    archivedSection
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationTitle("Vendors")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.userId) {
            viewModel = VendorsViewModel.resolve(context: context, kicker: kicker, session: session)
            viewModel?.refresh()
        }
        .sheet(isPresented: $presentingNew) {
            if let viewModel {
                VendorEditSheet(initial: nil) { id, name, method, value, notes in
                    try viewModel.upsert(id: id, displayName: name, contactMethod: method, contactValue: value, notes: notes)
                }
            }
        }
        .sheet(item: $editingVendor) { vendor in
            if let viewModel {
                VendorEditSheet(initial: vendor) { id, name, method, value, notes in
                    try viewModel.upsert(id: id, displayName: name, contactMethod: method, contactValue: value, notes: notes)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Contacts")
            Text("Vendors").slabTitle()
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        if let viewModel, !viewModel.active.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                KickerLabel("Active")
                SlabCard {
                    VStack(spacing: 0) {
                        ForEach(viewModel.active, id: \.id) { vendor in
                            if vendor.id != viewModel.active.first?.id { SlabCardDivider() }
                            row(for: vendor)
                        }
                    }
                }
            }
        } else if viewModel != nil {
            FeatureEmptyState(
                systemImage: "person.2",
                title: "No vendors yet",
                subtitle: "Add a vendor to track buys and surface contact details when you start a lot.",
                steps: ["Tap New vendor.", "Save once and they're picker-ready forever."]
            )
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        if let viewModel, !viewModel.archived.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                KickerLabel("Archived")
                SlabCard {
                    VStack(spacing: 0) {
                        ForEach(viewModel.archived, id: \.id) { vendor in
                            if vendor.id != viewModel.archived.first?.id { SlabCardDivider() }
                            row(for: vendor)
                        }
                    }
                }
            }
        }
    }

    private func row(for vendor: Vendor) -> some View {
        NavigationLink(value: vendor.id) {
            HStack(alignment: .center, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(vendor.displayName).slabRowTitle()
                    if let v = vendor.contactValue {
                        Text(v).font(SlabFont.mono(size: 12)).foregroundStyle(AppColor.dim)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12)).foregroundStyle(AppColor.dim)
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vendor-row-\(vendor.displayName)")
    }
}
```

- [ ] **Step 2: Implement `VendorDetailView`**

```swift
// Features/Vendors/VendorDetailView.swift
import SwiftUI
import SwiftData

struct VendorDetailView: View {
    let vendor: Vendor
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @State private var viewModel: VendorsViewModel?
    @State private var editing: Bool = false

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    contactCard
                    purchaseHistoryStub
                    actionsCard
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationTitle(vendor.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.userId) {
            viewModel = VendorsViewModel.resolve(context: context, kicker: kicker, session: session)
        }
        .sheet(isPresented: $editing) {
            if let viewModel {
                VendorEditSheet(initial: vendor) { id, name, method, value, notes in
                    try viewModel.upsert(id: id, displayName: name, contactMethod: method, contactValue: value, notes: notes)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Vendor")
            Text(vendor.displayName).slabTitle()
            if vendor.archivedAt != nil {
                Text("Archived").font(SlabFont.mono(size: 11)).foregroundStyle(AppColor.dim)
            }
        }
    }

    private var contactCard: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                KickerLabel("Contact")
                Text(vendor.contactMethod ?? "—").font(SlabFont.mono(size: 13))
                Text(vendor.contactValue ?? "no contact").font(SlabFont.sans(size: 14))
                if let notes = vendor.notes, !notes.isEmpty {
                    SlabCardDivider()
                    Text(notes).font(SlabFont.sans(size: 13)).foregroundStyle(AppColor.muted)
                }
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
        }
    }

    /// Plan 3 fills this with the actual transaction list. Kept stubbed so
    /// the UI shape is settled and the empty state copy is locked in.
    private var purchaseHistoryStub: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                KickerLabel("Purchase history")
                Text("No buys yet — purchase history lights up after this vendor's first paid transaction.")
                    .font(SlabFont.sans(size: 12)).foregroundStyle(AppColor.dim)
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
        }
    }

    private var actionsCard: some View {
        VStack(spacing: Spacing.m) {
            PrimaryGoldButton(title: "Edit vendor", systemIcon: "pencil") { editing = true }
                .accessibilityIdentifier("vendor-detail-edit")
            if vendor.archivedAt == nil {
                Button("Archive vendor") {
                    try? viewModel?.archive(vendor)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.negative)
                .accessibilityIdentifier("vendor-detail-archive")
            } else {
                Button("Reactivate vendor") {
                    try? viewModel?.reactivate(vendor)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.gold)
                .accessibilityIdentifier("vendor-detail-reactivate")
            }
        }
    }
}
```

- [ ] **Step 3: Build to confirm compile**

Run: `xcodebuild build -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ios/slabbist/slabbist/Features/Vendors/VendorsListView.swift \
        ios/slabbist/slabbist/Features/Vendors/VendorDetailView.swift
git commit -m "feat(ios): VendorsListView + VendorDetailView"
```

---

### Task 10 — Wire Vendors entry into Settings + UI test

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Settings/SettingsView.swift` (existing)
- Create: `ios/slabbist/slabbistUITests/VendorsFlowUITests.swift`

- [ ] **Step 1: Add a "Vendors" navigation row to Settings**

Open `SettingsView.swift`. Find the existing list/sections and add a row that pushes `VendorsListView`:

```swift
// Inside the existing SettingsView body, in the appropriate Section:
NavigationLink {
    VendorsListView()
} label: {
    Label("Vendors", systemImage: "person.2")
}
.accessibilityIdentifier("settings-vendors-row")
```

If `SettingsView` uses a different navigation idiom (e.g., a typed `Route` enum rather than `NavigationLink { destination }`), match that pattern. The destination must hand `VendorsListView` the same `@Environment` values it needs (`SessionStore`, `OutboxKicker`, `\.modelContext`) — those are already injected at the app root for the Lots tab and the Settings tab inherits them.

- [ ] **Step 2: Add the within-detail navigation destination**

Inside `VendorsListView`'s `NavigationStack` (or whatever stack wraps the Settings tab — match the existing pattern):

```swift
.navigationDestination(for: UUID.self) { vendorId in
    if let vendor = try? context.fetch(
        FetchDescriptor<Vendor>(predicate: #Predicate { $0.id == vendorId })
    ).first {
        VendorDetailView(vendor: vendor)
    } else {
        Text("Vendor no longer available").foregroundStyle(AppColor.dim)
    }
}
```

- [ ] **Step 3: Write the UI test (failing — destination doesn't render yet)**

```swift
// slabbistUITests/VendorsFlowUITests.swift
import XCTest

final class VendorsFlowUITests: XCTestCase {
    func test_create_edit_archive_vendor_flow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_AUTOSIGNIN"]    // pattern from existing UI tests
        app.launch()

        // Open Settings tab → Vendors row.
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings-vendors-row"].tap()

        // Create a vendor.
        app.buttons["vendor-list-new"].tap()
        let nameField = app.textFields["vendor-edit-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Acme Cards")
        app.buttons["vendor-edit-save"].tap()

        // Row exists, tap into detail.
        let row = app.buttons["vendor-row-Acme Cards"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.tap()

        // Archive.
        app.buttons["vendor-detail-archive"].tap()

        // Back out and confirm row is now under Archived.
        app.navigationBars.buttons.firstMatch.tap()  // back
        XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 2))
    }
}
```

- [ ] **Step 4: Run the UI test**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistUITests/VendorsFlowUITests/test_create_edit_archive_vendor_flow -quiet`
Expected: PASS.

- [ ] **Step 5: Run the full unit + UI suite to catch regressions**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: PASS across all suites. If any pre-existing UI test fails because of the new Settings row reorder, update its accessibility identifier; do not delete the test.

- [ ] **Step 6: Final commit**

```bash
git add ios/slabbist/slabbist/Features/Settings/SettingsView.swift \
        ios/slabbist/slabbistUITests/VendorsFlowUITests.swift
git commit -m "feat(ios): wire Vendors into Settings + end-to-end UI test"
```

---

## Self-review checklist (run after Task 10 completes)

- [ ] **Spec coverage.** Walk through the spec's "Vendors (new table)" SQL block, "SwiftData mirrors" `Vendor` definition, "Vendor flow" section, and the "RLS" entries for vendors. Every column, every CRUD path, every RLS policy has a task. Purchase history is intentionally stubbed — it depends on Plan 3's `transactions` table.
- [ ] **Type consistency.** `VendorsRepository.upsert(id:displayName:contactMethod:contactValue:notes:)` signature is identical in the test, the impl, and the view-model wrapper. `OutboxKind.upsertVendor` is the same string everywhere.
- [ ] **No placeholders.** Every code block contains complete code; no "TODO" or "implement later". The `purchase history stub` in `VendorDetailView` is intentionally a stub with explanatory comment, not a placeholder for missing implementation.
- [ ] **TDD ordering.** Each implementation task has a failing-test step before the impl step.
- [ ] **Commits.** Each task ends with a single commit; nothing slips between tasks uncommitted.

## What's next

After Plan 1 lands and is verified, **Plan 2 (Offer pricing)** picks up:
- Lot column extensions: `vendor_id`, `vendor_name_snapshot`, `margin_pct_snapshot`, `lot_offer_state`.
- `scans.offer_cents → vendor_ask_cents` rename + new `scans.buy_price_cents`.
- `/lot-offer-recompute` Edge Function.
- `OfferRepository` (pricing surface), `LotDetailView` extensions (vendor strip, margin slider, per-scan badges), and `OfferReviewView` up to the "accepted" state — no commit yet.

After Plan 2, **Plan 3 (Transactions)** lands the immutable ledger and the receipt/void surfaces.
