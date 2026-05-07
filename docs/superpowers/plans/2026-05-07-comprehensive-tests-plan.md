# Comprehensive Test Coverage — Plan

**Goal:** Land a regression catchnet for the comp pipeline (resolver + iOS) so future changes (alias CSV edits, parser tweaks, UI changes) don't silently break working scans.

**Why now:** 93% cold-path hit rate just shipped. The system is at a known-good baseline; the tests freeze that baseline so we can iterate confidently.

---

## Layer A — Resolver naming-convention property tests (Edge Function)

**Files (new):**
- `supabase/functions/price-comp/__tests__/tcg-products-property.test.ts`
- `supabase/functions/price-comp/__tests__/match-property.test.ts`
- `supabase/functions/price-comp/__tests__/aliases-property.test.ts`

**Coverage:**

`tcg-products-property.test.ts`:
- card_number normalization across formats: `"4"`, `"04"`, `"004"`, `"04/62"`, `"199/165"`, `"XY174"`, `"SWSH285"`, `"020/M-P"`, `"217/187"`, `null`. Each test feeds a fake-Supabase rowset and asserts the resolver picks the right product_id.
- Asymmetric zero-padding: PSA `"4"` matches tcg `"04/62"`; PSA `"020"` matches tcg `"020/198"`; PSA `"199"` matches tcg `"199/165"`. All variants resolved to the same product when in the same group.
- Multiple-name matches in a group with a card_number disambiguator: name+number unique combo wins over name-only.
- Null card_number: returns null when the group has multiple name-matches; returns the unique product when one name-match exists.

`match-property.test.ts`:
- `scoreCard` thresholds: name-miss → reject; name+exact_number → accept; name+set_overlap≥2 → accept; name only → not accepted unless other tiers escalate.
- Resolver tier escalation: A miss → B; B miss → C; C miss → D; all miss → null with `attemptLog` populated.
- Resolver respects the alias map: a PSA name with an alias entry skips B/C/D when A succeeds.

`aliases-property.test.ts`:
- A handful of "load-bearing" alias entries you've verified — these snapshot the curated CSV. If someone edits the CSV and breaks one, this test fails.
  - `Base Set` → 604
  - `Prismatic Evolutions` → 23821
  - `Scarlet & Violet 151` → 23237
  - `Champion's Path ETB Promo` → 2685
  - `M-P Promo` → 24423
  - `SV-P Promo` → 22872
  - `Terastal Festival ex` → 23909

**Effort:** 1 subagent (sonnet), ~2-3 hours.

---

## Layer B — Resolver regression suite vs. real identities

**Files (new):**
- `supabase/functions/price-comp/__tests__/regression.test.ts`
- `supabase/functions/price-comp/__fixtures__/regression-baseline.json` (frozen snapshot of identity + tcg_products + expected outcome)

**How it works:**
1. One-time: capture a representative ~20-identity sample of real `graded_card_identities`, the matching `tcg_groups` rows for each set, and the matching `tcg_products` rows. Save as JSON.
2. Capture the expected outcome per identity: `{ tcgPlayerId, tierMatched, resolvedLanguage }` from a current-deployment run.
3. Test runs `resolveCard()` against an in-memory fake Supabase that returns the frozen rows. Asserts the actual outcome matches the baseline.
4. PPT calls are NOT mocked at the network level — instead, mock `fetchCard()` to return synthetic responses derived from the baseline. (Otherwise the test depends on PPT's live state.)

**Re-baselining:** when an alias CSV change (or scoring tweak) is intended to flip outcomes, you re-run the capture script and commit the new baseline. The diff in the JSON file documents the intentional change.

**Effort:** 1 subagent (sonnet), ~3-4 hours including baseline capture.

---

## Layer C — iOS comp-fetch end-to-end

**Files (new):**
- `ios/slabbist/slabbistTests/Features/Comp/CompFetchE2ETests.swift`
- `ios/slabbist/slabbistTests/Helpers/MockURLProtocol.swift` (URLProtocol-based URLSession mock)
- `ios/slabbist/slabbistTests/Helpers/InMemoryModelContainer.swift` (SwiftData test container helper)

**Cases (each a separate test):**
1. Happy path: scan triggers fetch, mock returns full payload, scan transitions `.fetching → .resolved`, snapshot persisted in SwiftData with the right tier values.
2. Network failure (URLError.timedOut): scan ends `.failed` with the right user-facing message, no snapshot persisted.
3. 404 IDENTITY_NOT_FOUND: scan ends `.failed` with "Card identity not on file…" message.
4. 404 PRODUCT_NOT_RESOLVED: scan ends `.noData` with "We couldn't find this card on Pokemon Price Tracker." message.
5. 404 NO_MARKET_DATA: scan ends `.noData` with the supported-tier copy.
6. 502 AUTH_INVALID: scan ends `.failed` with the "Comp lookup misconfigured" message.
7. 503 UPSTREAM_UNAVAILABLE: scan ends `.failed`.
8. Stale-fallback (200 with `is_stale_fallback: true`): snapshot persisted with `isStaleFallback: true`; CompCardView would show the stale chip.
9. JP card (only `loose_price_cents` populated, all PSA tiers null): snapshot persisted; ladder renders empty except Raw cell; no caveat row.
10. Decoding error (malformed JSON): scan ends `.failed` with `Couldn't decode comp response…`.
11. In-flight de-dup: two concurrent calls for same `(identity, grader, grade)` — exactly one network request, both scans flip when it lands.

**Effort:** 1 subagent (opus), ~3-4 hours including helper setup.

---

## Layer D — iOS UI snapshot tests

**Dependency:** Add `pointfreeco/swift-snapshot-testing` v1.x as a SPM dep in the test target.

**Files (new):**
- `ios/slabbist/slabbistTests/Features/Comp/CompCardViewSnapshotTests.swift`
- `ios/slabbist/slabbistTests/Features/Comp/CompSparklineViewSnapshotTests.swift`
- `ios/slabbist/slabbistTests/__Snapshots__/` (auto-generated reference images)

**CompCardView snapshots (each in light + dark mode):**
1. PSA 10 full ladder + sparkline + good headline
2. BGS 10 headline (gold border on BGS cell, not PSA)
3. JP card (raw only, no ladder, no sparkline)
4. Stale fallback (caveat row visible)
5. Unsupported tier (TAG 10 — caveat with copy)
6. Empty state (all tiers null)

**CompSparklineView snapshots:**
1. 30-point series across 6 months (typical EN card)
2. 7-point series (typical JP card)
3. 2-point series (minimum)
4. 1-point series (hidden)
5. Empty (hidden)
6. Flat-price series (all same value)

**Effort:** 1 subagent (opus), ~3-4 hours including SPM setup and initial snapshot capture.

---

## Layer E — Diagnostic tooling

**Files (new):**
- `scripts/probe-resolver.ts` — calls `/price-comp` against every identity, outputs `docs/data/resolver-probe-<date>.csv`
- `scripts/audit-aliases.ts` — loads alias CSV, verifies group_id exists in tcg_groups, abbreviation matches, year is plausible. Reports inconsistencies.
- `scripts/validate-csv.ts` — strict CSV schema check; runnable as a pre-commit hook.

**Each is a standalone Deno script** with shebang + clear usage docstring. Lives outside `supabase/functions/` so it's not bundled into the Edge Function deploy.

**Effort:** 1 subagent (sonnet), ~2 hours.

---

## Execution order

1. **Parallel:** A + E (independent of each other and of B/C/D)
2. **Sequential after A:** B (uses A's helpers, e.g., the in-memory fake-Supabase)
3. **Parallel:** C + D (both iOS, independent)

## Reporting per layer

Each subagent reports:
- Git SHAs
- Test pass count delta
- One-line summary of what's covered
- Any concerns / known gaps

Final state: `~150+` Edge Function tests, `~30+` iOS tests, 3 diagnostic scripts in `scripts/`.
