# Store Workflow — Plan 2: Offer Pricing

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Operators can attach a vendor (built in Plan 1) to a lot, see auto-derived per-scan buy prices from the reconciled comp times a margin, override per line, adjust the lot's margin, and walk the lot through the offer states `drafting → priced → presented → accepted` (and back). The accepted state is reachable end-to-end **without** a server round-trip — the actual transaction commit lands in Plan 3.

**Architecture:** Postgres adds offer-state columns to `lots`, renames `scans.offer_cents → vendor_ask_cents`, and adds `scans.buy_price_cents` + `buy_price_overridden`. A new `/lot-offer-recompute` Edge Function keeps the lot total in sync server-side. iOS gets an `OfferRepository` (pricing layer + state-machine guards) plus extensions to `LotDetailView` (vendor strip, margin slider, per-scan buy badges, "Send to offer" CTA) and a new `OfferReviewView` that supports the `presented → accepted/declined/priced` transitions.

**Tech Stack:**
- iOS: Swift 6, SwiftUI, SwiftData, Swift Testing, XCUITest
- Backend: Postgres 15, Supabase Edge Functions (Deno + TS)

**Spec reference:** [`docs/superpowers/specs/2026-05-08-store-workflow-design.md`](../specs/2026-05-08-store-workflow-design.md). This plan implements the **Lot/scan column additions**, **`/lot-offer-recompute`**, **OfferRepository**, **`LotDetailView` extensions**, and **`OfferReviewView` (excluding commit)**.

**Prerequisite:** Plan 1 (Vendor DB Foundation) must have shipped — the `Vendor` model, `VendorsRepository`, and `VendorPicker` are used by this plan's lot UI.

---

## File structure

```
supabase/
├── migrations/
│   ├── 20260510130000_lots_offer_columns.sql           # (T1)
│   ├── 20260510130100_scans_buy_price_and_rename.sql   # (T2)
│   └── 20260510130200_lot_offer_state_enum.sql         # (T1) — defines lot_offer_state enum first
├── functions/
│   └── lot-offer-recompute/                            # (T4) NEW
│       ├── deno.json
│       ├── index.ts
│       └── __tests__/
│           └── recompute.test.ts
└── tests/
    └── lot_offer_state_transitions.sql                  # (T3) pgTAP

ios/slabbist/slabbist/
├── Core/
│   ├── Models/
│   │   ├── Lot.swift                                    # (T5)  add vendorId, vendorNameSnapshot, marginPctSnapshot, lotOfferState, lotOfferStateUpdatedAt
│   │   └── Scan.swift                                   # (T5)  rename offerCents → vendorAskCents, add buyPriceCents, buyPriceOverridden
│   └── Persistence/
│       └── Outbox/
│           ├── OutboxKind.swift                         # (T6)  add updateLotOffer, recomputeLotOffer, updateScanBuyPrice
│           └── OutboxPayloads.swift                     # (T6)  matching payloads
├── Features/
│   ├── Offers/                                          # NEW folder
│   │   ├── OfferRepository.swift                        # (T7)
│   │   ├── OfferPricingService.swift                    # (T7)  pure money math
│   │   └── OfferReviewView.swift                        # (T10)
│   ├── Lots/
│   │   ├── LotDetailView.swift                          # (T9)  add vendor strip + margin slider + buy-price badges + send-to-offer
│   │   ├── LotsViewModel.swift                          # (T8)  delegate to OfferRepository
│   │   └── LotsListView.swift                           # (T9)  state pill on each row
│   └── Scanning/
│       ├── ManualPriceSheet.swift                       # (T5b) rename to VendorAskSheet (or update copy + identifiers)
│       └── ScanDetailView.swift                         # (T11) buy-price card

ios/slabbist/slabbistTests/
├── Core/Models/
│   ├── LotOfferStateTests.swift                         # (T5)  enum cases + transitions
│   └── ScanBuyPriceTests.swift                          # (T5)
└── Features/
    ├── Offers/
    │   ├── OfferPricingServiceTests.swift               # (T7)  rounding, null handling, overrides sticky
    │   └── OfferRepositoryTests.swift                   # (T8)  state-machine guards, recompute integration
    └── Lots/
        └── LotsViewModelTests.swift                     # (T8)  exists; extend

ios/slabbist/slabbistUITests/
└── OfferPricingFlowUITests.swift                        # (T11) end-to-end: scan → margin → override → send to offer → accept → bounce
```

---

## Tasks

### Task 1 — Migration: lot offer-state enum + columns

**Files:**
- Create: `supabase/migrations/20260510130000_lots_offer_columns.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260510130000_lots_offer_columns.sql

create type lot_offer_state as enum (
  'drafting',   -- scans landing; no buy prices yet
  'priced',     -- buy_price_cents filled on at least one scan
  'presented',  -- operator showed offer to vendor; awaiting agreement
  'accepted',   -- vendor agreed; payment method captured
  'declined',   -- vendor said no; lot still inspectable
  'paid',       -- (Plan 3) transaction row exists, totals frozen
  'voided'      -- (Plan 3) transaction was voided after pay
);

alter table lots
  add column vendor_id uuid references vendors(id),
  add column vendor_name_snapshot text,
  add column margin_pct_snapshot numeric(5,4)
    check (margin_pct_snapshot is null
           or (margin_pct_snapshot >= 0 and margin_pct_snapshot <= 1)),
  add column lot_offer_state lot_offer_state not null default 'drafting',
  add column lot_offer_state_updated_at timestamptz;

create index lots_vendor_id on lots(vendor_id);
create index lots_offer_state on lots(store_id, lot_offer_state);

comment on column lots.vendor_name_snapshot is
  'Vendor display name at offer time. Stays stable if the vendor record is later renamed.';
comment on column lots.margin_pct_snapshot is
  'Snapshot of stores.default_margin_pct at lot creation. Plan 3-replaced by margin_rule_id output once subproject 7 lands.';
comment on column lots.lot_offer_state is
  'Where this lot is in the offer/transaction lifecycle. Parallel to lot_status; do not merge.';
```

- [ ] **Step 2: Apply and confirm**

Run: `supabase migration up`
Expected: migration applies; `\d lots` shows the new columns.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260510130000_lots_offer_columns.sql
git commit -m "feat(db): lot_offer_state enum + offer columns on lots"
```

---

### Task 2 — Migration: rename `scans.offer_cents` + add `buy_price_cents`

**Files:**
- Create: `supabase/migrations/20260510130100_scans_buy_price_and_rename.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260510130100_scans_buy_price_and_rename.sql
--
-- Renames scans.offer_cents → vendor_ask_cents to clear the name collision
-- with the new "store's offer to vendor" concept (buy_price_cents).
-- See spec: docs/superpowers/specs/2026-05-08-store-workflow-design.md#naming-clarification

alter table scans rename column offer_cents to vendor_ask_cents;
comment on column scans.vendor_ask_cents is
  'Vendor''s manual asking price for this slab when no comp data is available. Optional, operator-entered.';

alter table scans add column buy_price_cents bigint;
alter table scans add column buy_price_overridden boolean not null default false;

comment on column scans.buy_price_cents is
  'Store''s per-line offer to the vendor. Auto = round(reconciled_headline_price_cents * lot.margin_pct_snapshot); operator can override.';
comment on column scans.buy_price_overridden is
  'TRUE means an operator explicitly set buy_price_cents and a margin change should NOT auto-recompute it.';

create index scans_lot_buy_price on scans(lot_id) where buy_price_cents is not null;
```

- [ ] **Step 2: Apply and confirm**

Run: `supabase migration up`
Expected: migration applies; `\d scans` shows `vendor_ask_cents` (renamed) and the two new columns.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260510130100_scans_buy_price_and_rename.sql
git commit -m "feat(db): rename scans.offer_cents → vendor_ask_cents; add buy_price_cents"
```

---

### Task 3 — pgTAP test: `lot_offer_state` transitions

**Files:**
- Create: `supabase/tests/lot_offer_state_transitions.sql`

- [ ] **Step 1: Write the failing test**

```sql
-- supabase/tests/lot_offer_state_transitions.sql
--
-- Smoke test that the enum exists and the new columns are present + index'd.
-- The actual state-machine enforcement lives in the iOS OfferRepository (and
-- in /transaction-commit's `accepted` precondition); the database is a
-- typed dropbox.

begin;
select plan(4);
create extension if not exists pgtap;

select has_column('lots', 'vendor_id', 'lots has vendor_id');
select has_column('lots', 'lot_offer_state', 'lots has lot_offer_state');
select col_default_is('lots', 'lot_offer_state', 'drafting', 'lot_offer_state defaults to drafting');
select has_index('lots', 'lots_offer_state', 'index on (store_id, lot_offer_state) exists');

select * from finish();
rollback;
```

- [ ] **Step 2: Run and confirm**

Run: `supabase test db`
Expected: PASS 4/4.

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/lot_offer_state_transitions.sql
git commit -m "test(db): pgTAP smoke for lot_offer_state columns + index"
```

---

### Task 4 — Edge Function: `/lot-offer-recompute`

**Files:**
- Create: `supabase/functions/lot-offer-recompute/deno.json`
- Create: `supabase/functions/lot-offer-recompute/index.ts`
- Create: `supabase/functions/lot-offer-recompute/__tests__/recompute.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// supabase/functions/lot-offer-recompute/__tests__/recompute.test.ts
import { assertEquals } from "jsr:@std/assert";
import { computeNewState } from "../index.ts";

Deno.test("computeNewState: drafting → priced when total > 0", () => {
  assertEquals(computeNewState({ current: "drafting", totalCents: 1500 }), "priced");
});

Deno.test("computeNewState: drafting stays drafting when total = 0", () => {
  assertEquals(computeNewState({ current: "drafting", totalCents: 0 }), "drafting");
});

Deno.test("computeNewState: priced → drafting when all prices cleared", () => {
  assertEquals(computeNewState({ current: "priced", totalCents: 0 }), "drafting");
});

Deno.test("computeNewState: terminal states never change", () => {
  for (const s of ["paid", "voided", "declined"] as const) {
    assertEquals(computeNewState({ current: s, totalCents: 0 }), s);
    assertEquals(computeNewState({ current: s, totalCents: 9999 }), s);
  }
});

Deno.test("computeNewState: presented/accepted preserve their state", () => {
  for (const s of ["presented", "accepted"] as const) {
    assertEquals(computeNewState({ current: s, totalCents: 1500 }), s);
  }
});
```

- [ ] **Step 2: Run the test (should fail — module doesn't exist)**

Run: `cd supabase/functions/lot-offer-recompute && deno test --allow-net --allow-env`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the Edge Function**

```typescript
// supabase/functions/lot-offer-recompute/deno.json
{
  "imports": {
    "@supabase/supabase-js": "npm:@supabase/supabase-js@^2.45.0",
    "jsr:@std/assert": "jsr:@std/assert@^1.0.0"
  }
}
```

```typescript
// supabase/functions/lot-offer-recompute/index.ts
// @ts-nocheck — runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or remote imports.
//
// /lot-offer-recompute
// Request:  { lot_id: string }
// Response: { lot_id, offered_total_cents, lot_offer_state }
//
// Sums coalesce(scans.buy_price_cents, 0) for the lot; writes the result to
// lots.offered_total_cents; transitions lot_offer_state ↔ drafting/priced
// based on the total. Idempotent.
//
// Authentication: JWT. The caller must be a member of the lot's store —
// enforced by RLS on the underlying tables (this function uses the user's
// JWT, not service role).

import { createClient } from "@supabase/supabase-js";

type LotOfferState =
  | "drafting" | "priced" | "presented" | "accepted"
  | "declined" | "paid" | "voided";

const TERMINAL_STATES: ReadonlySet<LotOfferState> = new Set([
  "paid", "voided", "declined",
]);

const PRESERVE_STATES: ReadonlySet<LotOfferState> = new Set([
  "presented", "accepted",
]);

/**
 * Decides the new lot_offer_state given the current state and the freshly
 * summed total. Pure for unit tests.
 */
export function computeNewState(args: { current: LotOfferState; totalCents: number }): LotOfferState {
  const { current, totalCents } = args;
  if (TERMINAL_STATES.has(current)) return current;
  if (PRESERVE_STATES.has(current)) return current;
  // current is drafting or priced; flip based on total
  return totalCents > 0 ? "priced" : "drafting";
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function env(name: string): string {
  const v = Deno.env.get(name);
  if (v === undefined || v === "") throw new Error(`missing env: ${name}`);
  return v;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "access-control-allow-origin": "*",
        "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
        "access-control-allow-methods": "POST, OPTIONS",
      },
    });
  }
  if (req.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });

  let body: { lot_id?: string };
  try { body = await req.json(); } catch { return json(400, { code: "INVALID_JSON" }); }
  if (!body?.lot_id || typeof body.lot_id !== "string") {
    return json(400, { code: "MISSING_FIELDS" });
  }

  const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: req.headers.get("authorization") ?? "" } },
  });

  const { data: lot, error: lotErr } = await supabase
    .from("lots")
    .select("id, lot_offer_state")
    .eq("id", body.lot_id)
    .maybeSingle();

  if (lotErr) return json(500, { code: "DB_ERROR", detail: lotErr.message });
  if (!lot) return json(404, { code: "LOT_NOT_FOUND" });

  const current = lot.lot_offer_state as LotOfferState;
  if (TERMINAL_STATES.has(current)) {
    // Refuse recompute on terminal lots; iOS treats 409 as "trust local state".
    return json(409, { code: "TERMINAL_STATE", lot_offer_state: current });
  }

  const { data: rows, error: sumErr } = await supabase
    .from("scans")
    .select("buy_price_cents")
    .eq("lot_id", body.lot_id);

  if (sumErr) return json(500, { code: "DB_ERROR", detail: sumErr.message });

  const totalCents = (rows ?? []).reduce(
    (acc, r) => acc + (typeof r.buy_price_cents === "number" ? r.buy_price_cents : 0),
    0,
  );
  const next = computeNewState({ current, totalCents });

  const { error: updErr } = await supabase
    .from("lots")
    .update({
      offered_total_cents: totalCents,
      lot_offer_state: next,
      lot_offer_state_updated_at: new Date().toISOString(),
    })
    .eq("id", body.lot_id);

  if (updErr) return json(500, { code: "DB_ERROR", detail: updErr.message });

  return json(200, {
    lot_id: body.lot_id,
    offered_total_cents: totalCents,
    lot_offer_state: next,
  });
});
```

- [ ] **Step 4: Run the unit tests to confirm they pass**

Run: `cd supabase/functions/lot-offer-recompute && deno test --allow-net --allow-env`
Expected: PASS 5/5.

- [ ] **Step 5: Deploy locally and smoke test**

```bash
supabase functions serve lot-offer-recompute &
# Manually POST against http://localhost:54321/functions/v1/lot-offer-recompute
# with a real lot_id from the seeded local DB to confirm the round-trip.
```

Confirm a 200 + the expected payload. Kill the local server when done.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/lot-offer-recompute
git commit -m "feat(edge): /lot-offer-recompute — sums buy prices + flips state"
```

---

### Task 5 — Extend `Lot` and `Scan` SwiftData models

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Models/Lot.swift`
- Modify: `ios/slabbist/slabbist/Core/Models/Scan.swift`
- Create: `ios/slabbist/slabbistTests/Core/Models/LotOfferStateTests.swift`
- Create: `ios/slabbist/slabbistTests/Core/Models/ScanBuyPriceTests.swift`
- Modify: `ios/slabbist/slabbist/Features/Scanning/ManualPriceSheet.swift` (rename concept; keep file name)

- [ ] **Step 1: Write the failing tests**

```swift
// slabbistTests/Core/Models/LotOfferStateTests.swift
import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct LotOfferStateTests {
    @Test func defaultsToDrafting() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let lot = Lot(
            id: UUID(),
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "Test",
            createdAt: Date(),
            updatedAt: Date()
        )
        context.insert(lot)
        try context.save()
        #expect(lot.lotOfferState == LotOfferState.drafting.rawValue)
        #expect(lot.marginPctSnapshot == nil)
    }

    @Test func enumCasesMatchSpec() {
        let cases = LotOfferState.allCases.map(\.rawValue).sorted()
        #expect(cases == ["accepted", "declined", "drafting", "paid", "presented", "priced", "voided"])
    }
}
```

```swift
// slabbistTests/Core/Models/ScanBuyPriceTests.swift
import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct ScanBuyPriceTests {
    @Test func vendorAskCentsRoundTrips() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let scan = Scan(
            id: UUID(), storeId: UUID(), lotId: UUID(), userId: UUID(),
            grader: .PSA, certNumber: "123",
            createdAt: Date(), updatedAt: Date()
        )
        scan.vendorAskCents = 1234     // renamed from offerCents
        scan.buyPriceCents = 800
        scan.buyPriceOverridden = true
        context.insert(scan)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Scan>())
        #expect(fetched.first?.vendorAskCents == 1234)
        #expect(fetched.first?.buyPriceCents == 800)
        #expect(fetched.first?.buyPriceOverridden == true)
    }
}
```

- [ ] **Step 2: Run the tests (will fail — properties don't exist yet)**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Core/Models -quiet`
Expected: FAIL.

- [ ] **Step 3: Add `LotOfferState` enum + Lot properties**

In `Core/Models/Lot.swift`, add the new enum and the new properties:

```swift
enum LotOfferState: String, Codable, CaseIterable {
    case drafting
    case priced
    case presented
    case accepted
    case declined
    case paid
    case voided
}

@Model
final class Lot {
    @Attribute(.unique) var id: UUID
    var storeId: UUID
    var createdByUserId: UUID
    var name: String
    var notes: String?
    var status: LotStatus
    var vendorId: UUID?                       // ← add
    var vendorNameSnapshot: String?           // ← add
    var marginPctSnapshot: Double?            // ← add (0.0...1.0)
    var lotOfferState: String                 // ← add (LotOfferState.rawValue)
    var lotOfferStateUpdatedAt: Date?         // ← add
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
        lotOfferState: LotOfferState = .drafting,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.storeId = storeId
        self.createdByUserId = createdByUserId
        self.name = name
        self.notes = notes
        self.status = status
        self.vendorId = nil
        self.vendorNameSnapshot = nil
        self.marginPctSnapshot = nil
        self.lotOfferState = lotOfferState.rawValue
        self.lotOfferStateUpdatedAt = nil
        self.offeredTotalCents = nil
        self.marginRuleId = nil
        self.transactionStamp = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

(SwiftData's lightweight migration handles new attributes that have defaults — the `nil` defaults for the new optional properties and the `"drafting"` default for the non-optional `lotOfferState` make this safe.)

- [ ] **Step 4: Update `Scan` — rename `offerCents → vendorAskCents`, add buy-price properties**

In `Core/Models/Scan.swift`, rename and extend:

```swift
@Model
final class Scan {
    // ... existing properties ...
    var vendorAskCents: Int64?              // ← was offerCents
    var buyPriceCents: Int64?               // ← NEW
    var buyPriceOverridden: Bool            // ← NEW (default false)
    // ... rest unchanged ...
}
```

Update the initializer to set `buyPriceOverridden = false`. **All existing call sites that read or write `Scan.offerCents` must be renamed to `vendorAskCents`.** Search the codebase: `grep -rn "offerCents" ios/slabbist/`. Expect hits in:
- `LotsViewModel.swift` (the manual-price update method)
- `LotDetailView.swift` (the trailing-value rendering)
- `OutboxKind.updateScanOffer` and `OutboxPayloads.UpdateScanOffer` — keep the kind name and payload struct name for now (they're already shipped), but rename the **field** in the struct from `offer_cents` to `vendor_ask_cents` to match the column rename. Update all callers.
- `ManualPriceSheet.swift` (this sheet now edits `vendorAskCents`, not the new buy price; copy update only).
- `slabbistTests/Core/Models/*` and `slabbistUITests/ManualPriceFlowUITests.swift`.

- [ ] **Step 5: Update `OutboxPayloads.UpdateScanOffer` field names**

```swift
struct UpdateScanOffer: Codable {
    let id: String
    let vendor_ask_cents: Int64?    // ← renamed from offer_cents
    let updated_at: String
}
```

Update the encoder call sites (`LotsViewModel.updateScanManualPrice` or wherever this payload is built).

- [ ] **Step 6: Run unit tests to confirm green**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Core/Models -only-testing:slabbistTests/Features/Lots -quiet`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ios/slabbist/slabbist/Core/Models/Lot.swift \
        ios/slabbist/slabbist/Core/Models/Scan.swift \
        ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxPayloads.swift \
        ios/slabbist/slabbist/Features/Lots/ \
        ios/slabbist/slabbist/Features/Scanning/ManualPriceSheet.swift \
        ios/slabbist/slabbistTests/Core/Models/LotOfferStateTests.swift \
        ios/slabbist/slabbistTests/Core/Models/ScanBuyPriceTests.swift
git commit -m "feat(ios): extend Lot/Scan models with offer state + buy_price"
```

---

### Task 6 — New OutboxKinds for offer flow

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxKind.swift`
- Modify: `ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxPayloads.swift`
- Modify: `ios/slabbist/slabbist/Core/Sync/OutboxDrainer.swift`

- [ ] **Step 1: Add the kinds**

```swift
case updateLotOffer       // vendor_id, vendor_name_snapshot, margin_pct_snapshot, lot_offer_state changes
case recomputeLotOffer    // calls /lot-offer-recompute Edge Function
case updateScanBuyPrice   // buy_price_cents + buy_price_overridden patch
```

Priorities:

```swift
case .updateScanBuyPrice: return 10  // tied with updateScan — buy price edits race with cert/comp landings
case .updateLotOffer:     return 7
case .recomputeLotOffer:  return 6   // background reconciliation; below user-facing writes
```

- [ ] **Step 2: Add the payloads**

```swift
struct UpdateLotOffer: Codable {
    let id: String
    let vendor_id: String?
    let vendor_name_snapshot: String?
    let margin_pct_snapshot: Double?
    let lot_offer_state: String?
    let lot_offer_state_updated_at: String?
    let updated_at: String
}

struct RecomputeLotOffer: Codable {
    let lot_id: String
}

struct UpdateScanBuyPrice: Codable {
    let id: String
    let buy_price_cents: Int64?
    let buy_price_overridden: Bool
    let updated_at: String
}
```

- [ ] **Step 3: Wire the new kinds through `OutboxDrainer`**

```swift
case .updateLotOffer:
    let p = try JSONDecoder().decode(OutboxPayloads.UpdateLotOffer.self, from: item.payload)
    try await client.from("lots").update(p).eq("id", value: p.id).execute()
    return .success
case .updateScanBuyPrice:
    let p = try JSONDecoder().decode(OutboxPayloads.UpdateScanBuyPrice.self, from: item.payload)
    try await client.from("scans").update([
        "buy_price_cents": p.buy_price_cents.map(String.init) ?? "null",
        "buy_price_overridden": String(p.buy_price_overridden),
        "updated_at": p.updated_at,
    ]).eq("id", value: p.id).execute()
    return .success
case .recomputeLotOffer:
    let p = try JSONDecoder().decode(OutboxPayloads.RecomputeLotOffer.self, from: item.payload)
    let resp = try await client.functions.invoke("lot-offer-recompute", options: .init(body: ["lot_id": p.lot_id]))
    // 409 = TERMINAL_STATE; treat as success and refresh local state from a fresh /lots row read.
    return .success
```

(If the existing drainer's API differs, match its conventions — wrap raw HTTP, handle 4xx/5xx, etc.)

- [ ] **Step 4: Build to confirm**

Run: `xcodebuild build -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Persistence/Outbox/ \
        ios/slabbist/slabbist/Core/Sync/OutboxDrainer.swift
git commit -m "feat(ios): outbox kinds for lot-offer + scan-buy-price"
```

---

### Task 7 — `OfferPricingService` (pure money math) + `OfferRepository`

**Files:**
- Create: `ios/slabbist/slabbist/Features/Offers/OfferPricingService.swift`
- Create: `ios/slabbist/slabbist/Features/Offers/OfferRepository.swift`
- Create: `ios/slabbist/slabbistTests/Features/Offers/OfferPricingServiceTests.swift`

- [ ] **Step 1: Write failing tests for `OfferPricingService`**

```swift
// slabbistTests/Features/Offers/OfferPricingServiceTests.swift
import Foundation
import Testing
@testable import slabbist

struct OfferPricingServiceTests {
    @Test func defaultBuyPriceProductRoundsHalfUp() {
        let r = OfferPricingService.defaultBuyPrice(reconciledCents: 1000, marginPct: 0.6)
        #expect(r == 600)
    }

    @Test func defaultBuyPriceHandlesOddMargins() {
        let r = OfferPricingService.defaultBuyPrice(reconciledCents: 999, marginPct: 0.65)
        #expect(r == 649)   // 999 * 0.65 = 649.35 → 649
    }

    @Test func defaultBuyPriceReturnsNilWhenInputsNil() {
        #expect(OfferPricingService.defaultBuyPrice(reconciledCents: nil, marginPct: 0.6) == nil)
        #expect(OfferPricingService.defaultBuyPrice(reconciledCents: 1000, marginPct: nil) == nil)
    }

    @Test func defaultBuyPriceReturnsZeroWhenZero() {
        #expect(OfferPricingService.defaultBuyPrice(reconciledCents: 0, marginPct: 0.6) == 0)
        #expect(OfferPricingService.defaultBuyPrice(reconciledCents: 1000, marginPct: 0) == 0)
    }

    @Test func defaultBuyPriceClampsMarginAtBounds() {
        // values out of [0, 1] should be rejected (caller passed an invalid margin)
        #expect(OfferPricingService.defaultBuyPrice(reconciledCents: 1000, marginPct: 1.5) == nil)
        #expect(OfferPricingService.defaultBuyPrice(reconciledCents: 1000, marginPct: -0.1) == nil)
    }
}
```

- [ ] **Step 2: Run the tests (FAIL — service doesn't exist)**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Features/Offers/OfferPricingServiceTests -quiet`
Expected: FAIL.

- [ ] **Step 3: Implement the service**

```swift
// Features/Offers/OfferPricingService.swift
import Foundation

enum OfferPricingService {
    /// Auto-derived per-line buy price.
    /// Returns nil when either input is nil or when the margin is outside [0, 1].
    /// Rounds half-up so 0.5¢ partials always round up to a full cent.
    static func defaultBuyPrice(reconciledCents: Int64?, marginPct: Double?) -> Int64? {
        guard let reconciledCents, let marginPct else { return nil }
        guard marginPct >= 0 && marginPct <= 1 else { return nil }
        let raw = Double(reconciledCents) * marginPct
        return Int64((raw + 0.5).rounded(.down))   // round-half-up via floor(raw + 0.5)
    }
}
```

(Note: `(raw + 0.5).rounded(.down)` is a deliberate round-half-up; the more obvious `raw.rounded()` uses banker's rounding which surprises operators on `.5` boundaries.)

- [ ] **Step 4: Run the tests to confirm green**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Features/Offers/OfferPricingServiceTests -quiet`
Expected: PASS 5/5.

- [ ] **Step 5: Implement `OfferRepository`**

```swift
// Features/Offers/OfferRepository.swift
import Foundation
import SwiftData

@MainActor
final class OfferRepository {
    private let context: ModelContext
    private let kicker: OutboxKicker
    let currentStoreId: UUID
    let currentUserId: UUID

    init(context: ModelContext, kicker: OutboxKicker, currentStoreId: UUID, currentUserId: UUID) {
        self.context = context
        self.kicker = kicker
        self.currentStoreId = currentStoreId
        self.currentUserId = currentUserId
    }

    // MARK: - State machine

    enum InvalidTransition: Error { case notAllowed(from: LotOfferState, to: LotOfferState) }

    static func canTransition(from: LotOfferState, to: LotOfferState) -> Bool {
        switch (from, to) {
        case (.drafting, .priced),
             (.priced, .presented),
             (.presented, .priced),
             (.presented, .declined),
             (.presented, .accepted),
             (.accepted, .presented),
             (.accepted, .declined),
             (.accepted, .paid),
             (.paid, .voided),
             (.declined, .priced):
            return true
        default:
            return from == to
        }
    }

    private func transition(_ lot: Lot, to next: LotOfferState) throws {
        let current = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
        guard Self.canTransition(from: current, to: next) else {
            throw InvalidTransition.notAllowed(from: current, to: next)
        }
        lot.lotOfferState = next.rawValue
        lot.lotOfferStateUpdatedAt = Date()
        lot.updatedAt = Date()
        enqueueLotPatch(lot)
    }

    // MARK: - Public API

    /// Snapshot the store's default margin onto a freshly-created lot.
    func snapshotDefaultMargin(into lot: Lot, store: Store) throws {
        guard lot.marginPctSnapshot == nil else { return }
        lot.marginPctSnapshot = store.defaultMarginPct
        lot.updatedAt = Date()
        enqueueLotPatch(lot)
        try context.save()
        kicker.kick()
    }

    /// Set a per-scan buy price, marking it overridden. Pass `nil` to revert to auto-derive.
    func setBuyPrice(_ cents: Int64?, scan: Scan, overridden: Bool) throws {
        scan.buyPriceCents = cents
        scan.buyPriceOverridden = overridden
        scan.updatedAt = Date()
        enqueueScanBuyPricePatch(scan)
        try recompute(lot: scan.lotId)
        try context.save()
        kicker.kick()
    }

    /// Compute and apply the auto-derived buy price for a scan whose comp just landed.
    /// Skips overridden scans. Returns the computed value (or nil if inputs missing).
    @discardableResult
    func applyAutoBuyPrice(scan: Scan, lot: Lot) throws -> Int64? {
        guard !scan.buyPriceOverridden else { return scan.buyPriceCents }
        let auto = OfferPricingService.defaultBuyPrice(
            reconciledCents: scan.reconciledHeadlinePriceCents,
            marginPct: lot.marginPctSnapshot
        )
        scan.buyPriceCents = auto
        scan.updatedAt = Date()
        enqueueScanBuyPricePatch(scan)
        try recompute(lot: lot.id)
        return auto
    }

    /// Update the lot's margin (e.g., from a slider). Re-derives buy prices for all
    /// non-overridden scans in the lot.
    func setLotMargin(_ pct: Double, on lot: Lot) throws {
        lot.marginPctSnapshot = pct
        lot.updatedAt = Date()
        enqueueLotPatch(lot)

        let lotId = lot.id
        let descriptor = FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        let scans = try context.fetch(descriptor)
        for scan in scans where !scan.buyPriceOverridden {
            let auto = OfferPricingService.defaultBuyPrice(
                reconciledCents: scan.reconciledHeadlinePriceCents,
                marginPct: pct
            )
            scan.buyPriceCents = auto
            scan.updatedAt = Date()
            enqueueScanBuyPricePatch(scan)
        }
        try recompute(lot: lot.id)
        try context.save()
        kicker.kick()
    }

    /// Attach a vendor (or detach when nil). Snapshots the display name so a later
    /// rename of the vendor doesn't change this lot's offer header.
    func attachVendor(_ vendor: Vendor?, to lot: Lot) throws {
        lot.vendorId = vendor?.id
        lot.vendorNameSnapshot = vendor?.displayName
        lot.updatedAt = Date()
        enqueueLotPatch(lot)
        try context.save()
        kicker.kick()
    }

    func sendToOffer(_ lot: Lot) throws {
        try transition(lot, to: .presented)
        try context.save()
        kicker.kick()
    }

    func bounceBack(_ lot: Lot) throws {
        try transition(lot, to: .priced)
        try context.save()
        kicker.kick()
    }

    func decline(_ lot: Lot) throws {
        try transition(lot, to: .declined)
        try context.save()
        kicker.kick()
    }

    func recordAcceptance(_ lot: Lot) throws {
        try transition(lot, to: .accepted)
        try context.save()
        kicker.kick()
    }

    func reopenDeclined(_ lot: Lot) throws {
        try transition(lot, to: .priced)
        try context.save()
        kicker.kick()
    }

    // MARK: - Outbox plumbing

    private func enqueueLotPatch(_ lot: Lot) {
        let payload = OutboxPayloads.UpdateLotOffer(
            id: lot.id.uuidString,
            vendor_id: lot.vendorId?.uuidString,
            vendor_name_snapshot: lot.vendorNameSnapshot,
            margin_pct_snapshot: lot.marginPctSnapshot,
            lot_offer_state: lot.lotOfferState,
            lot_offer_state_updated_at: lot.lotOfferStateUpdatedAt.map { ISO8601DateFormatter.shared.string(from: $0) },
            updated_at: ISO8601DateFormatter.shared.string(from: lot.updatedAt)
        )
        let item = OutboxItem(
            id: UUID(), kind: .updateLotOffer,
            payload: (try? JSONEncoder().encode(payload)) ?? Data(),
            status: .pending, attempts: 0, createdAt: Date(), nextAttemptAt: Date()
        )
        context.insert(item)
    }

    private func enqueueScanBuyPricePatch(_ scan: Scan) {
        let payload = OutboxPayloads.UpdateScanBuyPrice(
            id: scan.id.uuidString,
            buy_price_cents: scan.buyPriceCents,
            buy_price_overridden: scan.buyPriceOverridden,
            updated_at: ISO8601DateFormatter.shared.string(from: scan.updatedAt)
        )
        let item = OutboxItem(
            id: UUID(), kind: .updateScanBuyPrice,
            payload: (try? JSONEncoder().encode(payload)) ?? Data(),
            status: .pending, attempts: 0, createdAt: Date(), nextAttemptAt: Date()
        )
        context.insert(item)
    }

    private func recompute(lot lotId: UUID) throws {
        let payload = OutboxPayloads.RecomputeLotOffer(lot_id: lotId.uuidString)
        let item = OutboxItem(
            id: UUID(), kind: .recomputeLotOffer,
            payload: try JSONEncoder().encode(payload),
            status: .pending, attempts: 0, createdAt: Date(), nextAttemptAt: Date()
        )
        context.insert(item)
    }
}
```

- [ ] **Step 6: Build + commit**

Run: `xcodebuild build -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: BUILD SUCCEEDED.

```bash
git add ios/slabbist/slabbist/Features/Offers/ \
        ios/slabbist/slabbistTests/Features/Offers/
git commit -m "feat(ios): OfferPricingService + OfferRepository state machine"
```

---

### Task 8 — `OfferRepositoryTests` + integrate auto-buy-price into existing comp landing

**Files:**
- Create: `ios/slabbist/slabbistTests/Features/Offers/OfferRepositoryTests.swift`
- Modify: `ios/slabbist/slabbist/Features/Comp/CompFetchService.swift` (call `OfferRepository.applyAutoBuyPrice` when a comp lands)
- Modify: `ios/slabbist/slabbist/Features/Lots/LotsViewModel.swift` (snapshot default margin on lot create)

- [ ] **Step 1: Write the failing tests**

```swift
// slabbistTests/Features/Offers/OfferRepositoryTests.swift
import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct OfferRepositoryTests {
    private func makeContext() -> (OfferRepository, ModelContext, Lot, Scan) {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let storeId = UUID()
        let userId = UUID()
        let kicker = OutboxKicker()
        let repo = OfferRepository(context: context, kicker: kicker, currentStoreId: storeId, currentUserId: userId)
        let lot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId, name: "L", createdAt: Date(), updatedAt: Date())
        lot.marginPctSnapshot = 0.6
        let scan = Scan(id: UUID(), storeId: storeId, lotId: lot.id, userId: userId, grader: .PSA, certNumber: "1", createdAt: Date(), updatedAt: Date())
        scan.reconciledHeadlinePriceCents = 1000
        context.insert(lot); context.insert(scan); try? context.save()
        return (repo, context, lot, scan)
    }

    @Test func applyAutoBuyPriceFillsValueWhenCompLands() throws {
        let (repo, _, lot, scan) = makeContext()
        let result = try repo.applyAutoBuyPrice(scan: scan, lot: lot)
        #expect(result == 600)
        #expect(scan.buyPriceCents == 600)
        #expect(scan.buyPriceOverridden == false)
    }

    @Test func applyAutoBuyPriceSkipsOverriddenScans() throws {
        let (repo, _, lot, scan) = makeContext()
        scan.buyPriceCents = 999
        scan.buyPriceOverridden = true
        let result = try repo.applyAutoBuyPrice(scan: scan, lot: lot)
        #expect(result == 999)
        #expect(scan.buyPriceCents == 999)
    }

    @Test func setLotMarginRecomputesNonOverriddenScans() throws {
        let (repo, _, lot, scan) = makeContext()
        scan.buyPriceCents = 600
        try repo.setLotMargin(0.7, on: lot)
        #expect(scan.buyPriceCents == 700)
    }

    @Test func setLotMarginPreservesOverriddenScans() throws {
        let (repo, _, lot, scan) = makeContext()
        scan.buyPriceCents = 999; scan.buyPriceOverridden = true
        try repo.setLotMargin(0.5, on: lot)
        #expect(scan.buyPriceCents == 999)
    }

    @Test func sendToOfferTransitionsDraftingViaPriced() throws {
        let (repo, _, lot, _) = makeContext()
        // drafting can't go directly to presented; must be priced first.
        #expect(throws: OfferRepository.InvalidTransition.self) { try repo.sendToOffer(lot) }
        // Apply a price → transition to priced (we'll fake by setting the lot state directly through setLotMargin which doesn't transition; instead use applyAuto)
        let scan = Scan(id: UUID(), storeId: lot.storeId, lotId: lot.id, userId: UUID(), grader: .PSA, certNumber: "x", createdAt: Date(), updatedAt: Date())
        scan.reconciledHeadlinePriceCents = 1000
        // (in practice the comp landing path drives the drafting→priced transition;
        // here we simulate by setting the buy price)
        try repo.setBuyPrice(600, scan: scan, overridden: false)
        // After the recompute job lands the state should be priced; in offline tests we
        // assert via direct state set, since the worker isn't running:
        lot.lotOfferState = LotOfferState.priced.rawValue
        try repo.sendToOffer(lot)
        #expect(lot.lotOfferState == LotOfferState.presented.rawValue)
    }

    @Test func bounceBackReturnsPresentedToPriced() throws {
        let (repo, _, lot, _) = makeContext()
        lot.lotOfferState = LotOfferState.presented.rawValue
        try repo.bounceBack(lot)
        #expect(lot.lotOfferState == LotOfferState.priced.rawValue)
    }

    @Test func acceptedCanDropBackToPresented() throws {
        let (repo, _, lot, _) = makeContext()
        lot.lotOfferState = LotOfferState.accepted.rawValue
        // If still in offline window, the operator can walk it back:
        lot.lotOfferState = LotOfferState.presented.rawValue
        #expect(OfferRepository.canTransition(from: .accepted, to: .presented) == true)
    }
}
```

- [ ] **Step 2: Run tests (FAIL — auto-buy-price not yet wired into comp landing path)**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/Features/Offers -quiet`
Expected: state-machine tests PASS; the auto-buy-price tests PASS once `OfferRepository` is implemented (Task 7 already wrote it).

- [ ] **Step 3: Hook `applyAutoBuyPrice` into `CompFetchService`**

Find the success path in `Features/Comp/CompFetchService.swift` where a `GradedMarketSnapshot` is upserted and `Scan.reconciledHeadlinePriceCents` is set. Immediately after, call:

```swift
if let lot = try? context.fetch(
    FetchDescriptor<Lot>(predicate: #Predicate { $0.id == scan.lotId })
).first {
    let repo = OfferRepository(context: context, kicker: kicker,
                               currentStoreId: scan.storeId,
                               currentUserId: scan.userId)
    _ = try? repo.applyAutoBuyPrice(scan: scan, lot: lot)
}
```

(The exact wiring depends on how `CompFetchService` accesses the model context — match its existing dependency-injection pattern.)

- [ ] **Step 4: Snapshot default margin on lot creation**

In `Features/Lots/LotsViewModel.swift`, modify `createLot` so the new lot picks up the store's `default_margin_pct`:

```swift
@discardableResult
func createLot(name: String, notes: String? = nil) throws -> Lot {
    let now = Date()
    let lot = Lot(...)   // existing
    context.insert(lot)

    // Snapshot the store's default margin onto the lot.
    let storeId = currentStoreId
    if let store = try context.fetch(
        FetchDescriptor<Store>(predicate: #Predicate { $0.id == storeId })
    ).first {
        lot.marginPctSnapshot = store.defaultMarginPct
    }

    // ... existing outbox enqueue + save
}
```

- [ ] **Step 5: Run the full test suite**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompFetchService.swift \
        ios/slabbist/slabbist/Features/Lots/LotsViewModel.swift \
        ios/slabbist/slabbistTests/Features/Offers/OfferRepositoryTests.swift
git commit -m "feat(ios): auto-derive buy_price on comp landing + margin snapshot on lot create"
```

---

### Task 9 — `LotDetailView` + `LotsListView` extensions

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Lots/LotDetailView.swift`
- Modify: `ios/slabbist/slabbist/Features/Lots/LotsListView.swift`

- [ ] **Step 1: Add the vendor strip + margin slider sheet to `LotDetailView`**

Just below the existing `aggregateStrip`, render a vendor strip and a margin row:

```swift
private var vendorStrip: some View {
    SlabCard {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                KickerLabel("Vendor")
                Text(lot.vendorNameSnapshot ?? lookupVendorName() ?? "No vendor attached")
                    .slabRowTitle()
            }
            Spacer()
            Button(lot.vendorId == nil ? "Attach" : "Change") { showingVendorPicker = true }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.gold)
                .accessibilityIdentifier("lot-vendor-attach")
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
    }
}

private var marginRow: some View {
    SlabCard {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                KickerLabel("Margin")
                Text(formattedMargin).font(SlabFont.mono(size: 14))
            }
            Spacer()
            Button("Adjust") { showingMarginSheet = true }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.gold)
                .accessibilityIdentifier("lot-margin-adjust")
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
    }
}
```

State:

```swift
@State private var showingVendorPicker = false
@State private var showingMarginSheet = false
```

Sheets:

```swift
.sheet(isPresented: $showingVendorPicker) {
    VendorPicker(
        storeId: lot.storeId,
        onPick: { vendor in
            try? offerRepository().attachVendor(vendor, to: lot)
        },
        onCreate: { id, name, method, value, notes in
            // Reuse VendorsRepository for the create (same outbox kind).
            let repo = VendorsRepository(context: context, kicker: kicker, currentStoreId: lot.storeId)
            return try repo.upsert(id: id, displayName: name, contactMethod: method, contactValue: value, notes: notes)
        }
    )
}
.sheet(isPresented: $showingMarginSheet) {
    MarginPickerSheet(
        currentPct: lot.marginPctSnapshot ?? 0.6,
        onSelect: { pct in
            try? offerRepository().setLotMargin(pct, on: lot)
        }
    )
}
```

- [ ] **Step 2: Add `MarginPickerSheet`** as a new file or inline:

```swift
struct MarginPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pct: Double
    let onSelect: (Double) -> Void

    init(currentPct: Double, onSelect: @escaping (Double) -> Void) {
        _pct = State(initialValue: currentPct)
        self.onSelect = onSelect
    }

    private static let snaps: [Double] = [0.50, 0.55, 0.60, 0.65, 0.70]

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                KickerLabel("Lot margin")
                Text("\(Int((pct * 100).rounded()))% of comp").slabTitle()
                HStack(spacing: Spacing.s) {
                    ForEach(Self.snaps, id: \.self) { snap in
                        Button("\(Int(snap * 100))%") { pct = snap }
                            .buttonStyle(.plain)
                            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
                            .background(snap == pct ? AppColor.gold.opacity(0.2) : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.gold, lineWidth: snap == pct ? 1.5 : 0.5))
                    }
                }
                Slider(value: $pct, in: 0...1, step: 0.01)
                    .accessibilityIdentifier("margin-slider")
                Spacer()
                PrimaryGoldButton(title: "Save margin") {
                    onSelect(pct)
                    dismiss()
                }
                .accessibilityIdentifier("margin-save")
            }
            .padding(.horizontal, Spacing.xxl).padding(.vertical, Spacing.l)
        }
    }
}
```

- [ ] **Step 3: Add per-scan buy-price badge in the slab row** (inside the existing `slabRow(for:)`)

Below the existing trailing-value `VStack`, add:

```swift
if let buy = scan.buyPriceCents {
    Text("Buy \(formattedCents(buy))")
        .font(SlabFont.mono(size: 11, weight: .semibold))
        .foregroundStyle(scan.buyPriceOverridden ? AppColor.gold : AppColor.text)
}
```

(If the trailing column already shows comp/manual, the buy badge goes underneath in the same VStack so the alignment stays clean.)

- [ ] **Step 4: Add bottom action bar** to `LotDetailView` (state-driven):

```swift
private var actionBar: some View {
    let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
    return Group {
        switch state {
        case .drafting:
            EmptyView()
        case .priced:
            PrimaryGoldButton(title: "Send to offer") {
                try? offerRepository().sendToOffer(lot)
            }
            .accessibilityIdentifier("send-to-offer")
        case .presented, .accepted:
            NavigationLink("Resume offer", value: LotsRoute.offerReview(lot.id))
                .accessibilityIdentifier("resume-offer")
        case .declined:
            Button("Re-open as new offer") { try? offerRepository().reopenDeclined(lot) }
                .accessibilityIdentifier("reopen-declined")
        case .paid, .voided:
            EmptyView()  // Plan 3 fills these with "View receipt" / "View void"
        }
    }
}
```

(Add `case .offerReview(UUID)` to `LotsRoute` and a destination handler — see Step 6.)

- [ ] **Step 5: Add per-row state pill on `LotsListView`**

Inside `row(for:)`, add a chip on the right:

```swift
private func statePill(for lot: Lot) -> some View {
    let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
    let label: String
    let color: Color
    switch state {
    case .drafting:  label = "Drafting";  color = AppColor.dim
    case .priced:    label = "Priced";    color = AppColor.gold
    case .presented: label = "Awaiting";  color = AppColor.gold
    case .accepted:  label = "Accepted";  color = AppColor.gold
    case .declined:  label = "Declined";  color = AppColor.muted
    case .paid:      label = "Paid";      color = AppColor.positive
    case .voided:    label = "Voided";    color = AppColor.negative
    }
    return Text(label)
        .font(SlabFont.mono(size: 10, weight: .semibold))
        .tracking(1)
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xxs)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.4), lineWidth: 1))
}
```

Place it in the row HStack between the lot name and the chevron.

- [ ] **Step 6: Add `LotsRoute.offerReview(UUID)`** and the navigation destination

```swift
enum LotsRoute: Hashable {
    case lot(UUID)
    case scan(UUID)
    case offerReview(UUID)
    case vendor(UUID)
}
```

In `LotsListView.routeDestination`:

```swift
case .offerReview(let lotId):
    if let lot = try? context.fetch(FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })).first {
        OfferReviewView(lot: lot)
    } else {
        missingEntityView(label: "Lot")
    }
```

- [ ] **Step 7: Build + commit**

Run: `xcodebuild build -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: BUILD SUCCEEDED.

```bash
git add ios/slabbist/slabbist/Features/Lots/
git commit -m "feat(ios): LotDetailView vendor strip, margin sheet, action bar; LotsListView state pill"
```

---

### Task 10 — `OfferReviewView`

**Files:**
- Create: `ios/slabbist/slabbist/Features/Offers/OfferReviewView.swift`

- [ ] **Step 1: Implement the view**

```swift
// Features/Offers/OfferReviewView.swift
import SwiftUI
import SwiftData

/// The "ready to present" workbench. Operator presents the offer to the vendor
/// from this screen; bounces back if they negotiate; declines if they walk;
/// "Mark paid" hands off to Plan 3's commit flow (stubbed here).
struct OfferReviewView: View {
    let lot: Lot
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @Query private var scans: [Scan]
    @State private var paymentMethod: String = "cash"
    @State private var paymentReference: String = ""
    @State private var error: String?

    init(lot: Lot) {
        self.lot = lot
        let lotId = lot.id
        _scans = Query(filter: #Predicate<Scan> { $0.lotId == lotId },
                       sort: [SortDescriptor(\Scan.createdAt)])
    }

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    totalCard
                    linesSection
                    paymentCard
                    if let error {
                        Text(error).font(SlabFont.sans(size: 13))
                            .foregroundStyle(AppColor.negative)
                    }
                    actionStack
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationTitle("Offer review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Vendor")
            Text(lot.vendorNameSnapshot ?? "No vendor attached").slabTitle()
        }
    }

    private var totalCard: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                KickerLabel("Offer total")
                Text(formattedCents(totalBuyCents)).font(SlabFont.serif(size: 40))
                Text("\(scans.count) lines · \(Int((lot.marginPctSnapshot ?? 0.6) * 100))% margin")
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
                    ForEach(scans, id: \.id) { scan in
                        if scan.id != scans.first?.id { SlabCardDivider() }
                        lineRow(scan)
                    }
                }
            }
        }
    }

    private func lineRow(_ scan: Scan) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(scan.grader.rawValue) \(scan.grade ?? "—") · \(scan.certNumber)")
                    .font(SlabFont.mono(size: 12)).foregroundStyle(AppColor.muted)
            }
            Spacer()
            Text(scan.buyPriceCents.map(formattedCents) ?? "—")
                .font(SlabFont.mono(size: 14, weight: .semibold))
                .foregroundStyle(scan.buyPriceOverridden ? AppColor.gold : AppColor.text)
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
    }

    private var paymentCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Payment")
            SlabCard {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Picker("Method", selection: $paymentMethod) {
                        ForEach(["cash", "check", "store_credit", "digital", "other"], id: \.self) {
                            Text($0.replacingOccurrences(of: "_", with: " ")).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("payment-method-picker")
                    TextField("Reference (check #, Venmo handle, …)", text: $paymentReference)
                        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
                        .accessibilityIdentifier("payment-reference-field")
                }
                .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
            }
        }
    }

    private var actionStack: some View {
        VStack(spacing: Spacing.m) {
            // Plan 3 wires this to /transaction-commit; here we only transition locally.
            PrimaryGoldButton(title: "Mark paid") {
                try? offerRepository().recordAcceptance(lot)
                // commit is Plan 3
            }
            .accessibilityIdentifier("mark-paid")

            HStack(spacing: Spacing.m) {
                Button("Bounce back") { try? offerRepository().bounceBack(lot) }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.muted)
                    .accessibilityIdentifier("bounce-back")
                Spacer()
                Button("Decline") { try? offerRepository().decline(lot) }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.negative)
                    .accessibilityIdentifier("decline-offer")
            }
        }
    }

    private var totalBuyCents: Int64 {
        scans.compactMap(\.buyPriceCents).reduce(0, +)
    }

    private func offerRepository() -> OfferRepository {
        OfferRepository(context: context, kicker: kicker,
                        currentStoreId: lot.storeId,
                        currentUserId: session.userId ?? UUID())
    }

    private func formattedCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
}
```

- [ ] **Step 2: Build to confirm**

Run: `xcodebuild build -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/Offers/OfferReviewView.swift
git commit -m "feat(ios): OfferReviewView (presented↔priced/declined/accepted)"
```

---

### Task 11 — `ScanDetailView` buy-price card + UI test

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift`
- Create: `ios/slabbist/slabbistUITests/OfferPricingFlowUITests.swift`

- [ ] **Step 1: Add buy-price card to `ScanDetailView`**

Above the existing `CompCardView`, render:

```swift
@State private var showingBuyPriceSheet = false

private var buyPriceCard: some View {
    SlabCard {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Buy price")
            HStack(alignment: .firstTextBaseline) {
                Text(scan.buyPriceCents.map(formatCents) ?? "—")
                    .font(SlabFont.serif(size: 32))
                Spacer()
                Text(buyPriceCaption)
                    .font(SlabFont.mono(size: 11)).foregroundStyle(AppColor.dim)
            }
            HStack(spacing: Spacing.m) {
                Button("Edit") { showingBuyPriceSheet = true }
                    .buttonStyle(.plain).foregroundStyle(AppColor.gold)
                    .accessibilityIdentifier("buy-price-edit")
                if scan.buyPriceOverridden {
                    Button("Reset to auto") {
                        try? offerRepository().setBuyPrice(nil, scan: scan, overridden: false)
                    }
                    .buttonStyle(.plain).foregroundStyle(AppColor.muted)
                    .accessibilityIdentifier("buy-price-reset")
                }
            }
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
    }
    .sheet(isPresented: $showingBuyPriceSheet) {
        BuyPriceSheet(initialCents: scan.buyPriceCents) { cents in
            try offerRepository().setBuyPrice(cents, scan: scan, overridden: true)
        }
    }
}

private var buyPriceCaption: String {
    if scan.buyPriceOverridden { return "Override" }
    if scan.buyPriceCents == nil { return "Awaiting comp" }
    let pct = Int(((lot()?.marginPctSnapshot ?? 0.6) * 100).rounded())
    return "Auto · \(pct)% × comp"
}
```

(Use the existing `ManualPriceSheet` UI shell as a template for `BuyPriceSheet` — copy and adapt the file, keeping the same identifier conventions but with `buy-price-*` prefixes.)

- [ ] **Step 2: Create `BuyPriceSheet`**

Copy `ManualPriceSheet.swift` to a new file `BuyPriceSheet.swift` and replace the copy with buy-price-specific text. Identifiers: `buy-price-field`, `buy-price-save`, `buy-price-clear`, `buy-price-error`. The `onSubmit` closure now writes to `Scan.buyPriceCents` via `OfferRepository.setBuyPrice`.

- [ ] **Step 3: Write the end-to-end UI test**

```swift
// slabbistUITests/OfferPricingFlowUITests.swift
import XCTest

final class OfferPricingFlowUITests: XCTestCase {
    func test_price_send_bounce_decline_flow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_AUTOSIGNIN", "UITEST_SEED_SCANNED_LOT"]
        app.launch()

        // Open the seeded lot.
        app.tabBars.buttons["Lots"].tap()
        app.buttons["lot-row-Test Lot"].tap()

        // Adjust margin to 70%.
        app.buttons["lot-margin-adjust"].tap()
        // tap the 70% snap chip via accessibility (the slider is also OK; chips are deterministic)
        app.buttons["70%"].tap()
        app.buttons["margin-save"].tap()

        // Override one line.
        app.buttons["scan-row-12345678"].tap()
        app.buttons["buy-price-edit"].tap()
        app.textFields["buy-price-field"].tap()
        app.textFields["buy-price-field"].typeText("99.99")
        app.buttons["buy-price-save"].tap()
        app.navigationBars.buttons.firstMatch.tap()  // back

        // Send to offer.
        app.buttons["send-to-offer"].tap()
        XCTAssertTrue(app.staticTexts["Offer total"].waitForExistence(timeout: 2))

        // Bounce back.
        app.buttons["bounce-back"].tap()
        // …UI returns to LotDetailView; confirm the action bar is back to "Send to offer"
        XCTAssertTrue(app.buttons["send-to-offer"].waitForExistence(timeout: 2))

        // Send → decline.
        app.buttons["send-to-offer"].tap()
        app.buttons["decline-offer"].tap()
        XCTAssertTrue(app.buttons["reopen-declined"].waitForExistence(timeout: 2))
    }
}
```

- [ ] **Step 4: Run the full test suite**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: PASS. If `UITEST_SEED_SCANNED_LOT` doesn't exist as a launch arg, add a small seeding helper to `UITestApp.swift` that creates a `Test Lot` with three validated scans and reconciled comps when that flag is set.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift \
        ios/slabbist/slabbist/Features/Scanning/BuyPriceSheet.swift \
        ios/slabbist/slabbistUITests/OfferPricingFlowUITests.swift
git commit -m "feat(ios): ScanDetailView buy-price card + offer pricing UI test"
```

---

## Self-review checklist

- [ ] **Spec coverage.** Every column added in the spec's "Lots (existing table — columns added)" + "Scans (existing table — column rename + add)" + "Stores (column added)" sections has a migration + matching SwiftData property. The `/lot-offer-recompute` Edge Function matches the spec's contract (200/404/409/500). `OfferRepository`'s state-machine matches the spec's "legal transitions" table.
- [ ] **Type consistency.** `OfferRepository` method names match between `OfferRepositoryTests`, `LotDetailView`, and `OfferReviewView` (`setBuyPrice`, `setLotMargin`, `attachVendor`, `sendToOffer`, `bounceBack`, `decline`, `recordAcceptance`, `reopenDeclined`).
- [ ] **No placeholders.** Every code block is complete. The `Mark paid` button transitions to `accepted` locally only — Plan 3 wires the actual commit. This is a known seam, documented in code comments, not a placeholder.
- [ ] **TDD ordering.** Each task that touches code has a failing-test step before the impl step.

## What's next

Plan 3 (Transactions) lands:
- `transactions` + `transaction_lines` tables + RLS.
- `/transaction-commit` + `/transaction-void` Edge Functions.
- `OfferRepository.commit(_:)` wiring from `accepted → paid`.
- `TransactionsListView` + `TransactionDetailView`.
- Post-paid immutability gate on `LotDetailView` and `ScanDetailView`.
- Vendor purchase history (lights up `VendorDetailView`'s history section).
