# Outbox Worker — Design Spec

**Date:** 2026-05-07
**Owner:** iOS app
**Problem:** Lots and scans created in the iOS app don't reach Supabase. The outbox-pattern producers exist (`LotsViewModel`, `BulkScanViewModel` enqueue `OutboxItem`s), but no consumer drains them. `public.lots` and `public.scans` stay at 0 rows.

## Goals

Build the outbox drainer that pushes pending `OutboxItem`s to Supabase reliably. After this ships, every lot, scan, edit, and delete the user makes appears in Supabase within seconds when the device is online — and is queued safely on-device when offline.

## Non-Goals (explicit)

- Not handling `OutboxKind.certLookupJob` or `priceCompJob`. Those dispatch to different endpoints (Edge Functions / RPC) and ship in a follow-up.
- No iOS `BGAppRefreshTask` / background-task wiring in v1. Drains happen only when the app is foregrounded.
- No "Sync issues" settings screen, retry-this-item UI, or list of `.failed` items in v1. They live in SwiftData for diagnostic queries; UI added later if telemetry says we need it.
- No server-side cascade on `deleteLot` (already noted in `OutboxPayloads.DeleteLot` comment — the producer enqueues per-scan deletes alongside).

## Scope

**In:** the seven CRUD `OutboxKind`s — `insertLot`, `updateLot`, `deleteLot`, `insertScan`, `updateScan`, `updateScanOffer`, `deleteScan`.

`updateLot` has no producer today, but it's added to the dispatch table now (with a new `OutboxPayloads.UpdateLot` struct) so the drainer's `switch` is exhaustive and a future producer is a one-line add.

## Architecture

Three new types, all under `Core/Sync/`:

| Type | Isolation | Responsibility |
|---|---|---|
| `OutboxDrainer` | `actor` (annotated `@ModelActor`) | Owns a background `ModelContext`. Runs the serial drain loop, dispatches by kind, classifies errors, mutates `OutboxItem` lifecycle. |
| `OutboxStatus` | `@MainActor @Observable final class` | Holds `pendingCount`, `isDraining`, `isPaused`, `lastError`. Bound to the SwiftUI status pill. |
| `OutboxKicker` | `@MainActor final class` | Single method `kick()` that does `Task.detached { await drainer.kick() }`. The thing producers and lifecycle hooks call. |

Plus one SwiftUI view: `SyncStatusPill` in `DesignSystem/`, bound to `OutboxStatus` + `Reachability`.

`OutboxDrainer` is constructed once at app launch with: shared `ModelContainer`, `RepositorySet` (already wired in `RepositoryProtocols.swift:110-111`), `Clock` (test seam), and a `MainActor` callback that publishes status updates to `OutboxStatus`. All three new types are injected via `.environment(...)`.

## Drain Loop

```
OutboxDrainer.kick():
    if isDraining { return }            # dedupe — one drain at a time
    isDraining = true
    publishStatus()
    defer { isDraining = false; publishStatus() }

    loop:
        let now = clock.now()
        let batch = fetch OutboxItem where
            status == .pending AND nextAttemptAt <= now
            ordered by kind.priority desc, createdAt asc
            fetchLimit 50

        if batch.isEmpty { break }

        for item in batch:
            item.status = .inFlight; save()
            do {
                try await dispatch(item)     # by item.kind
                context.delete(item)         # delete-on-success policy
                save()
            } catch let error {
                handle(error, item)          # see Error Handling
                save()
            }
            publishStatus()                  # pendingCount may have changed

    # If items remain with future nextAttemptAt, schedule a one-shot
    # Task.sleep until the earliest one and kick again.
```

**Dispatch table** (`switch item.kind`):

| Kind | Decoded payload | Repo call |
|---|---|---|
| `insertLot` | `OutboxPayloads.InsertLot` | `lots.insert(LotDTO(from: payload))` |
| `updateLot` | `OutboxPayloads.UpdateLot` *(new)* | `lots.patch(id:, fields:)` *(new helper)* |
| `deleteLot` | `OutboxPayloads.DeleteLot` | `lots.delete(id:)` |
| `insertScan` | `OutboxPayloads.InsertScan` | `scans.insert(ScanDTO(from: payload))` |
| `updateScan` | `OutboxPayloads.UpdateScan` | `scans.patch(id:, fields:)` *(new helper)* |
| `updateScanOffer` | `OutboxPayloads.UpdateScanOffer` | `scans.patch(id:, fields:)` |
| `deleteScan` | `OutboxPayloads.DeleteScan` | `scans.delete(id:)` |

**New repo helper:** `patch(id: UUID, fields: [String: AnyJSON])` on both `SupabaseLotRepository` and `SupabaseScanRepository` — needed because the existing `upsert(_ entity:)` requires a full row, but `UpdateScan` / `UpdateScanOffer` are partial. Small extension to those files, not a rewrite.

## Error Handling & Retry Policy

`OutboxDrainer.handle(error, item)` classifies errors into four buckets via a private `classify(error) -> Disposition` enum.

**1. Transient — retry forever with exponential backoff.**
Triggers: `URLError.notConnectedToInternet`, `.timedOut`, `.networkConnectionLost`, `.cannotFindHost`; HTTP 5xx; `URLError.cancelled` only if mid-flight at backgrounding.

Action:
- `item.attempts += 1`
- `item.lastError = "<short server/error message>"`
- `item.status = .pending` (back to the queue)
- `item.nextAttemptAt = now + min(2^attempts seconds, 5 min)`
- No max attempts.

**2. Conflict (idempotency) — treat as success.**
Triggers: HTTP 409 unique-violation on `insertLot` / `insertScan`. Means a previous attempt landed and the response was lost.

Action: `context.delete(item)`. Continue.

**3. Auth expired — pause queue, refresh, resume.**
Triggers: HTTP 401 (or `SupabaseError` mapped to auth-expired).

Action: stop the current drain pass, set `OutboxStatus.isPaused = true`, request `SessionStore.refreshAuth()` on MainActor.
- If refresh succeeds → `isPaused = false`, immediate kick.
- If refresh fails → `isPaused` stays true, `lastError = "Sign in again"`. Subsequent kicks no-op until session is re-established.

**4. Permanent — mark `.failed`, log, move on.**
Triggers: 4xx other than 401/409 (RLS denial 403, schema mismatch 400, validation 422); decode failure on payload.

Action:
- `item.status = .failed`
- `item.lastError = "<full server message, truncated to 1KB>"`
- `item.attempts += 1`
- OSLog at `.error`.
- Item is no longer fetched by the loop (predicate is `status == .pending`).

## Status Surface (Pill)

Pill placement: thin status strip at the top of `RootTabView`, height ~24pt. Auto-collapses to 0 height when state is "Up to date" so it's not permanent chrome.

| Snapshot | Pill |
|---|---|
| `pendingCount == 0 && !isDraining && reachable` | "Up to date" — collapsed/dim |
| `isDraining` | "Syncing N…" with small spinner |
| `pendingCount > 0 && !reachable` | "Offline — N pending" |
| `isPaused` (auth) | "Sign in to sync" — tappable, deep-links to `AuthView` |
| `pendingCount > 0 && reachable && !isDraining` | "Syncing N…" (same as drain — prevents flicker between drain ticks) |

Accessibility: `accessibilityIdentifier("sync-status-pill")`; `accessibilityLabel` reflects current state for VoiceOver.

`pendingCount` is updated by the drainer on every `publishStatus()` call (drain start/end, after each item) plus once on app foreground regardless of drainer state.

## Triggers

`OutboxKicker.kick()` is called from five places:

1. **Producer enqueue** — one new line after `try context.save()` in:
   - `Features/Lots/LotsViewModel.swift` — `createLot`, `setOfferCents`, `deleteScan`, `deleteLot`
   - `Features/Scanning/BulkScan/BulkScanViewModel.swift` — every `OutboxItem` insert site
   - Any `CertLookup` site that emits `updateScan` (kick is harmless even though that flow is technically out of scope for v1's dispatch coverage — the item will still drain through `updateScan`)

2. **App foreground** — `.onChange(of: scenePhase) { if .active { kicker.kick() } }` in `slabbistApp.swift`.

3. **Reachability online** — `.onChange(of: reachability.status)` → kick on `.online`. Requires flipping `Reachability(start: false)` to `.start()` after construction at app launch.

4. **Post-sign-in** — one line at the success leaf of `SessionStore.bootstrap()` (and the fresh-sign-in success path).

5. **Post auth-refresh recovery** — internal to the drainer; no external wiring.

`OutboxDrainer.kick()` is idempotent (early-returns on `isDraining`), so trigger overlap is free.

## Launch Order

`ModelContainer` → `SessionStore` → `Reachability.start()` → `RepositorySet` → `OutboxStatus` → `OutboxDrainer` → `OutboxKicker` → `.environment(...)` injection → first `kick()` fires from the post-sign-in trigger if the session restores from keychain.

## Testing Strategy

**Unit — `OutboxDrainerTests`:**
Fakes for everything in the actor's dependency set:
- `FakeLotRepository` / `FakeScanRepository` conforming to existing protocols (record calls, program responses).
- `TestClock` (custom or `Clock` protocol) for deterministic backoff math.
- In-memory `ModelContainer` (reuse `UITestEnvironment.resolveModelContainer()`).
- `MainActorStatusSink` capturing `OutboxStatus` updates.

Cases:
- Empty queue → no repo calls, status flips correctly.
- Single `insertScan` happy path → one call, item deleted.
- Mixed batch → ordering by `kind.priority` desc, then `createdAt` asc.
- 409 on insert → item deleted, no retry.
- 5xx then success → backoff sets `nextAttemptAt`, second kick after `TestClock.advance` succeeds.
- 401 → drain stops, `isPaused == true`, no further calls until session refresh.
- 403 / 422 → item flips to `.failed`, not re-fetched.
- Concurrent `kick()` calls → one drain pass, not two.
- Decode failure on corrupt payload → `.failed`, loop continues.

**Integration — `OutboxDrainerIntegrationTests`:**
Two tests against the project's shared dev Supabase. Skipped automatically when env unavailable so CI without secrets stays green.
- E2E `insertLot` then `insertScan` → rows actually appear in `public.lots` / `public.scans`.
- `deleteScan` after a successful insert → row gone.

**UI — XCUITest:**
One new test that scans a slab and asserts the status pill transitions through expected labels via `accessibilityIdentifier("sync-status-pill")`. Uses existing `UITestEnvironment` harness with stubbed deps.

**Test seams the implementation must support:**
1. `OutboxDrainer.init` accepts injected `RepositorySet` and `Clock`.
2. `kickAndWait()` test-only method that returns when current drain pass completes.
3. Constructible with in-memory `ModelContainer`.

## Out-of-Scope Reminders

- `certLookupJob`, `priceCompJob` — separate dispatch mechanism, follow-up spec.
- BGTaskScheduler — follow-up if telemetry shows long backgrounded queues.
- Failed-items UI — follow-up if `.failed` count becomes non-trivial.

## Acceptance

Implementation is complete when:

1. All unit / integration / UI tests above pass.
2. Manual smoke: create a lot in the app while online → row appears in `public.lots` within ~1s. Scan a slab → row appears in `public.scans`. Delete the scan → row removed.
3. Manual smoke offline: airplane mode, scan slab, see "Offline — N pending"; reconnect, see "Syncing…", then "Up to date"; row appears in Supabase.
4. **Implementation summary delivered as the final deliverable** — a short writeup of what shipped (files added/changed, line counts, test counts) accompanied by diagrams: a sequence diagram of a typical drain pass, and a state diagram of `OutboxItem` lifecycle (`pending → inFlight → completed/.failed/back to .pending`).

## Open Questions / Decisions Captured

- **Group A only for v1.** Group B (`certLookupJob`, `priceCompJob`) deferred.
- **Aggressive triggers** — foreground, post-sign-in, reachability online, post-enqueue.
- **Silent retry + status pill UI.** No dead-letter screen in v1.
- **Delete-on-success.** No retention of `.completed` items.
- **`@ModelActor` drainer + `@MainActor @Observable` status façade** as the architecture shape.
