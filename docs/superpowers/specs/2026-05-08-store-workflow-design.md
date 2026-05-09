# Store Workflow — Design Spec

**Sub-project:** #6 — Store workflow: transactions, vendor DB, offers
**Date:** 2026-05-08
**Status:** Design draft; awaiting review

## Summary

Sub-project #6 turns a saved lot into a real business transaction. After a store owner bulk-scans 30 slabs and gets per-slab comps (sub-project #5), this sub-project layers in:

- A vendor (and customer) contact database scoped per store, with full purchase history per vendor.
- Per-scan **buy prices** (the store's offer for each slab) derived from the reconciled comp times a margin, with operator override.
- A **lot-offer state machine** that walks a lot through `drafting → priced → presented → accepted → paid`, with `declined` and `voided` exits.
- An **immutable transactions ledger** — once a buy is paid, the line items, totals, and the snapshotted vendor name freeze. Voids are new rows pointing at the original; nothing mutates in place.
- The Edge Functions and SwiftUI screens needed to drive the spine end-to-end on iOS.

This spec is the **spine MVP**. The customer-facing presenter mode, PDF/email offer sheet, QR-coded receipts, signature capture, and ID-capture compliance flows are deliberately deferred — each is captured as a named follow-up in [Deferred follow-ups](#deferred-follow-ups) with enough design notes for a future plan to pick up cleanly. End-of-day recap is sketched as a Lots-tab summary card; the full analytics dashboard belongs to sub-project #8.

**What this sub-project owns:** `vendors`, `transactions`, `transaction_lines` tables and their RLS; new columns on `lots`/`scans`/`stores` for the offer-pricing seam; the `/lot-offer-recompute`, `/transaction-commit`, and `/transaction-void` Edge Functions; the new iOS Vendors / Offer Review / Transactions surfaces and the offer-pricing additions to existing Lots screens.

**What this sub-project references but does not own:** the entire graded-card data surface (`graded_card_identities`, `graded_cards`, `graded_market`) — owned by tcgcsv. The `/cert-lookup` and `/price-comp` Edge Functions and the SwiftData comp cache — owned by sub-projects 3/4. Margin **rules** (per-category, floors/ceilings) — owned by sub-project 7; this sub-project ships only a per-store flat default with a clean upgrade seam.

**Naming clarification.** The bulk-scan spec reserved `scans.offer_cents` for "the store's per-line offer" but the iOS app shipped that column as a vendor manual-ask fallback used in `ManualPriceSheet`. To eliminate the ambiguity, this sub-project **renames `scans.offer_cents` → `scans.vendor_ask_cents`** (with matching rename in the Swift `Scan.offerCents` property and the manual-price sheet) and adds a **new** `scans.buy_price_cents` for the store's per-line offer. Both columns coexist; only `buy_price_cents` flows into transaction totals.

## Goals

1. After a bulk scan completes, the operator can attach a vendor, see auto-computed buy prices, override per line, and finalize a transaction in under 90 seconds for a 12-slab lot.
2. Every paid transaction is reconstructable from the database alone — no view-layer math hidden in the iOS code, no value tied to a mutable scan that could later drift.
3. Vendor purchase history is queryable in O(history rows for that vendor) and renders without any cross-store leakage.
4. The data model supports sub-project #7's full margin rules (per-category, floors, ceilings, role-based visibility) **without schema migration** — the seam is the `lots.margin_rule_id` reference plus the `lots.margin_pct_snapshot` field.
5. The data model supports sub-project #8's analytics (P&L per transaction, employee performance, daily/weekly/monthly aggregates) by reading `transactions` and `transaction_lines` directly — no transformations in iOS.
6. Offline-first: a lot can be priced and an offer captured while offline; only the **commit-to-paid** transition requires a successful round-trip to `/transaction-commit` (no offline mode for paid status — see [Offline behavior](#offline-behavior)).
7. Voids are a first-class operation, never a delete.

## Non-goals

- Customer presenter mode, PDF offer sheets, QR receipts, signature capture, ID capture (all deferred — see [Deferred follow-ups](#deferred-follow-ups)).
- Per-category / per-grade margin rules — sub-project #7.
- Role-based visibility of cost vs margin in the iOS UI — sub-project #7. (Schema-level RLS protects cross-store leakage; intra-store role gating is a #7 concern.)
- Selling cards out (the marketplace flow) — sub-project #12.
- Multi-currency. Everything is USD cents. The display formatter is locale-aware; storage is not.
- Refund/partial-void of individual lines. MVP supports voiding the whole transaction only; partial voids are a follow-up.
- Tax. Buy transactions in this market are typically tax-exempt for the store; if tax becomes relevant it lives on transactions as a `tax_cents` column added later.

## Architecture

### Where this sub-project sits

```
┌─────────────────────────────────────┐    ┌──────────────────────────────────┐
│  iOS App                            │    │  Supabase                        │
│  ───────────                        │    │  ──────────                      │
│  SwiftUI + SwiftData                │    │  Postgres + RLS                  │
│                                     │    │                                  │
│  NEW Features/Vendors/              │    │  NEW tables (this sub-project):  │
│    VendorsListView                  │◄──►│    vendors                       │
│    VendorDetailView                 │    │    transactions                  │
│    VendorPicker                     │    │    transaction_lines             │
│                                     │    │                                  │
│  EXTENDED Features/Lots/            │    │  EXTENDED columns:               │
│    LotDetailView (offer sections)   │    │    stores.default_margin_pct     │
│    OfferReviewView (NEW)            │    │    lots.vendor_id                │
│                                     │    │    lots.vendor_name_snapshot     │
│  EXTENDED Features/Scanning/        │    │    lots.margin_pct_snapshot      │
│    ScanDetailView (buy-price edit)  │    │    lots.lot_offer_state          │
│    ManualPriceSheet (renamed →      │    │    scans.buy_price_cents (NEW)   │
│      VendorAskSheet, semantics      │    │    scans.vendor_ask_cents        │
│      preserved)                     │    │      (renamed from offer_cents)  │
│                                     │    │                                  │
│  NEW Features/Transactions/         │    │  NEW Edge Functions:             │
│    TransactionsListView             │    │    /lot-offer-recompute          │
│    TransactionDetailView            │    │    /transaction-commit           │
│                                     │    │    /transaction-void             │
└─────────────────────────────────────┘    └──────────────────────────────────┘
```

The **graded-card surface** (`graded_card_identities`, `graded_cards`, `graded_market`) and the comp pipeline (`/cert-lookup`, `/price-comp`) are unchanged — sub-project #6 reads `Scan.reconciledHeadlinePriceCents` (already populated server-side by the comp reconciliation rule) and never touches comp aggregation.

### Lifecycle: lot → offer → transaction

```
                     ┌──────────┐
                     │ drafting │  scans land, comps fetch
                     └────┬─────┘
                          │ first scan validates and a comp lands
                          ▼
                     ┌──────────┐
                     │  priced  │  buy_price_cents auto-filled per scan
                     └────┬─────┘
                          │ operator taps "Send to offer"
                          ▼
              ┌────────►┌──────────┐         ┌──────────┐
              │         │presented │ vendor  │ declined │  terminal-but-undo-able
   negotiation│         └────┬─────┘ no-go ─►└──────────┘
              │              │
              │ ◄────────────┤  vendor counters; operator drops back
              │              │
              │              │ vendor agrees
              │              ▼
              │         ┌──────────┐
              │         │ accepted │  payment method picked, ready to pay
              │         └────┬─────┘
              │              │ /transaction-commit
              │              ▼
              │         ┌──────────┐
              │         │   paid   │  transactions row written; lot frozen
              │         └────┬─────┘
              │              │ /transaction-void
              │              ▼
              │         ┌──────────┐
              │         │  voided  │  void row written; lot stays paid as a
              │         └──────────┘   reference but is excluded from totals
              │
              │ from drafting/priced: operator scraps and starts over
              ▼
         ┌──────────┐
         │ archived │  lot_status = closed, no transaction
         └──────────┘
```

`lot_status` (existing enum: `open | closed | converted`) and `lot_offer_state` (new) are kept **parallel**, not merged. `lot_status` continues to mean "is this lot in the operator's working set" (open vs closed); `lot_offer_state` describes "where in the offer/transaction lifecycle is this lot." A lot is `closed` once it's `paid`, `voided`, or operator-archived. Keeping them parallel avoids a destructive enum migration and lets the existing LotsListView "Open lots" filter work unchanged.

### Where money is computed

| Layer | Computes | Notes |
|---|---|---|
| **tcgcsv ingest** | comp aggregates | Per (identity, grading_service, grade) tuple; written to `graded_market`. |
| **`/price-comp`** | reconciled headline | Already in production. Returns `reconciled_headline_price_cents` + `reconciled_source` per scan. |
| **iOS `OfferPricingService`** | per-scan default `buy_price_cents = round(reconciled × lot.margin_pct_snapshot)` | Called once when a scan validates and a comp lands; result cached on the SwiftData `Scan` row. Operator overrides override. |
| **`/lot-offer-recompute`** | `lots.offered_total_cents = sum(scan.buy_price_cents)` | Idempotent; called whenever a buy price changes or margin changes. |
| **`/transaction-commit`** | freezes line totals + total_buy_cents | Server reads each scan, copies `buy_price_cents` to `transaction_lines.buy_price_cents`, sums them into `transactions.total_buy_cents`. After this point, scan-side edits do not affect the transaction. |

The discipline is: **the iOS app never holds the canonical total at commit time**. The server pulls fresh values from `scans` at the moment of `/transaction-commit` and copies them into `transaction_lines`. This means race conditions during the "tap Mark paid while another operator edits a line" window resolve cleanly to whatever is on the server.

## Data model

### Postgres schema additions

#### Stores (existing table — column added)

```sql
alter table stores
  add column default_margin_pct numeric(5,4) not null default 0.6000
  check (default_margin_pct >= 0 and default_margin_pct <= 1);
```

`0.6000` = "store offers 60% of comp by default." Range is `[0, 1]`. The check constraint guards against typos like `60` (which would offer 60× comp, a very expensive bug).

#### Vendors (new table)

```sql
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
```

`pg_trgm` index on `display_name` powers the vendor picker's fuzzy search. Soft-archive only — analytics still needs the row.

#### Lots (existing table — columns added)

```sql
create type lot_offer_state as enum (
  'drafting',   -- scans are landing; no buy prices yet
  'priced',     -- buy_price_cents filled (auto or override) on at least one scan
  'presented',  -- operator showed offer to vendor; awaiting agreement
  'accepted',   -- vendor agreed; payment method captured
  'declined',   -- vendor said no; lot still inspectable but not paid
  'paid',       -- transaction row exists, totals frozen
  'voided'      -- transaction was voided after pay
);

alter table lots
  add column vendor_id uuid references vendors(id),
  add column vendor_name_snapshot text,
  add column margin_pct_snapshot numeric(5,4)
    check (margin_pct_snapshot is null or (margin_pct_snapshot >= 0 and margin_pct_snapshot <= 1)),
  add column lot_offer_state lot_offer_state not null default 'drafting',
  add column lot_offer_state_updated_at timestamptz;
create index lots_vendor_id on lots(vendor_id);
create index lots_offer_state on lots(store_id, lot_offer_state);
```

The existing `lots.offered_total_cents`, `lots.transaction_stamp jsonb`, and `lots.margin_rule_id` remain — `offered_total_cents` is now actively maintained by `/lot-offer-recompute`; `transaction_stamp` is unused in MVP but kept as a dropbox for future per-lot metadata; `margin_rule_id` stays null in MVP (sub-project #7 fills it).

#### Scans (existing table — column rename + add)

```sql
alter table scans rename column offer_cents to vendor_ask_cents;
alter table scans add column buy_price_cents bigint;
alter table scans add column buy_price_overridden boolean not null default false;
```

`buy_price_overridden = true` means an operator explicitly set the value (don't auto-recompute on margin change). `false` means it was auto-derived; recompute on margin change. This avoids the surprise where an operator types a custom $400 and a margin slider tweak silently overwrites it.

#### Transactions (new tables)

```sql
create type payment_method as enum ('cash', 'check', 'store_credit', 'digital', 'other');

create table transactions (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references stores(id),
  lot_id uuid not null references lots(id),
  vendor_id uuid references vendors(id),  -- nullable: an unknown walk-in is still a real txn
  vendor_name_snapshot text not null,      -- always present, copied at commit time
  total_buy_cents bigint not null,
  payment_method payment_method not null,
  payment_reference text,                  -- check #, Venmo handle, free-text
  paid_at timestamptz not null,
  paid_by_user_id uuid not null references auth.users(id),
  voided_at timestamptz,
  voided_by_user_id uuid references auth.users(id),
  void_reason text,
  void_of_transaction_id uuid references transactions(id),  -- self-FK for voids
  created_at timestamptz not null default now()
);
create index transactions_store_paid_at on transactions(store_id, paid_at desc);
create index transactions_lot_id on transactions(lot_id);
create index transactions_vendor_id on transactions(vendor_id);
create unique index transactions_one_active_per_lot
  on transactions(lot_id) where void_of_transaction_id is null and voided_at is null;

create table transaction_lines (
  transaction_id uuid not null references transactions(id) on delete cascade,
  scan_id uuid not null references scans(id),
  line_index int not null,
  buy_price_cents bigint not null,
  identity_snapshot jsonb not null,        -- {card_name, set_name, card_number, year, variant,
                                            --  grader, grade, cert_number, comp_used_cents,
                                            --  reconciled_source}
  primary key (transaction_id, scan_id)
);
create index transaction_lines_scan_id on transaction_lines(scan_id);
```

Key invariants encoded in the schema:

- `transactions_one_active_per_lot` ensures a lot has at most one non-voided transaction.
- A void is `voided_at is not null` AND `void_of_transaction_id` references the original. The original keeps its `voided_at` null — voids are append-only.
- `vendor_name_snapshot` is `not null` because a vendor record can later be archived/renamed without rewriting receipts.
- `transaction_lines.identity_snapshot` is `not null` because a future schema change to `graded_card_identities` (new fields, splits, merges) cannot retroactively change a paid receipt's contents.

### SwiftData mirrors (device-side)

New `@Model` classes in `Core/Models/`:

```swift
@Model final class Vendor {
    @Attribute(.unique) var id: UUID
    var storeId: UUID
    var displayName: String
    var contactMethod: String?  // matches Postgres enum strings
    var contactValue: String?
    var notes: String?
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
}

@Model final class StoreTransaction {  // "Transaction" collides with Combine
    @Attribute(.unique) var id: UUID
    var storeId: UUID
    var lotId: UUID
    var vendorId: UUID?
    var vendorNameSnapshot: String
    var totalBuyCents: Int64
    var paymentMethod: String
    var paymentReference: String?
    var paidAt: Date
    var paidByUserId: UUID
    var voidedAt: Date?
    var voidedByUserId: UUID?
    var voidReason: String?
    var voidOfTransactionId: UUID?
    var createdAt: Date
}

@Model final class TransactionLine {
    @Attribute(.unique) var compositeKey: String  // "{transactionId}:{scanId}"
    var transactionId: UUID
    var scanId: UUID
    var lineIndex: Int
    var buyPriceCents: Int64
    var identitySnapshotJSON: Data
}
```

Existing `Lot` and `Scan` models gain matching properties for the new columns. The `Scan.offerCents` Swift property is renamed to `Scan.vendorAskCents`; a new `Scan.buyPriceCents: Int64?` and `Scan.buyPriceOverridden: Bool` are added.

### Outbox additions

New `OutboxKind` cases: `upsertVendor`, `archiveVendor`, `recomputeLotOffer`, `commitTransaction`, `voidTransaction`. The existing outbox worker priority is extended:

```
cert_lookup_job > price_comp_job > commit_transaction > void_transaction
  > upsert_vendor > archive_vendor > recompute_lot_offer
  > insert_scan > update_scan
```

`commit_transaction` and `void_transaction` are **non-collapsible** — duplicates are forbidden, not merged (each one is a different intent). Every other kind dedupes on its primary subject (vendor id, lot id).

### Row Level Security

```sql
-- vendors: read/write within caller's stores
create policy vendors_select on vendors for select
  using (exists (select 1 from store_members where user_id = auth.uid() and store_id = vendors.store_id));
create policy vendors_insert on vendors for insert
  with check (exists (select 1 from store_members where user_id = auth.uid() and store_id = vendors.store_id));
create policy vendors_update on vendors for update
  using (exists (select 1 from store_members where user_id = auth.uid() and store_id = vendors.store_id))
  with check (store_id = (select store_id from vendors v2 where v2.id = vendors.id));
-- no delete policy: archive only

-- transactions: read within store; insert/update only via Edge Function (service role)
create policy transactions_select on transactions for select
  using (exists (select 1 from store_members where user_id = auth.uid() and store_id = transactions.store_id));
-- no insert/update/delete policies — only service role (Edge Functions) writes

-- transaction_lines: same as transactions
create policy transaction_lines_select on transaction_lines for select
  using (exists (
    select 1 from transactions t
    join store_members sm on sm.store_id = t.store_id
    where t.id = transaction_lines.transaction_id and sm.user_id = auth.uid()
  ));
```

The "Edge Function only" write policy on `transactions` and `transaction_lines` is the load-bearing piece. It guarantees that no client-side code path can write to the ledger directly — every transaction has been through the commit flow's atomicity and validation. Role-based visibility (cost/margin hidden from associates) is sub-project #7's concern and is enforced at the iOS view layer plus a future view-layer Postgres role check.

## iOS application structure

### New folders

```
Features/
├── Vendors/                       (new)
│   ├── VendorsListView.swift
│   ├── VendorDetailView.swift
│   ├── VendorPicker.swift
│   ├── VendorEditSheet.swift
│   └── VendorsViewModel.swift
├── Offers/                        (new)
│   └── OfferReviewView.swift
├── Transactions/                  (new)
│   ├── TransactionsListView.swift
│   ├── TransactionDetailView.swift
│   └── TransactionsViewModel.swift
└── Lots/                          (extended)
    ├── LotDetailView.swift          ← gains vendor strip, margin slider, send-to-offer
    ├── LotsListView.swift           ← gains state pills, transaction footer chip
    └── LotsViewModel.swift          ← gains attachVendor, setMargin, recomputeOffer
```

### Routing

`LotsRoute` enum extends:

```swift
enum LotsRoute: Hashable {
    case lot(UUID)
    case scan(UUID)
    case offerReview(UUID)        // lot id
    case transaction(UUID)        // transaction id
    case vendor(UUID)
}
```

Vendors get their own tab? **No** — they live under "More" (the existing third tab) at MVP. A dedicated tab promotes vendors to peer-of-lots prominence which they don't deserve in a buy-only workflow. A "Vendors" entry point also lives inline on `LotDetailView` (the vendor strip → tap → vendor detail).

### View ownership

| View | Reads | Writes |
|---|---|---|
| `LotDetailView` (extended) | `Lot`, `Scan[]`, `GradedMarketSnapshot[]`, `Vendor?` | – (mutations go through `LotsViewModel`) |
| `OfferReviewView` (new) | `Lot`, `Scan[]`, `Vendor?`, `Store.defaultMarginPct` | enqueues `commitTransaction` outbox item |
| `VendorsListView` (new) | `Vendor[]` filtered by store | – |
| `VendorDetailView` (new) | `Vendor`, `StoreTransaction[]` for vendor | enqueues `upsertVendor`, `archiveVendor` |
| `VendorPicker` (new, sheet) | `Vendor[]` filtered by store + trigram search | enqueues `upsertVendor` if new vendor |
| `VendorEditSheet` (new, sheet) | `Vendor?` | enqueues `upsertVendor` |
| `TransactionsListView` (new) | `StoreTransaction[]` filtered by store, sorted by `paidAt desc` | – |
| `TransactionDetailView` (new) | `StoreTransaction`, `TransactionLine[]` | enqueues `voidTransaction` |
| `ScanDetailView` (extended) | + `Scan.buyPriceCents` | enqueues `update_scan` (via existing path) |

### Repositories

A new `OfferRepository` lives under `Features/Offers/`:

```swift
@MainActor
final class OfferRepository {
    func defaultBuyPrice(for scan: Scan, lot: Lot) -> Int64?
    func setBuyPrice(_ cents: Int64?, scan: Scan, overridden: Bool) throws
    func recomputeLotOffer(_ lot: Lot) throws
    func sendToOffer(_ lot: Lot) throws       // drafting/priced → presented
    func recordAcceptance(_ lot: Lot, paymentMethod: PaymentMethod, reference: String?) throws  // presented → accepted
    func decline(_ lot: Lot) throws           // presented → declined
    func bounceBack(_ lot: Lot) throws        // presented → priced (negotiation)
    func commit(_ lot: Lot) async throws -> StoreTransaction  // accepted → paid; awaits Edge Function
    func voidTransaction(_ txn: StoreTransaction, reason: String) async throws
}
```

`OfferRepository` is the single funnel for state transitions; `LotsViewModel` and `OfferReviewView` call into it. The repo also enforces invariants client-side (e.g., refuses to commit a lot with zero scans or a scan with no buy price) before enqueueing the outbox item — server-side enforcement is the source of truth, but the client-side check provides immediate UX feedback.

A new `VendorsRepository` and `TransactionsRepository` follow the same pattern.

## Edge Functions

### `/lot-offer-recompute`

- **Auth:** JWT.
- **Request:** `{ lot_id }`.
- **Behavior:** within a single transaction, sums `coalesce(scans.buy_price_cents, 0)` for the lot's scans, writes the result to `lots.offered_total_cents`, sets `lots.lot_offer_state = 'priced'` if currently `'drafting'` and at least one buy price is present. Returns the updated `{ lot_id, offered_total_cents, lot_offer_state }`.
- **Response 200:** updated lot summary.
- **Response 403:** caller is not a member of the lot's store.
- **Response 409:** lot is in a terminal state (`paid`, `voided`); recompute is rejected. iOS treats this as success and refreshes its local state from server.
- **Idempotent:** yes. Re-calling produces the same result.
- **Concurrency:** uses `update lots set ... where id = $1 and lot_offer_state in ('drafting', 'priced', 'presented', 'accepted')` — race with another writer either silently wins or trips the 409 check.

### `/transaction-commit`

- **Auth:** JWT.
- **Request:** `{ lot_id, payment_method, payment_reference?, vendor_id?, vendor_name_override? }`.
- **Behavior (single transaction):**
  1. Verify caller is a member of the lot's store with role `owner` or `manager`. (`associate` cannot commit; future #7 work tightens this.)
  2. Verify `lot_offer_state = 'accepted'`. Otherwise 409.
  3. Verify at least one scan with `buy_price_cents IS NOT NULL`. Otherwise 422.
  4. Resolve `vendor_name_snapshot`: prefer `vendor_name_override`, else `vendors.display_name` for `vendor_id`, else "(unknown)". `vendor_id` itself can be null (anonymous walk-in).
  5. `INSERT` into `transactions` with `paid_at = now()`, `paid_by_user_id = auth.uid()`, `total_buy_cents = sum(scan.buy_price_cents)`.
  6. For each scan with non-null `buy_price_cents`, `INSERT` a `transaction_lines` row carrying a fresh `identity_snapshot` joined from `graded_card_identities` (or null fields if the scan never validated — those scans are still recorded as a line with their cert/grader).
  7. `UPDATE lots SET lot_offer_state = 'paid', lot_offer_state_updated_at = now(), status = 'converted' WHERE id = $1`.
  8. Return the inserted transaction id and a hydrated `{ transaction, lines }` payload.
- **Response 200:** `{ transaction_id, transaction, lines[] }`.
- **Response 409:** state precondition failure (lot not accepted, or another transaction already exists for the lot — caught by the unique partial index).
- **Response 422:** validation failure (no priced scans).
- **Idempotent:** **no, but state-guarded.** A duplicate call from the outbox after a successful commit hits the 409 path because the lot is already `paid`. The outbox treats 409 as "verify locally, mark completed" — see [Offline behavior](#offline-behavior).

### `/transaction-void`

- **Auth:** JWT, role `owner` or `manager`.
- **Request:** `{ transaction_id, reason }`.
- **Behavior (single transaction):**
  1. Verify caller membership + role.
  2. Verify the target transaction is non-voided (`voided_at is null` and not itself a void row).
  3. `UPDATE transactions SET voided_at = now(), voided_by_user_id = auth.uid(), void_reason = $reason WHERE id = $target`.
  4. `INSERT` a new `transactions` row with `void_of_transaction_id = $target`, `total_buy_cents = -original.total_buy_cents`, `paid_at = now()`, `paid_by_user_id = auth.uid()`, `payment_method = original.payment_method`, vendor fields copied. **No** `transaction_lines` are inserted for the void row — the original lines remain readable; the negative total in the void row is the analytics signal.
  5. `UPDATE lots SET lot_offer_state = 'voided' WHERE id = $original.lot_id`. (Status stays `converted` — sub-project 8 reads `lot_offer_state` for analytics filters.)
- **Response 200:** void transaction id and updated original.
- **Response 409:** target is already voided or is itself a void.

## Scan → offer → transaction pipeline

End-to-end, picking up where sub-project #5 leaves off (lot has scans; comps are landing).

1. **Scan validates and a comp lands.** The existing `CompFetchService` upserts a `GradedMarketSnapshot` and writes `Scan.reconciledHeadlinePriceCents`. **New:** `OfferRepository.defaultBuyPrice(for:lot:)` is called by `LotsViewModel` on this transition; it computes `round(reconciled × lot.margin_pct_snapshot)` and stores it on `Scan.buyPriceCents` only if `Scan.buyPriceOverridden == false`. The store's lot offer is silently nudged via an enqueued `recompute_lot_offer` outbox item.

2. **Operator opens `LotDetailView`.** New sections render:
   - **Vendor strip.** Empty state ("Attach a vendor"), or vendor name + contact preview + tap to open `VendorDetailView`. Long-press → "Detach vendor."
   - **Pricing strip.** Shows `lots.offered_total_cents`, the active margin (`margin_pct_snapshot` rendered as "60%"), an "Adjust margin" affordance, and per-scan-row buy-price badges next to the existing comp badges.
   - **Send-to-offer CTA.** Bottom-pinned primary button. Disabled while `lot_offer_state == 'drafting'` and any scan still has `compFetchState == 'fetching'`. Enabled the moment `lot_offer_state == 'priced'`.

3. **Operator adjusts margin.** Sheet picker with snap points (50%, 55%, 60%, 65%, 70%, custom). On dismiss, `OfferRepository.setLotMargin(_:)`:
   - Updates `lots.margin_pct_snapshot` locally + outboxes an update.
   - For every scan with `buy_price_overridden == false`, recomputes `buyPriceCents`.
   - Enqueues a single dedup'd `recompute_lot_offer` job.

4. **Operator overrides a per-scan buy price.** From `ScanDetailView`'s buy-price editor (or an inline tap on the row badge), opens a numeric sheet pre-filled with the current value. On save, `OfferRepository.setBuyPrice(_, scan:, overridden: true)` — the override flag pins the value against future margin changes. Clearing the value reverts to auto-derived.

5. **Operator taps "Send to offer."** Lot transitions `priced → presented`. Pushes `OfferReviewView`.

6. **`OfferReviewView` — the workbench for the actual buy conversation.**
   - Header: vendor name, scan count, total offer.
   - Per-scan lines: identity (card name + set + grade), comp (small), buy price (large, editable inline), source pill (`avg`/`PPT`/`Poketrace`/`manual override`).
   - Payment method picker: cash / check / store credit / digital / other.
   - Optional payment reference field (label adapts: "Check #" / "Venmo handle" / etc.).
   - Three actions: **Bounce back** (negotiate — drops to `priced`, returns to `LotDetailView`), **Decline** (vendor walks — terminal `declined` state), **Mark paid** (commit).

7. **Operator taps "Mark paid."** Lot transitions `presented → accepted` synchronously, then `OfferRepository.commit(lot)` enqueues a `commit_transaction` outbox item. The view enters a "Committing…" state with a progress indicator. When the outbox worker drains the job:
   - **Success:** `OfferRepository` writes the returned `StoreTransaction` and `TransactionLine[]` into SwiftData, transitions the lot's local state to `paid`, swaps the view to `TransactionDetailView` (already on the nav stack via a `path` push). The success haptic fires.
   - **Failure (5xx, network):** outbox retries with backoff. View shows "Sync pending — your offer is saved" + a "Retry now" button. Lot stays in `accepted` state. **Important:** the lot is not yet `paid` and the operator can still bounce back or decline if the buy falls through during the offline window. Once a `200` lands, lot becomes `paid` and the lot is locked.
   - **Failure (409 / 422):** operator-actionable error sheet with the server's reason. Lot reverts to `presented`.

8. **Receipt view (`TransactionDetailView`).** Renders the immutable transaction:
   - Vendor name (snapshot), date paid, payment method + reference.
   - Per-line list with identity snapshot + buy price.
   - Total.
   - Footer actions: **Void transaction** (owner/manager only — confirmation sheet with required `void_reason`), **View lot**.
   - Future sections (sketched, not built): **Email PDF**, **Print receipt**, **Show QR**.

9. **Void path.** Confirmation sheet → `OfferRepository.voidTransaction(_, reason:)` → outbox `void_transaction` → server inserts the void row → local state updates. Voided transactions are visually de-emphasized (stripe + "VOIDED" pill) but never removed from the list.

## Vendor flow

### Attaching a vendor to a lot

`LotDetailView`'s vendor strip → tap "Attach a vendor" → presents `VendorPicker`.

`VendorPicker` is a sheet with:
- Search field (trigram-backed; minimum 2 chars).
- Recent vendors list (sorted by most recent transaction, fall back to most recent vendor edit).
- "+ New vendor" footer row.

On pick, the lot's `vendor_id` is set and `vendor_name_snapshot` is **not** populated yet — that snapshot is captured at commit time, so a vendor renamed between attach and commit still produces the correct paid-time name on the receipt. A separate display join in the iOS view shows the live vendor name pre-commit (since pre-commit views aren't ledger).

### Vendor detail + purchase history

`VendorDetailView`:
- Header: display name, contact method + value (tappable: phone → dial, email → compose, instagram → open URL), notes.
- Edit button → `VendorEditSheet`.
- **Purchase history** section: every `StoreTransaction` for this vendor, sorted by `paidAt desc`. Each row: date, total, payment method, # of slabs, void chip if voided. Tap → `TransactionDetailView`.
- Aggregate strip: **lifetime total**, **lifetime slab count**, **last buy** date. All three are computed locally from cached transactions (analytics gets server-side rollups in sub-project #8).
- Archive action: button at the bottom, confirmation sheet, sets `archived_at`. Archived vendors no longer appear in the picker but are still resolvable when reading old transactions.

### Vendor de-duplication

The picker shows "Looks like {name} (last buy {date})" hints when a partial match score is high. We do **not** auto-merge — manual de-dup is a sub-project #8 concern (it requires looking at transaction history, which is analytics territory).

## Lots tab updates

### `LotsListView` extension

Add per-lot **state chip** (right-aligned), one of:
- "Drafting" — gold dim
- "Priced — $X" — gold (offer total)
- "Awaiting vendor" — gold
- "Accepted — $X" — gold strong
- "Paid — $X" — positive green
- "Voided" — negative red
- "Declined" — muted

Add a **"Recent transactions"** section below open lots, showing the last 7 days' `StoreTransaction` rows with a "View all" footer link to `TransactionsListView`. This is the partial "end-of-day recap" feature — a real recap with EoD math is sub-project #8.

### `LotDetailView` extension

The aggregate strip already shows "Estimated $X." It adds:
- A **"Offer" sub-line** below "Estimated" showing `offered_total_cents` when `lot_offer_state >= priced`. Format: `"Offer · $X · 60% · 12 lines"`.
- Vendor strip directly under the aggregate.
- Per-scan row gains a **buy-price badge** alongside the comp number. When the value is overridden, the badge gets a small "•" indicator; when auto-derived, plain.
- Bottom action bar (replaces the implicit list-only treatment):
  - State `drafting`: bar hidden.
  - State `priced`: **Send to offer** primary, **Adjust margin** secondary.
  - State `presented`: this state is rare on `LotDetailView` — usually the user is on `OfferReviewView`. A "Resume offer" link to `OfferReviewView`.
  - State `accepted`: "Mark paid" link to `OfferReviewView` (commit pending).
  - State `paid`: "View receipt" link to `TransactionDetailView`.
  - State `voided`: "View void" link.
  - State `declined`: "Re-open as new offer" reopens the lot back to `priced`.

### `ScanDetailView` extension

Adds a buy-price card above the existing comp card:

- Big buy-price number with a "tap to edit" affordance.
- Source pill: "Auto · 60% of avg" / "Override" / "Manual (no comp)".
- A "Reset to auto" link when overridden.
- Edit sheet uses the existing `ManualPriceSheet` UI shell with new copy.

## Offline behavior

| Action | Online | Offline |
|---|---|---|
| Edit per-scan buy price | Local write + outbox `update_scan` | Local write + outbox `update_scan` (queued) |
| Adjust margin | Local + outbox `update_lot` + `recompute_lot_offer` | Same; recompute lands when online |
| Send to offer | Local state transition + outbox `update_lot` | Same; transition is local |
| Bounce back / Decline | Local state transition + outbox `update_lot` | Same |
| Mark paid (commit) | Outbox `commit_transaction`; view shows "Committing…" until 200 lands | Outbox `commit_transaction` queued; view shows "Sync pending — your offer is saved" |
| Void | Outbox `void_transaction`; UI shows pending state | Same |

Two principles:

1. **Pricing and presentation are entirely local.** A vendor across the table doesn't need wifi for the operator to show numbers and capture a payment method. The `accepted` state can be reached fully offline.

2. **The transaction itself requires a server round-trip.** A receipt with `paid_at` must come from the server (real timestamp, real `paid_by_user_id` from JWT). Until the round-trip succeeds, the lot is `accepted`, not `paid`. The operator can still walk the buy back if they need to.

The `commit_transaction` outbox item handles the handoff: it stays `pending` while offline, retries on online transitions, and on 200 the local SwiftData picks up the server-authored `transactions` and `transaction_lines` rows. On a duplicate (the worker fired but lost connectivity before recording success, then retried), the server returns 409 with the existing transaction id; the worker treats this as success, refreshes the local cache, and marks the outbox item complete. **No double-commit is possible** because of the unique partial index on `transactions(lot_id) where void_of_transaction_id is null`.

## Error handling

| Class | Examples | User-visible behavior |
|---|---|---|
| **Margin out of range** | Operator types 150% in custom margin | Sheet shows "Margin must be 0–100%"; submit blocked |
| **No buy prices** | Lot has scans but all `buy_price_cents` are null | "Send to offer" disabled with hover tooltip "Pricing pending — wait for comps or set manual prices" |
| **Vendor record stale** | Picker showed a vendor that's been archived elsewhere | Picker fetches a fresh list before commit; archived vendors filtered out; if mid-flow the cached vendor is archived, the offer review view banners "This vendor was archived" with a re-pick CTA |
| **Commit 409 (already paid)** | Outbox retried after a network hiccup | Worker fetches the existing transaction by lot_id, marks outbox done, swaps UI to receipt view |
| **Commit 422 (no priced lines)** | Race: an operator deleted all priced scans between accept and commit | Sheet with "All lines were removed before payment. Returning to lot." Lot reverts to `drafting` |
| **Commit 403 (associate role)** | Future sub-project 7 enforces this; MVP all members are owners | Sheet with "Only owners and managers can complete a buy." |
| **Void 409 (already voided)** | Two operators tried to void simultaneously | Worker treats as success; UI refreshes |
| **Network timeout on commit** | Slow wifi at a card show | View stays on "Sync pending"; vendor receives a hand-written note for now; once online, the proper receipt becomes available |
| **Vendor name conflict** | Vendor created in two places at once | Both rows persist; de-dup is manual via sub-project 8 |
| **Lot deleted while in offer flow** | Operator on iPad A deletes lot; operator on iPad B is at OfferReviewView | iPad B's `OfferReviewView` shows missing-entity state on next refresh; outbox commit fails with 404 and surfaces "Lot is no longer available" |

## Testing strategy

### Unit (Swift Testing / XCTest)

- `OfferRepository.defaultBuyPrice` — boundary cases: comp=0, comp=null, margin=0, margin=1, margin=null (lot has no snapshot — fall back to store default; if both null, return null).
- `OfferRepository.setLotMargin` — only auto-derived prices recompute; overridden ones are sticky.
- `OfferRepository` state-machine guards — every `lot_offer_state` transition rejects illegal sources (e.g., `voided → priced` is rejected client-side before the outbox call).
- Identity snapshot serialization round-trip — snapshot built from a `GradedCardIdentity` decodes back to the same fields.
- Money math — penny-clean rounding on the margin product; no float drift.

### Integration

- Migration tests: rename `scans.offer_cents → vendor_ask_cents` is reversible; fresh insert + read for new tables.
- RLS policy tests for `vendors`, `transactions`, `transaction_lines` — positive and negative per policy. Negative tests confirm a member of store A cannot read store B's vendors or transactions, even by guessing UUIDs.
- Edge Function tests:
  - `/lot-offer-recompute` — sums correctly, idempotent on re-call, 409 on terminal state.
  - `/transaction-commit` — happy path; 409 on duplicate; 422 on no lines; verifies `vendor_name_snapshot` precedence (override > vendor > "(unknown)"); verifies line snapshots are populated even when scans never validated.
  - `/transaction-void` — happy path; 409 on already-voided; verifies negative `total_buy_cents` and `void_of_transaction_id` linkage.
- End-to-end (iOS simulator + local Supabase): bulk scan → attach vendor → adjust margin → send to offer → mark paid → void. Asserts that the SwiftData state at every step matches the database state.

### UI (XCUITest)

- Happy path: open lot → attach vendor → adjust margin → override one line → send to offer → mark paid → see receipt.
- Offline commit path: airplane mode → mark paid → assert pending state → toggle online → assert receipt lands.
- Void path: receipt → void → assert voided pill on lot list.
- Vendor picker fuzzy search: type partial match → assert correct vendor surfaces.
- Per-scan override sticky: set margin to 60%, override one line, change margin to 70%, assert the overridden line did not change.

### Fixtures

- Seed scripts for a multi-store setup: 2 stores, each with 5 vendors, 10 lots, 3 transactions. Used by RLS tests and by the End-of-day recap UI tests.
- Identity snapshot fixtures covering: validated PSA scan, manual-entry scan with no identity, scan with a partially-populated identity (no `card_number`).

## Observability

- Structured logs (OSLog subsystem `com.slabbist.offers`):
  - `offer.transition` — every `lot_offer_state` change (lot id, from, to, user id).
  - `offer.commit_attempt`, `offer.commit_success`, `offer.commit_failure` (with reason).
  - `offer.void` — same shape.
- Server-side metrics (Supabase project): `transactions_inserted_total`, `transactions_voided_total`, `lot_offer_state_transitions_total{from,to}`, `commit_duration_ms`.
- Client metric: median time from "Send to offer" to "receipt visible" (the operator's true wait time at the counter).

## Deferred follow-ups

Each of the items below is a named follow-up captured here so future plans can pick them up cleanly. They are explicitly **out of scope for the spine MVP** but the data model is shaped to accommodate them without migration.

### Customer presenter mode

A flipped-device layout that shows only buy prices and totals — hiding margin %, comp source labels, and any internal numerics. Reuses `OfferReviewView`'s data with a `.presenter` style. The brief: when the operator hands the iPad to the vendor, the vendor sees "Here's our offer for your 12 slabs: $1,847" and can scroll a clean per-line list. No edit affordances. Probably gated behind a long-press on the offer total in `OfferReviewView`. Future plan should pull design from `.impeccable.md`'s "vendor handoff" section.

### PDF / email offer sheet

Server-rendered PDF (Edge Function with a templating library, or a hosted render service — decision belongs to the follow-up plan). Generated post-commit and stored under `transactions/{id}.pdf` in Supabase Storage. Email send via the project's transactional email provider. The receipt URL is short and signed. **Ledger note:** the `transactions` table doesn't need a `pdf_url` column — the URL is derivable from `transaction_id`.

### QR code receipts

A short-lived signed JWT encoding `{transaction_id, redact: true}` rendered as a QR. Vendor scans → opens a public URL on `slabbist.com` showing the redacted receipt (line items, total, vendor name, date). No margin, no comp. Token expires after 30 days. Storage: nothing new; reuses the transaction id.

### Digital signature capture

PencilKit canvas inside `OfferReviewView` between "accepted" and "mark paid." Saved as a PNG to `transactions/{id}/signature.png` in Supabase Storage. The `transactions` table gains a single `signature_url` column when this lands. Trigger threshold: configurable per store — default "always for buys ≥ $200," plus an explicit "always require signature" store setting.

### ID capture for large buys

`PHPickerViewController` + Vision text recognition. Stored to `transactions/{id}/id_front.jpg` (and back when applicable). Compliance rule: configurable per store, default "buys ≥ $500 cash require ID capture." `transactions` table gains `id_capture_required boolean` and `id_capture_completed_at timestamptz`. **PII concerns:** the follow-up plan must include retention policy (default proposal: encrypted at rest, 7-year retention to match accounting norms, deletable on vendor request).

### End-of-day recap (full)

The Lots-tab "Recent transactions" section is the MVP partial. A full recap — daily P&L, employee breakdown, payment method split, void summary — belongs to sub-project #8 and reads directly from `transactions` and `transaction_lines`.

### Customer (sell-side) contacts

The current `vendors` table is buy-side only. When sub-project #12 (marketplace) introduces sells, it can either reuse `vendors` (rename to `contacts` + role flag) or introduce a parallel `customers` table. Decision deferred; the schema choice doesn't affect this sub-project.

### Partial-void / line-level void

MVP voids the whole transaction. Partial voids — "vendor came back saying that one slab was a fake, refund just that line" — require `transaction_lines` to gain a `voided_at` column and the void Edge Function to take a line list. Captured here so the schema seam is documented.

### Receipt printing (thermal)

Bluetooth thermal-printer integration for in-store paper receipts. Uses any of the standard StarPRNT/ESC-POS libs. Receipt format mirrors the digital one but plain-text. Printer settings live on `stores` (a single configured-printer per store).

## Out of scope (explicit)

- Anything in the [Deferred follow-ups](#deferred-follow-ups) list.
- Per-category margin rules and floors/ceilings — sub-project #7.
- Role-based UI visibility (associates seeing only buy prices) — sub-project #7.
- Wishlist / want-list price alerts — sub-project #7.
- Inventory tagging (case vs. back stock, location, aging) — sub-project #8.
- Tax handling, multi-currency, cross-store transfers, marketplace sells.
- Push notifications for completed transactions — sub-project #12.

## Cross-cutting references

- Bulk-scan spec (sub-project #5, the foundation this extends): [`2026-04-22-bulk-scan-comp-design.md`](./2026-04-22-bulk-scan-comp-design.md). Specifically, the lot/scan schema and outbox machinery this spec builds on.
- Sub-project #5 README: [`../../product/sub-projects/05-bulk-scan/README.md`](../../product/sub-projects/05-bulk-scan/README.md).
- Sub-project #6 README (this sub-project's high-level scope): [`../../product/sub-projects/06-store-workflow/README.md`](../../product/sub-projects/06-store-workflow/README.md).
- Sub-project #7 README (margin rules — consumes the `margin_rule_id` seam): [`../../product/sub-projects/07-margin-rules-buylist/README.md`](../../product/sub-projects/07-margin-rules-buylist/README.md).
- Sub-project #8 README (analytics — consumes `transactions` + `transaction_lines`): [`../../product/sub-projects/08-analytics-reporting/README.md`](../../product/sub-projects/08-analytics-reporting/README.md).
- Repo-root design language (consult before any UI work): `.impeccable.md`.
- Raw/graded decoupling rationale: memory note *"Raw and graded card data stay decoupled"*. This sub-project does not change that boundary.

## Follow-up tasks (captured for the plan step)

- **Migration ordering.** The `scans.offer_cents → vendor_ask_cents` rename and the `scans.buy_price_cents` add must land before the `/transaction-commit` Edge Function; the Edge Function must land before the iOS commit flow. Three separate plans likely.
- **`pg_trgm` extension.** Confirm it's already enabled in the Supabase project (check `supabase/migrations/`); if not, the vendors plan adds an enable migration.
- **Backfill.** Existing rows on `scans` with non-null `offer_cents` (the old vendor-ask manual fallback) carry their semantics over correctly under the rename — no data transformation needed.
- **Default margin pct.** The `0.6` default-default is a guess. Calibrate against operator interviews before launch; expose the setting in Settings (a new screen, but trivial).
- **Sub-project #7 seam check.** Before #7 plans land, walk the `lots.margin_rule_id` seam to confirm it cleanly replaces `lots.margin_pct_snapshot` with rule-derived values without touching `OfferRepository` outside the snapshot computation.
- **Outbox priority.** The new outbox kinds slot above `insert_scan` / `update_scan`. Verify with a load test that the priority order doesn't starve scan inserts during a heavy commit run.
- **Visual polish for the new screens.** `frontend-design` + `ui-design:mobile-ios-design` (and `swiftui-expert-skill`) at implementation time. Reference `.impeccable.md` and the existing dark+gold language used in `LotDetailView` and `CompCardView`.
