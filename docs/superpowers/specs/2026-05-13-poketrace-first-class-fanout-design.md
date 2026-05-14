# Poketrace First-Class Fan-out — Design

**Status:** Approved  
**Author:** phil + Claude  
**Date:** 2026-05-13  
**Predecessor:** `2026-05-08-poketrace-comp-design.md`

## Summary

Refactor `price-comp/index.ts` so Poketrace runs as a first-class pricing source in parallel with PPT, not sequentially after it. PPT failures (NO_MARKET_DATA, PRODUCT_NOT_RESOLVED, upstream errors) no longer block Poketrace. The first scan of a brand-new card gets Poketrace data on the same request where PPT first resolves the card identity — the freshly resolved TCGPlayer ID is passed directly into the Poketrace cross-walk before either price fetch begins.

No changes to any module outside `index.ts`. No iOS changes required.

## Motivation

The V1 implementation runs PPT first and short-circuits the entire request on any PPT failure, meaning Poketrace never executes. The spec explicitly called this out as a known limitation. Additionally, even when PPT succeeds on a cold first-scan, Poketrace receives the original `null` `ppt_tcgplayer_id` from the identity read (before PPT persisted the newly resolved ID), so the cross-walk always fails on first scan regardless of PPT's outcome. This design fixes both problems.

## Architecture

`handle()` is restructured into three sequential phases. Each phase has a clear input, output, and failure contract.

```
Phase 1: PPT Identity Resolution
   ↓ PPTResolution | null
Phase 2: Parallel price fan-out
   Promise.allSettled([processPPTCard(), fetchPoketraceBranch()])
   ↓ pptData | null, poketraceBlock | null
Phase 3: Response assembly
   reconcile → 200 | 404
```

### Phase 1 — PPT Identity Resolution

New helper: `resolvePPTIdentity(identity, deps, cached): Promise<PPTResolution | null>`

Runs the existing warm/cold PPT logic unchanged:
- **Warm path** (`ppt_tcgplayer_id` cached): calls `fetchCard`. Language fallback (English → Japanese) preserved.
- **Cold path** (no cached ID): calls `resolveCard` multi-tier resolver.

On success, immediately persists the resolved TCGPlayer ID to `graded_card_identities` (unchanged from current behaviour). Returns a `PPTResolution`:

```ts
interface PPTResolution {
  card: PPTCard;
  resolvedTCGPlayerId: string;
  resolvedLanguage: "english" | "japanese";
  resolverTier: string | null;
  creditsConsumed: number | undefined;
}
```

On failure, returns `null` for soft failures, or throws a short-circuit `Response` for hard failures (see Failure Modes below). The caller catches short-circuit throws before Phase 2.

### Phase 2 — Parallel Price Fan-out

```ts
const freshTCGPlayerId =
  phase1?.resolvedTCGPlayerId ?? identity.ppt_tcgplayer_id ?? null;

const [pptResult, ptResult] = await Promise.allSettled([
  Promise.resolve(phase1 ? processPPTCard(phase1, body, identity) : null),
  fetchPoketraceBranch(deps, {
    id: identity.id,
    ppt_tcgplayer_id: freshTCGPlayerId,
    poketrace_card_id: identity.poketrace_card_id ?? null,
    poketrace_card_id_resolved_at: identity.poketrace_card_id_resolved_at ?? null,
  }, body.grading_service, body.grade),
]);
```

`processPPTCard()` is a **pure synchronous transform**: extracts ladder, picks headline tier, parses price history, builds the PPT response object, and schedules market persistence. No additional HTTP. It replaces the inline price-extraction code currently in `handle()` after the warm/cold path.

`fetchPoketraceBranch()` is unchanged. The key improvement: it now receives `freshTCGPlayerId` — the TCGPlayer ID that PPT just resolved and persisted in Phase 1 — rather than whatever was on the identity at request time (which was null on first scan).

### Phase 3 — Response Assembly

| PPT result | Poketrace result | HTTP | `reconciled.source` |
|---|---|---|---|
| data | data | 200 | `"avg"` or `"poketrace-preferred"` |
| data | null | 200 | `"ppt-only"` |
| null | data | 200 | `"poketrace-only"` |
| null | null | 404 | — (`code: "PRODUCT_NOT_RESOLVED"`) |

The existing `reconcile()` function and `buildResponse()` shape are unchanged. When PPT is null, `buildResponse` is not called; the response is assembled directly from the Poketrace block under the existing `PriceCompResponseV2` envelope with PPT fields set to null.

## Failure Modes

### Phase 1 failure taxonomy

| Failure | Classification | Behaviour |
|---|---|---|
| 401 / 403 (AUTH_INVALID) | Hard (short-circuit) | Return 502 immediately. PPT mis-config must surface. |
| 429 / 5xx **with** stale cache | Soft (use stale) | PPT branch uses stale data; Poketrace runs live. |
| 429 / 5xx **without** stale cache | Soft (null) | PPT branch = null; Poketrace runs live. |
| NO_MARKET_DATA (ladder empty) | Soft (null) | PPT branch = null; Poketrace runs live. |
| PRODUCT_NOT_RESOLVED | Soft (null) | PPT branch = null; Poketrace runs live. |

### Phase 2 failures

Each provider is independently isolated via `Promise.allSettled`. A rejected promise on either branch is logged and treated as null for that branch. Existing per-provider error logging is preserved.

### Both providers fail

Returns `json(404, { code: "PRODUCT_NOT_RESOLVED" })`. This is a change from current behaviour where PPT failures alone produced the 404 — now both must fail to surface the error to iOS.

## Cache-Hit Path

The existing cache-hit path (with Poketrace backfill) is **unchanged**. It already handles both sources independently and is not affected by this refactor.

## Persistence

No schema changes. `upsertMarketLadder` calls are unchanged in signature and semantics. The only difference is that Poketrace persistence may now succeed on scans where it previously always failed (first scan of a new card).

## What Changes

**`supabase/functions/price-comp/index.ts`** — sole file modified:
- Extract `resolvePPTIdentity(identity, deps, cached): Promise<PPTResolution | null>` from the inline warm/cold path.
- Extract `processPPTCard(resolution, body, identity): PPTData` (synchronous) from the inline price-extraction block.
- Rewrite the live-fetch section of `handle()` to use Phase 1 → Phase 2 → Phase 3 structure.
- Update `staleOrUpstreamDown` so a 429/5xx stale-fallback for PPT no longer returns immediately — it continues to Phase 2 with stale PPT data alongside a live Poketrace fetch.

**No other files change:** `match.ts`, `prices.ts`, `history.ts`, `client.ts`, `parse.ts`, `persistence/market.ts`, `lib/`, `cache/` — all untouched.

## Testing

### New test cases for `__tests__/index.test.ts` (or `index-fanout.test.ts`)

- PPT returns PRODUCT_NOT_RESOLVED, Poketrace has data → 200 with `poketrace-only`.
- PPT returns NO_MARKET_DATA, Poketrace has data → 200 with `poketrace-only`.
- PPT resolves new card (cold path, no prior `ppt_tcgplayer_id`), Poketrace cross-walk succeeds on same request → 200 with `avg`.
- PPT 5xx with stale cache, Poketrace live → 200 with stale PPT + fresh Poketrace.
- Both fail → 404 PRODUCT_NOT_RESOLVED.
- PPT AUTH_INVALID → 502 short-circuit (Poketrace does not run).

### Existing tests

All existing `__tests__/` files pass unchanged — the individual modules are untouched.

## Non-Goals

- Dedicated `POKETRACE_FRESHNESS_TTL_SECONDS` env var (deferred from V1, still deferred).
- 429 daily-budget short-circuit for Poketrace (deferred from V1, still deferred).
- Watchlist-side bulk Poketrace refresh (deferred from V1, still deferred).
- iOS UI changes.
