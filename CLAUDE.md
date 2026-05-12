# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## Rule 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## Rule 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## Rule 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## Rule 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## Rule 5. Use the model only for judgment calls
Use Claude for: classification, drafting, summarization, extraction from unstructured text.
Do NOT use Claude for: routing, retries, status-code handling, deterministic transforms.
If a status code already answers the question, plain code answers the question.

## Rule 6. Token budgets are not advisory
Per-task budget: 4,000 tokens.
Per-session budget: 30,000 tokens.
If a task is approaching budget, summarize and start fresh. Do not push through.
Surfacing the breach > silently overrunning.

## Rule 7. Surface conflicts, don't average them
If two existing patterns in the codebase contradict, don't blend them.
Pick one (the more recent / more tested), explain why, and flag the other for cleanup.
"Average" code that satisfies both rules is the worst code.

## Rule 8. Read before you write
Before adding code in a file, read the file's exports, the immediate caller, and any obvious shared utilities.
If you don't understand why existing code is structured the way it is, ask before adding to it.
"Looks orthogonal to me" is the most dangerous phrase in this codebase.

## Rule 9. Tests verify intent, not just behavior
Every test must encode WHY the behavior matters, not just WHAT it does.
A test like `expect(getUserName()).toBe('John')` is worthless if the function takes a hardcoded ID.
If you can't write a test that would fail when business logic changes, the function is wrong.

## Rule 10. Checkpoint after every significant step
After completing each step in a multi-step task: summarize what was done, what's verified, what's left.
Don't continue from a state you can't describe back to me.
If you lose track, stop and restate.

## Rule 11. Match the codebase's conventions, even if you disagree
If the codebase uses snake_case and you'd prefer camelCase: snake_case.
If the codebase uses class-based components and you'd prefer hooks: class-based.
Disagreement is a separate conversation. Inside the codebase, conformance > taste.
If you genuinely think the convention is harmful, surface it. Don't fork it silently.

## Rule 12. Fail loud
If you can't be sure something worked, say so explicitly.
"Migration completed" is wrong if 30 records were skipped silently.
"Tests pass" is wrong if you skipped any.
"Feature works" is wrong if you didn't verify the edge case I asked about.
Default to surfacing uncertainty, not hiding it.

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

## Repo

Slabbist is an iOS-first app for **hobby-store vendors / buy-side dealers** comping Pokémon slabs to make defensible offers. Buy-side tool, not a collector vault — IA is **Lots / Scans / Comps / Offers**, even when mockups speak collector language.

Monorepo, one shared Supabase project:

| Path | Stack | Purpose |
|---|---|---|
| `ios/slabbist/` | SwiftUI + SwiftData, iOS 26.4 | The product. Offline-first. |
| `dashboard/` | Next.js 16.2.4, React 19, Tailwind v4, Bun | Buy-side operator web (early). |
| `marketing/` | Next.js 16.2.4, React 19, Tailwind v4, Bun | Marketing site. |
| `scraper/` | TS + Bun + Vitest, `@slabbist/tcgcsv` | Cron ingest. Never defines schema. |
| `supabase/` | Postgres 17 + Edge Functions (Deno 2) | **Single source of truth for schema, RLS, Edge Functions.** |
| `docs/superpowers/{specs,plans}/` | — | Canonical specs/plans. **Read before changing a feature.** |
| `.impeccable.md` | — | **Canonical design direction** across UI surfaces. |

## Commands

- **Env:** repo uses **direnv** — `.envrc` exports `SUPABASE_*`, `EPN_*`. Run `direnv allow` after editing. Launch Xcode from a direnv shell so env propagates to iOS builds.
- **Supabase:** schema lives only in `supabase/migrations/` (timestamp-prefixed `YYYYMMDDHHMMSS_<desc>.sql`). `supabase db push` applies; `supabase functions deploy <fn>` ships an Edge Function; `psql "$DATABASE_URL" -f supabase/tests/<file>.sql` runs RLS tests. If push errors "relation already exists", INSERT into `supabase_migrations.schema_migrations` rather than re-running DDL.
- **Scraper:** `cd scraper && bun install`. `bun run typecheck` / `bun run test` / `bun run cli run raw tcgcsv` (daily) / `bun run cli run graded ebay` (6h, watchlist) / `bun run cli run graded pop -s all` (weekly) / `bun run cli seed popular-slabs`.
- **Dashboard / Marketing:** `cd {dashboard,marketing} && bun install && bun dev | bun run build | bun run lint`.
- **iOS:** `open ios/slabbist/slabbist.xcodeproj`. Scheme `slabbist`; tests `slabbistTests` / `slabbistUITests`. CLI: `xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`. Archive/CI/TestFlight: fill `ios/slabbist/Config/Secrets.xcconfig` from the example.
- **Deno scripts:** `./scripts/validate-csv.ts` (offline), `./scripts/audit-aliases.ts` (live), `./scripts/probe-resolver.ts` (price-comp hit-rate).

## Critical architecture rules

1. **Next.js 16 is NOT what you remember.** `dashboard/` and `marketing/` pin Next 16.2.4 + React 19. Read `node_modules/next/dist/docs/` before writing — APIs differ from training data.
2. **Raw and graded data are decoupled.** `tcg_*` and `graded_*` tables have no FKs, shared identities, or join tables. Side-by-side UX is a presentation concern.
3. **Schema lives in `supabase/migrations/` only.** Other surfaces read/write Postgres but never define schema locally.
4. **iOS is offline-first via the outbox.** All writes go through `OutboxDrainer` (`ios/slabbist/slabbist/Core/Sync/`); repos under `Core/Data/Repositories/` are the only layer talking to Supabase. New write surfaces extend `OutboxKind`/`OutboxPayloads` + the drainer.
5. **Multi-tenant by default.** All data tables are `store_id`-scoped with RLS; new tables need RLS policies tested in `supabase/tests/rls_*.sql`.
6. **iOS hero flow: scraper → tables → Edge Function → app.** `price-comp` reads `graded_market`/`tcg_*`; `cert-lookup` proxies grader APIs. iOS never adds raw aggregator logic. When wiring a new Edge Function shape, do a live `Decodable` round-trip — curl misses shape mismatches.
7. **eBay ingest is a watchlist, not the whole catalog.** `graded_watchlist` is curated; scans auto-promote (`promote_scanned_slabs_to_watchlist`, ≥5 distinct certs / 7 days). Arbitrary on-demand lookups happen on-device.
8. **Design system is non-negotiable.** `.impeccable.md` specifies dark+gold OKLCH palette, Instrument Serif + Inter Tight + JetBrains Mono / .monospaced SF, 4pt spacing, 18/14 radii, WCAG 2.2 AA. Mockups in `docs/design/ios-mockup/` are visual reference only — their collector IA ("vault", "portfolio") must not leak into product IA. Spec > mockup.

## SwiftUI, specs, MCP

- **SwiftUI:** invoke `swiftui-expert-skill` and pass its rules into subagent prompts. SwiftData container resolves via `UITestEnvironment.resolveModelContainer()` (in-memory under XCUITests); UI tests bootstrap synthetic auth via `UITestEnvironment.bootstrapIfActive(...)` — use `slabbistUITests/UITestApp.swift` as the harness pattern.
- **Specs/plans:** check `docs/superpowers/specs/` and `docs/superpowers/plans/` before non-trivial product work; if your task conflicts with a spec, raise it before coding.
- **MCP:** `.mcp.json` wires Supabase MCP (project `ksildxueezkvrwryybln`) and GitHub MCP — prefer them over re-implementing API calls. `skills-lock.json` pins external skills (auto-installed under `.agents/skills/`).
