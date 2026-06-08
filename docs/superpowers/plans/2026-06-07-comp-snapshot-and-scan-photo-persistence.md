# Comp-Snapshot & Scan-Photo Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist the comp that justified an offer (frozen at offer-send time) to Supabase so it survives later refetches and is retrievable per-scan; and write a deferred design for syncing scan photos.

**Architecture:** Mirror the existing offline-first outbox pipeline used by `updateScanBuyPrice`. When a lot transitions to `presented` (`OfferUseCase.sendToOffer`), serialize each scan's local `GradedMarketSnapshot` into an immutable JSON-string blob, store it on the local `Scan` + enqueue a new `updateScanComp` outbox kind that PATCHes a new `scans.comp_snapshot` text column. Photos (Part 2) are a separate, larger change deferred to a later branch.

**Tech Stack:** SwiftUI + SwiftData (iOS 26.4), Supabase Postgres 17 + PostgREST, Swift Testing (`@Test`/`#expect`).

**Scope note:** Part 1 (comp snapshot) is execution-ready, bite-sized TDD and should be built now. Part 2 (scan photos) is a deferred design + coarse task outline per the product decision "plan it, build comps first" — do **not** execute Part 2 in this branch.

**Decisions locked in (from design Q&A):**
- **Fidelity:** full snapshot (headline + per-grade tier ladder + price history + sold listings + confidence + source), not headline-only.
- **Timing:** frozen at offer-send (`sendToOffer` → `.presented`). A later re-send after edits overwrites the blob with the then-current comp. This captures "the comp behind the current offer."
- **Storage shape:** a `text` JSON blob column (`scans.comp_snapshot`), NOT `jsonb`. Rationale: mirrors the existing `*JSON` String? convention on `GradedMarketSnapshot`, keeps the outbox patch a plain `.string` value (no `AnyJSON.object` construction), and this is a retrieval/audit field, not a server-side query target. Tradeoff: cannot query inside the blob in SQL — acceptable and noted.

---

## File Structure

**Create:**
- `ios/slabbist/slabbist/Core/Models/CompSnapshotWire.swift` — Codable wire struct + serializer/deserializer between `GradedMarketSnapshot` and the JSON blob.
- `supabase/migrations/20260607120000_scans_comp_snapshot.sql` — adds `comp_snapshot text` + `comp_snapshot_at timestamptz` to `scans`.
- `ios/slabbist/slabbistTests/Core/Models/CompSnapshotWireTests.swift` — round-trip serialization tests.

**Modify:**
- `ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxKind.swift` — add `.updateScanComp` case + priority.
- `ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxPayloads.swift` — add `UpdateScanComp` payload struct.
- `ios/slabbist/slabbist/Core/Sync/OutboxDrainer.swift:613` — add `.updateScanComp` dispatch case.
- `ios/slabbist/slabbist/Core/Models/Scan.swift` — add `compSnapshotJSON` + `compSnapshotAt` stored properties.
- `ios/slabbist/slabbist/Core/Data/DTOs/ScanDTO.swift` — add `compSnapshot` + `compSnapshotAt` fields + coding keys (detail projection only).
- `ios/slabbist/slabbist/Features/Offers/OfferUseCase.swift:277` — freeze comp snapshots inside `sendToOffer`.
- `ios/slabbist/slabbist/slabbistTests/Core/Sync/OutboxDrainerTestSupport.swift` — add `enqueueUpdateScanComp` harness helper.
- `ios/slabbist/slabbist/slabbistTests/Core/Sync/OutboxDrainerTests.swift` — add dispatch test.
- `ios/slabbist/slabbist/slabbistTests/Features/Offers/OfferUseCaseTests.swift` — add freeze-on-send test.

---

## PART 1 — Comp-at-offer-time persistence (BUILD NOW)

### Task 1: Database migration — add comp-snapshot columns to `scans`

**Files:**
- Create: `supabase/migrations/20260607120000_scans_comp_snapshot.sql`

Adding columns to an existing `store_id`-scoped table needs **no new RLS policy** — the existing `scans` RLS already covers all columns of the row. No new policy file.

- [ ] **Step 1: Write the migration**

```sql
-- Freeze the comp that justified an offer onto the scan at offer-send time.
-- comp_snapshot is a JSON-string blob (text, not jsonb) mirroring the
-- on-device GradedMarketSnapshot *JSON convention; it is an audit/retrieval
-- record, not a server-side query target. comp_snapshot_at marks the moment
-- the lot was presented and the comp was frozen.
alter table public.scans
  add column if not exists comp_snapshot text,
  add column if not exists comp_snapshot_at timestamptz;
```

- [ ] **Step 2: Apply the migration**

Run: `supabase db push`
Expected: applies cleanly. If it errors `relation already exists` (ledger drift), do NOT re-run DDL — INSERT the migration filename into `supabase_migrations.schema_migrations` per the repo's migration-ledger convention, then re-verify the columns exist.

- [ ] **Step 3: Verify the columns landed**

Run (via Supabase MCP `execute_sql` or psql):
```sql
select column_name, data_type from information_schema.columns
where table_schema='public' and table_name='scans'
  and column_name in ('comp_snapshot','comp_snapshot_at');
```
Expected: two rows — `comp_snapshot | text` and `comp_snapshot_at | timestamp with time zone`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260607120000_scans_comp_snapshot.sql
git commit -m "feat(db): add comp_snapshot columns to scans"
```

---

### Task 2: `CompSnapshotWire` serializer

**Files:**
- Create: `ios/slabbist/slabbist/Core/Models/CompSnapshotWire.swift`
- Test: `ios/slabbist/slabbist/slabbistTests/Core/Models/CompSnapshotWireTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import slabbist

@Suite("CompSnapshotWire")
struct CompSnapshotWireTests {
    /// A frozen comp must faithfully reproduce the snapshot that justified
    /// the offer — if any priced field (headline, tier ladder, history,
    /// sold listings) is dropped on the round-trip, the audit record lies
    /// about what the operator saw. This test would fail if the encoder
    /// silently omitted a field or used a non-round-tripping date strategy.
    @Test func roundTripsAllPricedFields() throws {
        let identity = UUID()
        let snap = GradedMarketSnapshot(
            identityId: identity,
            gradingService: "PSA",
            grade: "10",
            source: "poketrace",
            headlinePriceCents: 125_00,
            ptAvgCents: 120_00,
            ptLowCents: 100_00,
            ptHighCents: 150_00,
            ptTrend: "up",
            ptConfidence: "high",
            ptSaleCount: 12,
            poketraceCardId: "pt-abc",
            tcgplayerProductId: 4242,
            ptTierPricesJSON: #"{"psa_10":12500,"psa_9":9000}"#,
            priceHistoryJSON: nil,
            marketplaceURL: URL(string: "https://ebay.com/sold"),
            soldListingsJSON: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cacheHit: true
        )

        let json = CompSnapshotWire.encode(from: snap)
        let wire = CompSnapshotWire.decode(json)

        #expect(wire?.headlinePriceCents == 125_00)
        #expect(wire?.source == "poketrace")
        #expect(wire?.ptConfidence == "high")
        #expect(wire?.ptSaleCount == 12)
        #expect(wire?.tcgplayerProductId == 4242)
        #expect(wire?.tierPricesCents["psa_10"] == 12500)
        #expect(wire?.tierPricesCents["psa_9"] == 9000)
        #expect(wire?.marketplaceURL?.absoluteString == "https://ebay.com/sold")
        #expect(wire?.cacheHit == true)
        #expect(wire?.fetchedAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// Missing/garbage blobs decode to nil rather than crashing — the
    /// detail view treats nil as "no frozen comp" and degrades gracefully.
    @Test func decodeReturnsNilForMissingOrMalformed() {
        #expect(CompSnapshotWire.decode(nil) == nil)
        #expect(CompSnapshotWire.decode("not json") == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:slabbistTests/CompSnapshotWireTests`
Expected: FAIL to compile — `CompSnapshotWire` undefined.

(Note: use an installed iOS 26.x simulator like **iPhone 17 Pro**; the CLAUDE.md "iPhone 16 Pro" string is stale for this 26.4-target app.)

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Immutable, self-contained serialization of a `GradedMarketSnapshot`
/// frozen onto a `Scan` at offer-send time. Persisted as a JSON-string
/// blob in `scans.comp_snapshot` (text column) so the comp that justified
/// an offer stays retrievable later — even after the live `graded_market`
/// cache is overwritten by a subsequent refetch.
///
/// Stored as a text blob (not jsonb) to mirror the existing `*JSON`
/// String? convention on `GradedMarketSnapshot` and to keep the outbox
/// patch a plain `.string` value. This is an audit/retrieval record, not
/// a server-side query target.
struct CompSnapshotWire: Codable, Equatable {
    let source: String
    let headlinePriceCents: Int64?
    let ptAvgCents: Int64?
    let ptLowCents: Int64?
    let ptHighCents: Int64?
    let ptAvg1dCents: Int64?
    let ptAvg7dCents: Int64?
    let ptAvg30dCents: Int64?
    let ptMedian3dCents: Int64?
    let ptMedian7dCents: Int64?
    let ptMedian30dCents: Int64?
    let ptTrend: String?
    let ptConfidence: String?
    let ptSaleCount: Int?
    let poketraceCardId: String?
    let tcgplayerProductId: Int?
    let tierPricesCents: [String: Int64]
    let priceHistory: [PriceHistoryPoint]
    let soldListings: [SoldListing]
    let marketplaceURL: URL?
    let fetchedAt: Date
    let cacheHit: Bool

    enum CodingKeys: String, CodingKey {
        case source
        case headlinePriceCents = "headline_price_cents"
        case ptAvgCents = "pt_avg_cents"
        case ptLowCents = "pt_low_cents"
        case ptHighCents = "pt_high_cents"
        case ptAvg1dCents = "pt_avg_1d_cents"
        case ptAvg7dCents = "pt_avg_7d_cents"
        case ptAvg30dCents = "pt_avg_30d_cents"
        case ptMedian3dCents = "pt_median_3d_cents"
        case ptMedian7dCents = "pt_median_7d_cents"
        case ptMedian30dCents = "pt_median_30d_cents"
        case ptTrend = "pt_trend"
        case ptConfidence = "pt_confidence"
        case ptSaleCount = "pt_sale_count"
        case poketraceCardId = "poketrace_card_id"
        case tcgplayerProductId = "tcgplayer_product_id"
        case tierPricesCents = "tier_prices_cents"
        case priceHistory = "price_history"
        case soldListings = "sold_listings"
        case marketplaceURL = "marketplace_url"
        case fetchedAt = "fetched_at"
        case cacheHit = "cache_hit"
    }
}

extension CompSnapshotWire {
    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Build a wire struct from the on-device snapshot, reusing the
    /// snapshot's decoded accessors so the nested blobs (tier ladder,
    /// price history, sold listings) come across already-typed.
    init(from snapshot: GradedMarketSnapshot) {
        self.source = snapshot.source
        self.headlinePriceCents = snapshot.headlinePriceCents
        self.ptAvgCents = snapshot.ptAvgCents
        self.ptLowCents = snapshot.ptLowCents
        self.ptHighCents = snapshot.ptHighCents
        self.ptAvg1dCents = snapshot.ptAvg1dCents
        self.ptAvg7dCents = snapshot.ptAvg7dCents
        self.ptAvg30dCents = snapshot.ptAvg30dCents
        self.ptMedian3dCents = snapshot.ptMedian3dCents
        self.ptMedian7dCents = snapshot.ptMedian7dCents
        self.ptMedian30dCents = snapshot.ptMedian30dCents
        self.ptTrend = snapshot.ptTrend
        self.ptConfidence = snapshot.ptConfidence
        self.ptSaleCount = snapshot.ptSaleCount
        self.poketraceCardId = snapshot.poketraceCardId
        self.tcgplayerProductId = snapshot.tcgplayerProductId
        self.tierPricesCents = snapshot.ptTierPricesCents
        self.priceHistory = snapshot.priceHistory
        self.soldListings = snapshot.soldListings
        self.marketplaceURL = snapshot.marketplaceURL
        self.fetchedAt = snapshot.fetchedAt
        self.cacheHit = snapshot.cacheHit
    }

    /// JSON-string blob for `scans.comp_snapshot`. Returns nil on encode
    /// failure (caller skips the freeze rather than queueing a bad patch).
    static func encode(from snapshot: GradedMarketSnapshot) -> String? {
        guard let data = try? makeEncoder().encode(CompSnapshotWire(from: snapshot)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode a persisted blob back into a wire struct. Returns nil when
    /// missing or malformed; the detail UI renders "no frozen comp".
    static func decode(_ json: String?) -> CompSnapshotWire? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? makeDecoder().decode(CompSnapshotWire.self, from: data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:slabbistTests/CompSnapshotWireTests`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Models/CompSnapshotWire.swift ios/slabbist/slabbist/slabbistTests/Core/Models/CompSnapshotWireTests.swift
git commit -m "feat(comp): add CompSnapshotWire serializer"
```

---

### Task 3: Outbox kind + payload

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxKind.swift`
- Modify: `ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxPayloads.swift`

- [ ] **Step 1: Add the enum case**

In `OutboxKind.swift`, add the case after `updateScanBuyPrice` (line 7):
```swift
    case updateScanBuyPrice
    case updateScanComp
```
And add its priority in the `priority` switch, alongside the other scan updates (after line 37):
```swift
        case .updateScanBuyPrice: return 10
        case .updateScanComp:     return 10
```

- [ ] **Step 2: Add the payload struct**

In `OutboxPayloads.swift`, after `UpdateScanBuyPrice` (line 147), add:
```swift
    /// Patch payload that freezes the comp behind an offer onto a scan at
    /// offer-send time. `comp_snapshot` is a JSON-string blob (text column,
    /// not jsonb); `nil` clears it. `comp_snapshot_at` marks when the lot
    /// was presented. Mirrors `scans.comp_snapshot` / `scans.comp_snapshot_at`.
    struct UpdateScanComp: Codable {
        let id: String
        let comp_snapshot: String?
        let comp_snapshot_at: String
        let updated_at: String
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED. (The new `OutboxKind` case will produce a non-exhaustive-switch error in `OutboxDrainer.dispatch` — that's expected and fixed in Task 4. If the build fails ONLY on that switch, proceed to Task 4 before committing.)

- [ ] **Step 4: Commit (after Task 4 makes it build)**

Defer the commit until Task 4 restores a clean build; commit them together there.

---

### Task 4: Drainer dispatch case

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Sync/OutboxDrainer.swift` (in `dispatch(kind:payload:)`, after the `.updateScanBuyPrice` case ending at line 676)

- [ ] **Step 1: Add the dispatch case**

After the `.updateScanBuyPrice` case (line 676), add:
```swift
        case .updateScanComp:
            let p = try decode(OutboxPayloads.UpdateScanComp.self, payload)
            guard let id = UUID(uuidString: p.id) else {
                throw OutboxBridgeError.malformedPayload(reason: "UpdateScanComp: invalid UUID")
            }
            var fields: [String: AnyJSON] = [
                "comp_snapshot_at": .string(p.comp_snapshot_at),
                "updated_at":       .string(p.updated_at)
            ]
            fields["comp_snapshot"] = p.comp_snapshot.map(AnyJSON.string) ?? .null
            try await repositories.scans.patch(id: id, fields: fields)
```

- [ ] **Step 2: Build to verify clean compile**

Run: `xcodebuild build -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED, no non-exhaustive-switch error.

- [ ] **Step 3: Commit (Tasks 3 + 4 together)**

```bash
git add ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxKind.swift ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxPayloads.swift ios/slabbist/slabbist/Core/Sync/OutboxDrainer.swift
git commit -m "feat(outbox): add updateScanComp kind + dispatch"
```

---

### Task 5: Drainer dispatch test

**Files:**
- Modify: `ios/slabbist/slabbist/slabbistTests/Core/Sync/OutboxDrainerTestSupport.swift`
- Modify: `ios/slabbist/slabbist/slabbistTests/Core/Sync/OutboxDrainerTests.swift`

- [ ] **Step 1: Add the harness enqueue helper**

In `OutboxDrainerTestSupport.swift`, after `enqueueUpdateScanBuyPrice` (ends line 332), add:
```swift
    func enqueueUpdateScanComp(
        id: UUID,
        snapshot: String?,
        createdAt: Date? = nil
    ) async throws {
        let stamp = createdAt ?? clock.current()
        let iso = ISO8601DateFormatter().string(from: stamp)
        let dto = OutboxPayloads.UpdateScanComp(
            id: id.uuidString,
            comp_snapshot: snapshot,
            comp_snapshot_at: iso,
            updated_at: iso
        )
        let payload = try JSONEncoder().encode(dto)
        try await drainer._testEnqueue(
            id: UUID(),
            kind: .updateScanComp,
            payload: payload,
            createdAt: stamp,
            nextAttemptAt: stamp
        )
    }
```

- [ ] **Step 2: Write the failing test**

In `OutboxDrainerTests.swift`, after the existing buy-price tests, add:
```swift
    @Test("updateScanComp: patches comp_snapshot + comp_snapshot_at")
    @MainActor
    func dispatchesUpdateScanComp() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueUpdateScanComp(id: scanId, snapshot: #"{"source":"poketrace"}"#)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.patchCalls.count == 1)
        #expect(h.fakeScans.patchCalls[0].id == scanId)
        #expect(h.fakeScans.patchCalls[0].fields["comp_snapshot"] == .string(#"{"source":"poketrace"}"#))
        #expect(h.fakeScans.patchCalls[0].fields["comp_snapshot_at"] != nil)
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("updateScanComp: nil snapshot writes .null")
    @MainActor
    func dispatchesUpdateScanCompNil() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueUpdateScanComp(id: scanId, snapshot: nil)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.patchCalls[0].fields["comp_snapshot"] == .null)
    }
```

- [ ] **Step 3: Run test to verify it passes**

Run: `xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:slabbistTests/OutboxDrainerTests/dispatchesUpdateScanComp -only-testing:slabbistTests/OutboxDrainerTests/dispatchesUpdateScanCompNil`
Expected: PASS (2 tests). The patch goes through `FakeScanRepository.patch`, which records into `patchCalls`.

- [ ] **Step 4: Commit**

```bash
git add ios/slabbist/slabbist/slabbistTests/Core/Sync/OutboxDrainerTestSupport.swift ios/slabbist/slabbist/slabbistTests/Core/Sync/OutboxDrainerTests.swift
git commit -m "test(outbox): cover updateScanComp dispatch"
```

---

### Task 6: Local model + DTO fields

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Models/Scan.swift`
- Modify: `ios/slabbist/slabbist/Core/Data/DTOs/ScanDTO.swift`

- [ ] **Step 1: Add the Scan stored properties**

In `Scan.swift`, after `reconciledSource` (line 90), add two optional stored properties (NOT added to `init` — optional + no default lets SwiftData lightweight migration leave existing rows nil, matching the `validationFailure*` convention already in this model):
```swift
    /// The comp that justified the most recent offer-send for this scan,
    /// serialized via `CompSnapshotWire` and frozen at `sendToOffer` time.
    /// Persisted so the operator can later see the exact number/ladder/sold
    /// comps behind an offer even after the live cache has refreshed.
    /// Mirrors `scans.comp_snapshot`. Optional + no init default → SwiftData
    /// lightweight migration leaves existing rows nil.
    var compSnapshotJSON: String?
    /// When `compSnapshotJSON` was frozen (the moment the lot was presented).
    /// Mirrors `scans.comp_snapshot_at`.
    var compSnapshotAt: Date?
```

- [ ] **Step 2: Add the DTO fields (detail projection only)**

In `ScanDTO.swift`, after `buyPriceOverridden` (line 24), add:
```swift
    /// Frozen comp blob (text) + its timestamp. Carried on the detail
    /// projection only; the slim `ScanListItemDTO` deliberately omits it
    /// (same reasoning as `ocr_raw_text` / `captured_photo_url`).
    var compSnapshot: String?
    var compSnapshotAt: Date?
```
And in `CodingKeys`, after `buyPriceOverridden` (line 42):
```swift
        case compSnapshot = "comp_snapshot"
        case compSnapshotAt = "comp_snapshot_at"
```

- [ ] **Step 3: Build to verify compile**

Run: `xcodebuild build -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED. Confirm no other call site constructs `ScanDTO` with a positional initializer that now breaks — `ScanDTO` uses the synthesized memberwise/Codable init; new optional fields default to nil at decode and don't break `init(from:)`. If any explicit `ScanDTO(...)` memberwise call exists (e.g. in `ScanDTO(from: InsertScan)`), add the two nil args there.

- [ ] **Step 4: Commit**

```bash
git add ios/slabbist/slabbist/Core/Models/Scan.swift ios/slabbist/slabbist/Core/Data/DTOs/ScanDTO.swift
git commit -m "feat(scan): add comp snapshot fields to model + DTO"
```

---

### Task 7: Freeze comp snapshots in `sendToOffer`

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Offers/OfferUseCase.swift:277`
- Test: `ios/slabbist/slabbist/slabbistTests/Features/Offers/OfferUseCaseTests.swift`

- [ ] **Step 1: Write the failing test**

In `OfferUseCaseTests.swift`, add (mirrors the existing `makeContext` style; builds its own priced lot + matching snapshot):
```swift
    @Test func sendToOfferFreezesCompSnapshotOntoScans() throws {
        let (repo, context, lot, scan) = makeContext()
        // Make the scan resolvable to a comp snapshot.
        let identity = UUID()
        scan.gradedCardIdentityId = identity
        scan.grade = "10"
        // A matching local snapshot (the live comp the operator is seeing).
        let snap = GradedMarketSnapshot(
            identityId: identity,
            gradingService: "PSA",
            grade: "10",
            source: "poketrace",
            headlinePriceCents: 125_00,
            priceHistoryJSON: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cacheHit: false
        )
        context.insert(snap)
        // Move the lot to .priced so the .presented transition is legal.
        lot.lotOfferState = LotOfferState.priced.rawValue
        try? context.save()

        try repo.sendToOffer(lot)

        #expect(lot.lotOfferState == LotOfferState.presented.rawValue)
        #expect(scan.compSnapshotAt != nil)
        let wire = CompSnapshotWire.decode(scan.compSnapshotJSON)
        #expect(wire?.headlinePriceCents == 125_00)
        #expect(wire?.source == "poketrace")
    }

    @Test func sendToOfferLeavesScansWithoutCompUntouched() throws {
        let (repo, context, lot, scan) = makeContext()
        // No gradedCardIdentityId / no snapshot → nothing to freeze.
        lot.lotOfferState = LotOfferState.priced.rawValue
        try? context.save()

        try repo.sendToOffer(lot)

        #expect(lot.lotOfferState == LotOfferState.presented.rawValue)
        #expect(scan.compSnapshotJSON == nil)
        #expect(scan.compSnapshotAt == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:slabbistTests/OfferUseCaseTests/sendToOfferFreezesCompSnapshotOntoScans`
Expected: FAIL — `scan.compSnapshotAt` is nil (freeze not yet wired).

- [ ] **Step 3: Implement the freeze**

In `OfferUseCase.swift`, replace `sendToOffer` (lines 277–281) with:
```swift
    /// Move a priced lot into the `presented` state — the moment the
    /// vendor sees the number. Freezes the comp behind each scan onto the
    /// scan (local + outbox) so the offer's justification is retrievable
    /// later, even after the live comp cache refreshes.
    func sendToOffer(_ lot: Lot) throws {
        try transition(lot, to: .presented)
        let now = Date()
        let lotId = lot.id
        let scans = try context.fetch(
            FetchDescriptor<Scan>(predicate: #Predicate<Scan> { $0.lotId == lotId })
        )
        for scan in scans {
            try freezeCompSnapshot(for: scan, at: now)
        }
        try context.save()
        kicker.kick()
    }
```
And add the private helper in the "Outbox plumbing" section (after `enqueueScanBuyPricePatch`, line 389):
```swift
    /// Serialize the scan's current local `GradedMarketSnapshot` (matched
    /// on identity + grader + grade) into an immutable blob, store it on
    /// the scan, and enqueue the patch. No-op when the scan has no resolved
    /// identity/grade or no local snapshot — there is no comp to freeze.
    private func freezeCompSnapshot(for scan: Scan, at now: Date) throws {
        guard let identityId = scan.gradedCardIdentityId, let grade = scan.grade else { return }
        let service = scan.grader.rawValue
        var descriptor = FetchDescriptor<GradedMarketSnapshot>(
            predicate: #Predicate<GradedMarketSnapshot> { s in
                s.identityId == identityId && s.gradingService == service && s.grade == grade
            }
        )
        descriptor.fetchLimit = 1
        guard let snapshot = try context.fetch(descriptor).first,
              let json = CompSnapshotWire.encode(from: snapshot) else { return }

        scan.compSnapshotJSON = json
        scan.compSnapshotAt = now
        scan.updatedAt = now
        let payload = OutboxPayloads.UpdateScanComp(
            id: scan.id.uuidString,
            comp_snapshot: json,
            comp_snapshot_at: ISO8601DateFormatter.shared.string(from: now),
            updated_at: ISO8601DateFormatter.shared.string(from: now)
        )
        context.insert(try OutboxItem.pending(.updateScanComp, payload))
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:slabbistTests/OfferUseCaseTests`
Expected: PASS — all existing OfferUseCase tests plus the two new ones.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Offers/OfferUseCase.swift ios/slabbist/slabbist/slabbistTests/Features/Offers/OfferUseCaseTests.swift
git commit -m "feat(offers): freeze comp snapshot onto scans at offer-send"
```

---

### Task 8: Full-suite regression check

- [ ] **Step 1: Run the full unit-test suite**

Run: `xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:slabbistTests`
Expected: green, **modulo the known pre-existing red baseline** (stale `testTabBarReachesEveryRoot`, pending snapshot re-records, flaky UI flows). Diff against that baseline — any NEW failure traceable to this change must be fixed before declaring done. Report the exact pass/fail counts; do not claim "tests pass" if any new failure appears.

---

## PART 2 — Scan-photo persistence (DEFERRED DESIGN — DO NOT BUILD IN THIS BRANCH)

**Why deferred:** unlike comps, the image does not currently exist to upload. In both the live bulk-scan (`Features/Scanning/Camera/CertOCRRecognizer.swift:137`) and the photo-scan path (`PhotoCertParser`), the camera frame is fed to OCR and **discarded** — only cert text + confidence survive. `scans.captured_photo_url` and `ScanDTO.capturedPhotoURL` are read on pull but never written. So this is a capture change, a storage change, and a sync change — materially larger than Part 1, and with no existing spec.

**Reusable infra that already exists (the easy parts):**
- Storage uploader pattern: `Core/Data/Repositories/GradePhotoUploader.swift:44` uses `client.storage.from("grade-photos").upload(path, data, options)`; auth (JWT) is automatic via `AppSupabase.shared.client`.
- Bucket migration pattern: `supabase/migrations/20260423130100_grade_photos_bucket.sql` (10 MB cap, JPEG/PNG, per-user RLS, path `<user_id>/<estimate_id>/...`).
- High-res still capture already implemented for the grading estimator: `Core/Vision/StillImageCapture.swift:54`.

**Open product decision to resolve before building (needs the user):** which image source?
- **(a) Still photo-scan path / `StillImageCapture`** — good quality, but only covers scans created from the photo-scan flow, not live bulk-scan.
- **(b) Retain the live bulk-scan frame** — covers every scan, but frames are downscaled for OCR (low quality) and retaining `CMSampleBuffer`s adds memory pressure during a fast stack scan.
- Recommendation to put to the user: start with (a) — capture-at-source where a high-res still already exists — and treat bulk-scan frame retention as a later enhancement.

**Coarse task outline (expand into bite-sized TDD when this branch is scheduled):**

1. **Decide + spec the image source** (a/b above). Write `docs/superpowers/specs/<date>-scan-photo-capture-design.md`.
2. **Bucket migration** — new `scan-photos` bucket + per-user RLS, mirroring `20260423130100_grade_photos_bucket.sql`. Path scheme `<user_id>/<scan_id>.jpg`.
3. **Capture retention** — thread the chosen image (downscaled + JPEG-compressed) from the capture site through to `BulkScanViewModel.record(candidate:)` / the photo-scan recorder. For source (a), the still is already in hand at the `StillImageCapture` delegate; carry it on the recorded candidate.
4. **Uploader** — extend or clone `GradePhotoUploader` into a `ScanPhotoUploader` writing to `scan-photos`, returning the stored path.
5. **Outbox kind** — add `OutboxKind.updateScanPhoto` (priority 10) + `OutboxPayloads.UpdateScanPhoto { id, captured_photo_url, updated_at }` + a drainer dispatch case patching `captured_photo_url` (exact mirror of `updateScanComp` from Part 1).
6. **Wire the flow** — after a scan inserts and its photo uploads, set `scan.capturedPhotoURL` locally + enqueue `updateScanPhoto`. (Upload is a network op; gate it so an offline scan still records and the photo syncs when connectivity returns — consider enqueuing the upload itself rather than blocking `record`.)
7. **Display** — surface the photo on the scan detail screen (reads `ScanDTO.capturedPhotoURL`, already pulled).
8. **Tests** — uploader path-construction unit test, drainer dispatch test for `updateScanPhoto`, and a capture-retention test.

---

## Self-Review

**Spec coverage:**
- Full snapshot fidelity → Task 2 (`CompSnapshotWire` carries headline, tier ladder, price history, sold listings, confidence, source). ✓
- Freeze at offer-send → Task 7 (`sendToOffer` → `.presented`). ✓
- Sync to Supabase → Tasks 1, 3, 4 (column + outbox kind + drainer patch). ✓
- Retrievable later → Task 6 (local `Scan` fields + detail-projection `ScanDTO` round-trip). Display surface is a follow-up (noted; not in scope this branch). ✓
- Photos planned, not built → Part 2. ✓

**Type consistency:** `compSnapshotJSON`/`compSnapshotAt` (Scan model), `compSnapshot`/`compSnapshotAt` (DTO, wire keys `comp_snapshot`/`comp_snapshot_at`), `UpdateScanComp` payload fields (`comp_snapshot`, `comp_snapshot_at`, `updated_at`), drainer patch keys (`comp_snapshot`, `comp_snapshot_at`, `updated_at`), SQL columns (`comp_snapshot`, `comp_snapshot_at`) — all aligned. `CompSnapshotWire.encode`/`.decode` names match call sites in Tasks 2 and 7. `OutboxKind.updateScanComp` consistent across Kind, Payload, Drainer, OfferUseCase, harness, tests.

**Placeholder scan:** every code step shows full code; commands include expected output; no TBD/TODO. ✓

**Known caveat surfaced:** comp blob is `text` not `jsonb` (not SQL-queryable) — intentional, documented. Cross-device retrieval depends on a scan pull path; on-device retrieval works immediately via local SwiftData.
