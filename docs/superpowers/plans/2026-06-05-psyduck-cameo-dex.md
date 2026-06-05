# Psyduck Cameo Dex Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A hidden Psyduck peeks from the edge of every iOS screen; tapping it opens a full-screen, tab-less "Cameo Dex" that browses/searches every Pokémon & Trainer that appears as a cameo on TCG cards, each card deep-linking to an affiliate-wrapped TCGplayer search.

**Architecture:** Two new global-reference Supabase tables (`cameo_subjects`, `cameo_cards`, public-read RLS like `tcg_*`), populated by a re-runnable Deno seed script that parses the 10 forward-filled CSVs. iOS reads them PostgREST-direct through a `CameoRepository` (no edge function), builds TCGplayer **search** affiliate URLs at render time, and surfaces everything through a `.fullScreenCover` triggered by a `PsyduckPeekOverlay` in `RootTabView`.

**Tech Stack:** Postgres 17 + RLS (pgTAP tests), Deno (seed script + `Deno.test`), Swift 6 / SwiftUI / Supabase SDK, Swift Testing (`@Suite`/`@Test`).

**Source spec:** `docs/superpowers/specs/2026-06-05-psyduck-cameo-dex-design.md`

---

## File structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260605140000_cameo_dex.sql` | DDL + public-read RLS for `cameo_subjects`, `cameo_cards` |
| `supabase/tests/rls_cameo.sql` | pgTAP: anon select allowed, anon insert denied |
| `scripts/cameo_parse.ts` | Pure `parseCameoSheet()` — the forward-fill logic |
| `scripts/cameo_parse.test.ts` | `Deno.test` for the parser |
| `scripts/seed-cameos.ts` | Reads CSVs → parses → rebuilds the two tables via service role |
| `ios/.../Core/Utilities/TCGPlayerAffiliateLink.swift` | **Modify**: add `searchLink(query:subId:)` |
| `ios/.../slabbistTests/Core/TCGPlayerAffiliateLinkTests.swift` | **Modify**: add search-link tests |
| `ios/.../Core/Data/DTOs/CameoSubjectDTO.swift` | `CameoSubjectDTO` model |
| `ios/.../Core/Data/DTOs/CameoCardDTO.swift` | `CameoCardDTO` model |
| `ios/.../Core/Data/Repositories/CameoRepository.swift` | `searchSubjects` / `cards(forSubject:)` |
| `ios/.../slabbistTests/Core/CameoDTODecodeTests.swift` | Decode round-trip vs real PostgREST shape |
| `ios/.../Core/DesignSystem/Components/TCGPlayerSearchLinkButton.swift` | Search-URL affiliate button |
| `ios/.../Assets.xcassets/Psyduck.imageset/` | The peeking artwork |
| `ios/.../Features/Cameo/PsyduckPeekOverlay.swift` | The edge-peek hit target |
| `ios/.../Features/Cameo/CameoSecretView.swift` | Full-screen cover: search + subject list |
| `ios/.../Features/Cameo/CameoSubjectDetailView.swift` | One subject's cards + TCGplayer buttons |
| `ios/.../Features/Shell/RootTabView.swift` | **Modify**: overlay + `.fullScreenCover` |

> All iOS paths are under `ios/slabbist/slabbist/`. SwiftUI work: invoke `swiftui-expert-skill` and pass its rules into any subagent prompt (project rule).

---

## Task 1: Schema migration + RLS

**Files:**
- Create: `supabase/migrations/20260605140000_cameo_dex.sql`
- Create: `supabase/tests/rls_cameo.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260605140000_cameo_dex.sql`:

```sql
-- Cameo Dex: global reference data (same class as tcg_*/graded_*).
-- Not store-scoped. Public read; writes only via service role (seed script).

create table if not exists public.cameo_subjects (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('pokemon','trainer')),
  ndex        int,
  region      text,
  name        text not null,
  card_count  int  not null default 0,
  unique (kind, name)
);

create table if not exists public.cameo_cards (
  id           uuid primary key default gen_random_uuid(),
  subject_id   uuid not null references public.cameo_subjects(id) on delete cascade,
  card_name    text not null,
  set_name     text not null,
  card_number  text,
  notes        text,
  generation   text not null
);
create index if not exists cameo_cards_subject_id_idx on public.cameo_cards(subject_id);
create index if not exists cameo_subjects_name_idx on public.cameo_subjects(name);

-- Public-read RLS, mirroring the tcg_* pattern. No write policy: the seed
-- script connects with the service role, which bypasses RLS.
do $$
declare t text;
begin
  foreach t in array array['cameo_subjects','cameo_cards'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_public_read', t);
    execute format('create policy %I on public.%I for select using (true)', t || '_public_read', t);
  end loop;
end $$;
```

- [ ] **Step 2: Write the RLS test**

Create `supabase/tests/rls_cameo.sql` (mirrors `rls_graded_market_sales.sql`):

```sql
-- cameo_subjects / cameo_cards: anyone may read; only service-role may write.
begin;
create extension if not exists pgtap;
select plan(4);

-- Service-role-equivalent (superuser) write succeeds — the seed-script path.
select lives_ok($$
  insert into public.cameo_subjects (id, kind, ndex, name, card_count)
  values ('22222222-2222-2222-2222-222222222222', 'pokemon', 25, 'Pikachu', 1);
$$, 'service-role can insert a cameo subject');

select lives_ok($$
  insert into public.cameo_cards (subject_id, card_name, set_name, card_number, generation)
  values ('22222222-2222-2222-2222-222222222222', 'Pokémon March', 'Neo Genesis', '102', 'Gen 2');
$$, 'service-role can insert a cameo card');

-- Become an authenticated end-user.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated"}', true);

select lives_ok($$ select 1 from public.cameo_subjects limit 1; $$,
  'authenticated can select cameo subjects');

select throws_ok($$
  insert into public.cameo_subjects (kind, name) values ('pokemon', 'Bulbasaur');
$$, NULL, 'authenticated cannot insert cameo subjects');

select * from finish();
rollback;
```

- [ ] **Step 3: Apply the migration**

Run: `supabase db push`
Expected: applies `20260605140000_cameo_dex.sql` with no error.
(If it errors "relation already exists", reconcile the ledger per the project rule — `INSERT INTO supabase_migrations.schema_migrations` — rather than re-running DDL.)

- [ ] **Step 4: Verify RLS functionally over REST (no DATABASE_URL in this env)**

The repo's `.envrc` exports no direct Postgres connection string, so the pgTAP file
(`rls_cameo.sql`) is committed as a CI/documentation artifact but is verified here
**functionally over PostgREST** with the anon (publishable) key. In a direnv-allowed shell:

```bash
eval "$(direnv export bash)"
# anon SELECT must succeed (200)
curl -s -o /dev/null -w "select=%{http_code}\n" \
  "$SUPABASE_URL/rest/v1/cameo_subjects?select=id&limit=1" \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY" -H "Authorization: Bearer $SUPABASE_PUBLISHABLE_KEY"
# anon INSERT must be denied (401/403)
curl -s -o /dev/null -w "insert=%{http_code}\n" -X POST \
  "$SUPABASE_URL/rest/v1/cameo_subjects" \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY" -H "Authorization: Bearer $SUPABASE_PUBLISHABLE_KEY" \
  -H "Content-Type: application/json" -d '{"kind":"pokemon","name":"RLS Probe"}'
```
Expected: `select=200` and `insert=401` (or `403`). Anyone with a `DATABASE_URL` can
additionally run `psql "$DATABASE_URL" -f supabase/tests/rls_cameo.sql` → `ok 1..4`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260605140000_cameo_dex.sql supabase/tests/rls_cameo.sql
git commit -m "feat(cameo): cameo_subjects/cameo_cards tables + public-read RLS"
```

---

## Task 2: CSV parser (pure function, TDD)

The CSVs are forward-filled at two levels (see spec). This task builds and tests the pure parser in isolation — it does **no** I/O.

**Files:**
- Create: `scripts/cameo_parse.ts`
- Test: `scripts/cameo_parse.test.ts`

- [ ] **Step 1: Write the failing test**

Create `scripts/cameo_parse.test.ts`. The fixture exercises the three tricky cases: a new subject, a **reprint** (blank card name, new set), and a **subject boundary** (next cameo resets the card name).

```ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseCameoSheet } from "./cameo_parse.ts";

// Rows are header-stripped, position-based arrays:
// [Ndex/region, CameoName, CardName, Set, #, Notes]
Deno.test("forward-fills subject, reprints, and resets card at the next subject", () => {
  const rows = [
    ["152", "Chikorita", "Pokémon March", "Neo Genesis", "102", ""],
    ["", "", "", "Unseen Forces", "89", "reprint"],   // reprint: blank card name
    ["", "", "Professor Elm", "Expedition", "148", ""], // new card, same subject
    ["155", "Cyndaquil", "Switch", "Neo Genesis", "94", ""], // new subject resets card
  ];

  const subjects = parseCameoSheet(rows, { generation: "Gen 2", kind: "pokemon" });

  assertEquals(subjects.length, 2);

  assertEquals(subjects[0], {
    kind: "pokemon", ndex: 152, region: null, name: "Chikorita",
    cards: [
      { cardName: "Pokémon March",  setName: "Neo Genesis",  cardNumber: "102", notes: "",        generation: "Gen 2" },
      { cardName: "Pokémon March",  setName: "Unseen Forces", cardNumber: "89",  notes: "reprint", generation: "Gen 2" },
      { cardName: "Professor Elm",  setName: "Expedition",    cardNumber: "148", notes: "",        generation: "Gen 2" },
    ],
  });

  assertEquals(subjects[1].name, "Cyndaquil");
  assertEquals(subjects[1].cards[0].cardName, "Switch"); // did NOT bleed "Professor Elm"
});

Deno.test("trainer sheet forward-fills region from column 0", () => {
  const rows = [
    ["KANTO", "Red",  "Red's Pikachu", "SM-P Promos",    "270", ""],
    ["",      "",     "Pikachu",       "Cosmic Eclipse", "241", ""], // same region+subject
    ["",      "Blue", "Blue's Pikachu","SV Promos",      "1",   ""], // new subject, region carries
  ];

  const subjects = parseCameoSheet(rows, { generation: "Trainers", kind: "trainer" });

  assertEquals(subjects[0], {
    kind: "trainer", ndex: null, region: "KANTO", name: "Red",
    cards: [
      { cardName: "Red's Pikachu", setName: "SM-P Promos",    cardNumber: "270", notes: "", generation: "Trainers" },
      { cardName: "Pikachu",       setName: "Cosmic Eclipse", cardNumber: "241", notes: "", generation: "Trainers" },
    ],
  });
  assertEquals(subjects[1], {
    kind: "trainer", ndex: null, region: "KANTO", name: "Blue",
    cards: [
      { cardName: "Blue's Pikachu", setName: "SV Promos", cardNumber: "1", notes: "", generation: "Trainers" },
    ],
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `deno test scripts/cameo_parse.test.ts`
Expected: FAIL — `Module not found "./cameo_parse.ts"`.

- [ ] **Step 3: Write the parser**

Create `scripts/cameo_parse.ts`:

```ts
export type ParsedCard = {
  cardName: string;
  setName: string;
  cardNumber: string;
  notes: string;
  generation: string;
};

export type ParsedSubject = {
  kind: "pokemon" | "trainer";
  ndex: number | null;
  region: string | null;
  name: string;
  cards: ParsedCard[];
};

type SheetOpts = { generation: string; kind: "pokemon" | "trainer" };

/**
 * Turns position-based, header-stripped CSV rows into subjects with their
 * cards. Handles two independent forward-fills:
 *   - column 0 (ndex for pokemon, region for trainers) and column 1 (name)
 *     forward-fill down; a non-empty column 1 starts a new subject.
 *   - column 2 (card name) forward-fills down within a subject; a reprint row
 *     leaves it blank but supplies a new set/number. A new subject always
 *     carries its own card name, which replaces the running one.
 * Fully-empty rows are skipped.
 */
export function parseCameoSheet(rows: string[][], opts: SheetOpts): ParsedSubject[] {
  const subjects: ParsedSubject[] = [];
  let current: ParsedSubject | null = null;
  let region: string | null = null;   // trainer region carries across subjects
  let cardName = "";

  for (const row of rows) {
    const col0 = (row[0] ?? "").trim();
    const name = (row[1] ?? "").trim();
    const rawCard = (row[2] ?? "").trim();
    const setName = (row[3] ?? "").trim();
    const cardNumber = (row[4] ?? "").trim();
    const notes = (row[5] ?? "").trim();

    if (!col0 && !name && !rawCard && !setName && !cardNumber && !notes) continue;

    if (opts.kind === "trainer" && col0) region = col0;

    if (name) {
      current = {
        kind: opts.kind,
        ndex: opts.kind === "pokemon" ? (col0 ? Number(col0) : null) : null,
        region: opts.kind === "trainer" ? region : null,
        name,
        cards: [],
      };
      subjects.push(current);
      cardName = ""; // reset; this row's card name is set next
    }

    if (rawCard) cardName = rawCard;
    if (!current) continue; // defensive: data before any subject

    current.cards.push({
      cardName,
      setName,
      cardNumber,
      notes,
      generation: opts.generation,
    });
  }

  return subjects;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `deno test scripts/cameo_parse.test.ts`
Expected: PASS — both tests green (`ok | 2 passed`).

- [ ] **Step 5: Commit**

```bash
git add scripts/cameo_parse.ts scripts/cameo_parse.test.ts
git commit -m "feat(cameo): forward-fill CSV parser with Deno tests"
```

---

## Task 3: Seed script (CSV → Supabase)

Reads the 10 CSVs, parses each with Task 2's function, and rebuilds the tables via the service role. Idempotent: deletes all subjects (cascade clears cards) then re-inserts.

**Files:**
- Create: `scripts/seed-cameos.ts`

- [ ] **Step 1: Write the seed script**

Create `scripts/seed-cameos.ts`:

```ts
#!/usr/bin/env -S deno run --allow-read --allow-env --allow-net

/**
 * seed-cameos.ts
 *
 * Purpose:
 *   Parse cameo-data/*.csv and rebuild public.cameo_subjects + public.cameo_cards.
 *   Idempotent: deletes all subjects (cards cascade) then bulk-inserts fresh rows.
 *
 * Usage (needs the secret key — bypasses RLS to write; exported by the repo's
 * .envrc as SUPABASE_SECRET_KEY, an sb_secret_… service-role-equivalent key):
 *   ./scripts/seed-cameos.ts        # inside a direnv-allowed shell
 *
 * Expected output:
 *   Parsing 10 sheets ...
 *   Parsed 3214 subjects, 3811 cards
 *   Cleared existing cameo data
 *   Inserted 3214 subjects, 3811 cards
 *   ✓ Done
 */

import { parse as parseCsv } from "https://deno.land/std@0.224.0/csv/mod.ts";
import { parseCameoSheet, type ParsedSubject } from "./cameo_parse.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "https://ksildxueezkvrwryybln.supabase.co";
const SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEY");
if (!SECRET_KEY) {
  console.error("SUPABASE_SECRET_KEY is required (writes bypass RLS). Run inside a direnv-allowed shell.");
  Deno.exit(1);
}

const DATA_DIR = "cameo-data";
const SHEETS: { file: string; generation: string; kind: "pokemon" | "trainer" }[] = [
  ...Array.from({ length: 9 }, (_, i) => ({
    file: `RotomAmiti's Cameo Pokémon Card Database - Gen ${i + 1}.csv`,
    generation: `Gen ${i + 1}`,
    kind: "pokemon" as const,
  })),
  {
    file: "RotomAmiti's Cameo Pokémon Card Database - Trainers.csv",
    generation: "Trainers",
    kind: "trainer" as const,
  },
];

async function loadSheet(file: string): Promise<string[][]> {
  const text = await Deno.readTextFile(`${DATA_DIR}/${file}`);
  const rows = parseCsv(text) as string[][]; // array mode (no header inference)
  return rows.slice(1); // drop the header row
}

const headers = {
  apikey: SECRET_KEY!,
  Authorization: `Bearer ${SECRET_KEY}`,
  "Content-Type": "application/json",
};

async function rest(path: string, init: RequestInit) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { ...init, headers: { ...headers, ...(init.headers ?? {}) } });
  if (!res.ok) {
    throw new Error(`${init.method} ${path} -> ${res.status} ${await res.text()}`);
  }
  return res;
}

async function chunkedInsert(table: string, rows: unknown[]) {
  const SIZE = 500;
  for (let i = 0; i < rows.length; i += SIZE) {
    await rest(table, {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify(rows.slice(i, i + SIZE)),
    });
  }
}

// ── Parse ───────────────────────────────────────────────────────────────────
console.log(`Parsing ${SHEETS.length} sheets ...`);
const allSubjects: ParsedSubject[] = [];
for (const sheet of SHEETS) {
  const rows = await loadSheet(sheet.file);
  allSubjects.push(...parseCameoSheet(rows, { generation: sheet.generation, kind: sheet.kind }));
}
const totalCards = allSubjects.reduce((n, s) => n + s.cards.length, 0);
console.log(`Parsed ${allSubjects.length} subjects, ${totalCards} cards`);

// ── Build insert payloads (client-generated UUIDs link cards → subjects) ──────
const subjectRows = allSubjects.map((s) => ({
  id: crypto.randomUUID(),
  kind: s.kind,
  ndex: s.ndex,
  region: s.region,
  name: s.name,
  card_count: s.cards.length,
}));
const cardRows = allSubjects.flatMap((s, i) =>
  s.cards.map((c) => ({
    subject_id: subjectRows[i].id,
    card_name: c.cardName,
    set_name: c.setName,
    card_number: c.cardNumber || null,
    notes: c.notes || null,
    generation: c.generation,
  }))
);

// ── Rebuild ───────────────────────────────────────────────────────────────────
// Delete every subject (cards cascade via FK). PostgREST requires a filter on
// DELETE; `kind` is non-null on every row, so this matches all.
await rest("cameo_subjects?kind=in.(pokemon,trainer)", { method: "DELETE", headers: { Prefer: "return=minimal" } });
console.log("Cleared existing cameo data");

await chunkedInsert("cameo_subjects", subjectRows);
await chunkedInsert("cameo_cards", cardRows);
console.log(`Inserted ${subjectRows.length} subjects, ${cardRows.length} cards`);
console.log("✓ Done");
```

- [ ] **Step 2: Run the seed script**

Run (from repo root, inside a direnv shell that exports `SUPABASE_SERVICE_ROLE_KEY`):
`./scripts/seed-cameos.ts`
Expected: prints `Parsed N subjects, M cards`, `Cleared existing cameo data`, `Inserted N subjects, M cards`, `✓ Done`, exit 0.

- [ ] **Step 3: Spot-check the data landed (REST, no DATABASE_URL in this env)**

Run in a direnv-allowed shell:
```bash
eval "$(direnv export bash)"
auth=(-H "apikey: $SUPABASE_SECRET_KEY" -H "Authorization: Bearer $SUPABASE_SECRET_KEY")
# Totals come back in the Content-Range response header when Prefer: count=exact.
curl -s -o /dev/null -D - "${auth[@]}" -H "Prefer: count=exact" \
  "$SUPABASE_URL/rest/v1/cameo_subjects?select=id&limit=1" | grep -i content-range
curl -s -o /dev/null -D - "${auth[@]}" -H "Prefer: count=exact" \
  "$SUPABASE_URL/rest/v1/cameo_cards?select=id&limit=1" | grep -i content-range
curl -s "${auth[@]}" "$SUPABASE_URL/rest/v1/cameo_subjects?name=eq.Pikachu&select=name,card_count"
```
Expected: both `content-range` headers show non-zero totals (e.g. `0-0/3214`); the Pikachu query
returns one row with a plausible `card_count`. Re-running `./scripts/seed-cameos.ts` leaves the
totals unchanged (idempotent).

- [ ] **Step 4: Commit**

```bash
git add scripts/seed-cameos.ts
git commit -m "feat(cameo): re-runnable Supabase seed script for cameo CSVs"
```

---

## Task 4: TCGplayer search affiliate link (TDD)

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Utilities/TCGPlayerAffiliateLink.swift`
- Test: `ios/slabbist/slabbistTests/Core/TCGPlayerAffiliateLinkTests.swift`

- [ ] **Step 1: Add the failing tests**

Append to `TCGPlayerAffiliateLinkTests.swift` inside the existing `struct TCGPlayerAffiliateLinkTests`:

```swift
@Test("search link wraps an encoded tcgplayer search URL with subId1")
func searchWraps() throws {
    let url = try #require(
        TCGPlayerAffiliateLink.searchLink(query: "Pokémon March Neo Genesis", subId: "cameo", baseURL: base)
    )
    #expect(url.absoluteString ==
        "https://partner.tcgplayer.com/c/6098165/1830156/21018?subId1=cameo&u=https%3A%2F%2Fwww.tcgplayer.com%2Fsearch%2Fpokemon%2Fproduct%3FproductLineName%3Dpokemon%26q%3DPok%25C3%25A9mon%2520March%2520Neo%2520Genesis")
}

@Test("search link empty base falls back to the raw tcgplayer search URL")
func searchRawFallback() throws {
    let url = try #require(
        TCGPlayerAffiliateLink.searchLink(query: "Switch Neo Genesis", subId: "cameo", baseURL: "")
    )
    #expect(url.absoluteString ==
        "https://www.tcgplayer.com/search/pokemon/product?productLineName=pokemon&q=Switch%20Neo%20Genesis")
}

@Test("search link with blank query returns nil so the button hides")
func searchGuardsQuery() {
    #expect(TCGPlayerAffiliateLink.searchLink(query: "   ", subId: "cameo", baseURL: base) == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:slabbistTests/TCGPlayerAffiliateLinkTests 2>&1 | tail -20
```
Expected: FAIL — `searchLink` is not a member of `TCGPlayerAffiliateLink`.
(Sim note: the app targets iOS 26.4; use an installed iOS 26.x sim such as **iPhone 17 Pro** — the CLAUDE.md "iPhone 16 Pro" line is stale.)

- [ ] **Step 3: Implement `searchLink`**

Add to `TCGPlayerAffiliateLink.swift`, inside the `enum`, below the existing `link(productId:...)`:

```swift
    /// Builds an affiliate deep link to a TCGplayer **search** for `query`
    /// (used when we have no resolved product id — e.g. cameo cards). The
    /// destination is `tcgplayer.com/search/pokemon/product?...q=<query>`,
    /// percent-encoded into the impact base's `u=` param with `subId1`.
    /// Returns nil for a blank query so callers can hide the button.
    static func searchLink(
        query: String,
        subId: String,
        baseURL: String = AppEnvironment.tcgplayerImpactBaseURL
    ) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Encode the query as a query-component value (space -> %20).
        let queryAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? trimmed
        let destination = "https://www.tcgplayer.com/search/pokemon/product?productLineName=pokemon&q=\(q)"
        guard !baseURL.isEmpty else { return URL(string: destination) }

        // Encode the whole destination as a single u= value (same rule as link()).
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: unreserved) ?? destination
        return URL(string: "\(baseURL)?subId1=\(subId)&u=\(encoded)")
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.
Expected: PASS — all `TCGPlayerAffiliateLinkTests` green (original 3 + new 3).

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Utilities/TCGPlayerAffiliateLink.swift \
        ios/slabbist/slabbistTests/Core/TCGPlayerAffiliateLinkTests.swift
git commit -m "feat(cameo): TCGPlayerAffiliateLink.searchLink for product-less cards"
```

---

## Task 5: Cameo DTOs + decode round-trip (TDD)

**Files:**
- Create: `ios/slabbist/slabbist/Core/Data/DTOs/CameoSubjectDTO.swift`
- Create: `ios/slabbist/slabbist/Core/Data/DTOs/CameoCardDTO.swift`
- Test: `ios/slabbist/slabbistTests/Core/CameoDTODecodeTests.swift`

- [ ] **Step 1: Write the failing decode test**

Create `CameoDTODecodeTests.swift`. The JSON mirrors a real PostgREST `select *` row (snake_case, nullable fields present and absent):

```swift
import Foundation
import Testing
@testable import slabbist

@Suite("Cameo DTO decode")
struct CameoDTODecodeTests {
    // Why: the secret screen renders straight from PostgREST rows, so the DTOs
    // must round-trip the exact snake_case shape — including null ndex/region
    // (trainers) and null card_number/notes — or rows silently drop.
    @Test("subject decodes pokemon and trainer shapes")
    func subject() throws {
        let json = """
        [
          {"id":"22222222-2222-2222-2222-222222222222","kind":"pokemon","ndex":25,"region":null,"name":"Pikachu","card_count":42},
          {"id":"33333333-3333-3333-3333-333333333333","kind":"trainer","ndex":null,"region":"KANTO","name":"Red","card_count":7}
        ]
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode([CameoSubjectDTO].self, from: json)
        #expect(rows[0].ndex == 25)
        #expect(rows[0].region == nil)
        #expect(rows[1].ndex == nil)
        #expect(rows[1].region == "KANTO")
        #expect(rows[1].name == "Red")
    }

    @Test("card decodes with null card_number and notes")
    func card() throws {
        let json = """
        [{"id":"44444444-4444-4444-4444-444444444444","subject_id":"22222222-2222-2222-2222-222222222222",
          "card_name":"Pokémon March","set_name":"Neo Genesis","card_number":null,"notes":null,"generation":"Gen 2"}]
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode([CameoCardDTO].self, from: json)
        #expect(rows[0].cardName == "Pokémon March")
        #expect(rows[0].cardNumber == nil)
        #expect(rows[0].notes == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:slabbistTests/CameoDTODecodeTests 2>&1 | tail -20
```
Expected: FAIL — `CameoSubjectDTO` / `CameoCardDTO` unknown.

- [ ] **Step 3: Write the DTOs**

Create `CameoSubjectDTO.swift`:

```swift
import Foundation

/// One row from `public.cameo_subjects` — a Pokémon or Trainer that appears as
/// a cameo on TCG cards. `ndex` is set for pokemon, `region` for trainers.
nonisolated struct CameoSubjectDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: UUID
    let kind: String
    let ndex: Int?
    let region: String?
    let name: String
    let cardCount: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, ndex, region, name
        case cardCount = "card_count"
    }
}
```

Create `CameoCardDTO.swift`:

```swift
import Foundation

/// One row from `public.cameo_cards` — a card (or reprint) featuring a cameo
/// subject. `cardNumber`/`notes` are nullable in Postgres.
nonisolated struct CameoCardDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: UUID
    let subjectId: UUID
    let cardName: String
    let setName: String
    let cardNumber: String?
    let notes: String?
    let generation: String

    enum CodingKeys: String, CodingKey {
        case id
        case subjectId  = "subject_id"
        case cardName   = "card_name"
        case setName    = "set_name"
        case cardNumber = "card_number"
        case notes, generation
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run the same command as Step 2.
Expected: PASS — both decode tests green.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Data/DTOs/CameoSubjectDTO.swift \
        ios/slabbist/slabbist/Core/Data/DTOs/CameoCardDTO.swift \
        ios/slabbist/slabbistTests/Core/CameoDTODecodeTests.swift
git commit -m "feat(cameo): CameoSubjectDTO/CameoCardDTO with decode round-trip tests"
```

---

## Task 6: CameoRepository (PostgREST-direct reads)

**Files:**
- Create: `ios/slabbist/slabbist/Core/Data/Repositories/CameoRepository.swift`

No new unit test here (covered by Task 5 decode + the live decode in Step 3). Follows the `StoreMemberRepository` direct-`query()` pattern.

- [ ] **Step 1: Write the repository**

Create `CameoRepository.swift`:

```swift
import Foundation
import Supabase

/// Reads the global-reference cameo tables PostgREST-direct (public-read RLS).
/// Not the aggregator/proxy hero-flow, so no edge function — same direct-query
/// pattern as `SupabaseStoreMemberRepository`.
nonisolated struct CameoRepository: Sendable {
    private let subjects: SupabaseRepository<CameoSubjectDTO>
    private let cards: SupabaseRepository<CameoCardDTO>

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.subjects = SupabaseRepository(tableName: "cameo_subjects", client: client)
        self.cards = SupabaseRepository(tableName: "cameo_cards", client: client)
    }

    /// Subjects whose name matches `query` (case-insensitive substring). A blank
    /// query returns the full list. Ordered by ndex (trainers, ndex null, sort
    /// last) then name. Capped at 1000 — the dataset is ~3k but a single screen
    /// never needs more; search narrows it.
    func searchSubjects(_ query: String) async throws -> [CameoSubjectDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var builder = subjects.query().select()
            if !trimmed.isEmpty {
                builder = builder.ilike("name", value: "%\(trimmed)%")
            }
            return try await builder
                .order("ndex", ascending: true, nullsFirst: false)
                .order("name", ascending: true)
                .limit(1000)
                .execute()
                .value
        } catch {
            throw SupabaseError.map(error)
        }
    }

    /// Every card (incl. reprints) for one subject, grouped by generation then set.
    func cards(forSubject id: UUID) async throws -> [CameoCardDTO] {
        do {
            return try await cards.query().select()
                .eq("subject_id", value: id.uuidString)
                .order("generation", ascending: true)
                .order("set_name", ascending: true)
                .execute()
                .value
        } catch {
            throw SupabaseError.map(error)
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild build -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`. (If `ilike`/`order(nullsFirst:)` signatures differ in the pinned Supabase SDK, check `LSP hover` on the builder and adjust — `query()` returns a `PostgrestFilterBuilder`.)

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Core/Data/Repositories/CameoRepository.swift
git commit -m "feat(cameo): CameoRepository search + cards reads (PostgREST-direct)"
```

---

## Task 7: TCGPlayerSearchLinkButton

**Files:**
- Create: `ios/slabbist/slabbist/Core/DesignSystem/Components/TCGPlayerSearchLinkButton.swift`

- [ ] **Step 1: Write the button**

Create `TCGPlayerSearchLinkButton.swift` — mirrors `TCGPlayerLinkButton` (same gold-outlined style + affiliate disclosure) but takes a search `query` instead of a product id:

```swift
import SwiftUI

/// "Search on TCGplayer" affiliate button for cards we have no resolved product
/// id for (cameo cards). Builds a search URL via `TCGPlayerAffiliateLink.searchLink`
/// and renders nothing for a blank query. `subId` is recorded as impact's subId1.
struct TCGPlayerSearchLinkButton: View {
    let query: String
    var subId: String = "cameo"

    var body: some View {
        if let url = TCGPlayerAffiliateLink.searchLink(query: query, subId: subId) {
            VStack(spacing: Spacing.xs) {
                Link(destination: url) {
                    HStack(spacing: Spacing.xs) {
                        Text("Search on TCGplayer")
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(TCGPlayerSearchLinkButtonStyle())
                .accessibilityLabel("Search on TCGplayer")
                .accessibilityHint("Opens a TCGplayer search for this card")

                Text("Affiliate link — Slabbist may earn a commission.")
                    .font(SlabFont.sans(size: 11))
                    .foregroundStyle(AppColor.dim)
                    .accessibilityLabel("Affiliate link disclosure. Slabbist may earn a commission.")
            }
        }
    }
}

private struct TCGPlayerSearchLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SlabFont.sans(size: 15, weight: .semibold))
            .foregroundStyle(AppColor.gold)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .stroke(AppColor.gold, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

#Preview("TCGPlayerSearchLinkButton") {
    VStack(spacing: Spacing.l) {
        TCGPlayerSearchLinkButton(query: "Pokémon March Neo Genesis")
        TCGPlayerSearchLinkButton(query: "   ") // renders nothing
    }
    .padding()
    .background(AppColor.ink)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild build -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Core/DesignSystem/Components/TCGPlayerSearchLinkButton.swift
git commit -m "feat(cameo): TCGPlayerSearchLinkButton (search-URL affiliate CTA)"
```

---

## Task 8: Psyduck asset

**Files:**
- Create: `ios/slabbist/slabbist/Assets.xcassets/Psyduck.imageset/Contents.json`
- Create: `ios/slabbist/slabbist/Assets.xcassets/Psyduck.imageset/psyduck.png` (copied)

- [ ] **Step 1: Create the imageset directory + copy the art**

Run:
```bash
mkdir -p ios/slabbist/slabbist/Assets.xcassets/Psyduck.imageset
cp cameo-data/psyduck.png ios/slabbist/slabbist/Assets.xcassets/Psyduck.imageset/psyduck.png
```

- [ ] **Step 2: Write Contents.json**

Create `ios/slabbist/slabbist/Assets.xcassets/Psyduck.imageset/Contents.json` (single-scale source; the 512×512 PNG scales down cleanly):

```json
{
  "images" : [
    { "filename" : "psyduck.png", "idiom" : "universal", "scale" : "1x" },
    { "idiom" : "universal", "scale" : "2x" },
    { "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : false }
}
```

- [ ] **Step 3: Build to verify the asset compiles into the catalog**

Run:
```bash
xcodebuild build -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **` (asset catalog compiles `Psyduck` with no "unassigned children" warning).

- [ ] **Step 4: Commit**

```bash
git add ios/slabbist/slabbist/Assets.xcassets/Psyduck.imageset
git commit -m "feat(cameo): add Psyduck imageset for the easter egg"
```

---

## Task 9: Secret screen — subject detail

Built bottom-up: the leaf detail view first, then the list, then the overlay.

**Files:**
- Create: `ios/slabbist/slabbist/Features/Cameo/CameoSubjectDetailView.swift`

> Invoke `swiftui-expert-skill` before writing; honor `.impeccable.md` (dark+gold, SlabFont, Spacing, Radius, AA contrast, 44pt targets).

- [ ] **Step 1: Write the detail view**

Create `CameoSubjectDetailView.swift`:

```swift
import SwiftUI

/// Lists every card (incl. reprints) that features one cameo subject, each with
/// a TCGplayer search-affiliate button. Loads its own cards on appear.
struct CameoSubjectDetailView: View {
    let subject: CameoSubjectDTO
    var repo: CameoRepository = CameoRepository()

    @State private var cards: [CameoCardDTO] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.m) {
                if isLoading {
                    ProgressView().tint(AppColor.gold).frame(maxWidth: .infinity)
                } else if loadFailed {
                    Text("Couldn’t load cards. Pull down to retry.")
                        .font(SlabFont.sans(size: 14))
                        .foregroundStyle(AppColor.dim)
                } else {
                    ForEach(cards) { card in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(card.cardName).slabRowTitle()
                            Text("\(card.setName)\(card.cardNumber.map { " · #\($0)" } ?? "")")
                                .font(SlabFont.mono(size: 13))
                                .foregroundStyle(AppColor.dim)
                            if let notes = card.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(SlabFont.sans(size: 12))
                                    .foregroundStyle(AppColor.dim)
                            }
                            TCGPlayerSearchLinkButton(query: "\(card.cardName) \(card.setName)")
                        }
                        .padding(Spacing.m)
                        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                    }
                }
            }
            .padding(Spacing.m)
        }
        .background(AppColor.ink)
        .navigationTitle(subject.name)
        .task { await load() }
    }

    private func load() async {
        isLoading = true; loadFailed = false
        do { cards = try await repo.cards(forSubject: subject.id) }
        catch { loadFailed = true }
        isLoading = false
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild build -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`. (If `AppColor.surface`, `SlabFont.mono`, or `slabRowTitle()` resolve differently, `LSP hover`/`goToDefinition` on the existing usages in `CompCardView.swift` and match the actual token names.)

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/Cameo/CameoSubjectDetailView.swift
git commit -m "feat(cameo): CameoSubjectDetailView — cards + TCGplayer buttons"
```

---

## Task 10: Secret screen — searchable subject list

**Files:**
- Create: `ios/slabbist/slabbist/Features/Cameo/CameoSecretView.swift`

- [ ] **Step 1: Write the cover view**

Create `CameoSecretView.swift`:

```swift
import SwiftUI

/// The hidden "Cameo Dex": a full-screen, tab-less cover reached only via the
/// Psyduck easter egg. Search/browse every cameo subject; drill into one to see
/// its cards. Dismisses via the X — there is intentionally no tab bar.
struct CameoSecretView: View {
    var repo: CameoRepository = CameoRepository()
    let onClose: () -> Void

    @State private var query = ""
    @State private var subjects: [CameoSubjectDTO] = []
    @State private var isLoading = true
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.s) {
                    KickerLabel("Cameo Dex")
                        .padding(.horizontal, Spacing.m)
                        .padding(.top, Spacing.s)

                    if isLoading {
                        ProgressView().tint(AppColor.gold)
                            .frame(maxWidth: .infinity).padding(.top, Spacing.l)
                    } else if subjects.isEmpty {
                        Text("No cameos match “\(query)”.")
                            .font(SlabFont.sans(size: 14))
                            .foregroundStyle(AppColor.dim)
                            .padding(.horizontal, Spacing.m)
                    } else {
                        ForEach(subjects) { subject in
                            NavigationLink(value: subject) {
                                CameoSubjectRow(subject: subject)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, Spacing.l)
            }
            .background(AppColor.ink)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search cameo Pokémon or Trainers")
            .navigationDestination(for: CameoSubjectDTO.self) { subject in
                CameoSubjectDetailView(subject: subject, repo: repo)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onClose() } label: { Image(systemName: "xmark") }
                        .tint(AppColor.gold)
                        .accessibilityLabel("Close Cameo Dex")
                }
            }
        }
        .task { await runSearch(query) }                 // initial full list
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            searchTask = Task { await runSearch(newValue) } // debounced-ish via cancellation
        }
    }

    private func runSearch(_ text: String) async {
        isLoading = subjects.isEmpty
        do {
            let result = try await repo.searchSubjects(text)
            if !Task.isCancelled { subjects = result }
        } catch {
            if !Task.isCancelled { subjects = [] }
        }
        isLoading = false
    }
}

private struct CameoSubjectRow: View {
    let subject: CameoSubjectDTO

    var body: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name).slabRowTitle()
                Text(subtitle)
                    .font(SlabFont.mono(size: 12))
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
            Text("\(subject.cardCount)")
                .font(SlabFont.mono(size: 13))
                .foregroundStyle(AppColor.gold)
            Image(systemName: "chevron.right").foregroundStyle(AppColor.dim)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }

    private var subtitle: String {
        if let ndex = subject.ndex { return "No. \(ndex)" }
        if let region = subject.region { return region }
        return "Trainer"
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild build -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`. (`CameoSubjectDTO` must be `Hashable` for `navigationDestination(for:)` — it is, from Task 5.)

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/Cameo/CameoSecretView.swift
git commit -m "feat(cameo): CameoSecretView — searchable cameo subject list"
```

---

## Task 11: Psyduck overlay + wire into RootTabView

**Files:**
- Create: `ios/slabbist/slabbist/Features/Cameo/PsyduckPeekOverlay.swift`
- Modify: `ios/slabbist/slabbist/Features/Shell/RootTabView.swift`

- [ ] **Step 1: Write the overlay**

Create `PsyduckPeekOverlay.swift`:

```swift
import SwiftUI

/// The easter egg: a Psyduck that peeks in from the trailing edge (lower third)
/// of every screen. Only the duck is hit-testable; everything else passes touches
/// through. Tapping fires `onTap`. Half its width sits off-screen.
struct PsyduckPeekOverlay: View {
    var onTap: () -> Void
    private let size: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            Image("Psyduck")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .accessibilityLabel("A curious Psyduck")
                .accessibilityHint("Opens a hidden screen")
                .position(
                    x: geo.size.width - size / 2 + 14,           // ~half off the trailing edge
                    y: geo.size.height * 0.66                     // lower third
                )
        }
        .allowsHitTesting(true)
        .ignoresSafeArea()
    }
}
```

- [ ] **Step 2: Wire it into `RootTabView`**

In `RootTabView.swift`, add cover state and wrap the existing `VStack` in a `ZStack`.

Add the state property after the existing `@State`:

```swift
    @State private var showCameoDex: Bool = false
```

Replace the outer `VStack(spacing: 0) { ... }` opening line:

```swift
        VStack(spacing: 0) {
```

with:

```swift
        ZStack(alignment: .topLeading) {
        VStack(spacing: 0) {
```

and add the overlay + close the ZStack immediately before the existing `.sheet(isPresented: $showFailuresSheet)` modifier. Concretely, the block that currently reads:

```swift
        }
        .sheet(isPresented: $showFailuresSheet) {
```

becomes:

```swift
        }
        PsyduckPeekOverlay { showCameoDex = true }
        }
        .fullScreenCover(isPresented: $showCameoDex) {
            CameoSecretView(onClose: { showCameoDex = false })
        }
        .sheet(isPresented: $showFailuresSheet) {
```

(The first `}` closes the `VStack`; `PsyduckPeekOverlay` is the ZStack's second child; the next `}` closes the `ZStack`. The `.fullScreenCover` and `.sheet` attach to the `ZStack`.)

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
xcodebuild build -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual smoke (simulator)**

Run the app (`/run` or Xcode). Verify: Psyduck peeks from the right edge lower-third on every tab; tapping it opens the full-screen Cameo Dex with **no tab bar**; search filters subjects; tapping a subject shows its cards with a "Search on TCGplayer" button that opens an affiliate URL; the X dismisses back to the tabs.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Cameo/PsyduckPeekOverlay.swift \
        ios/slabbist/slabbist/Features/Shell/RootTabView.swift
git commit -m "feat(cameo): Psyduck peek overlay opens the Cameo Dex cover"
```

---

## Task 12: Full regression pass

- [ ] **Step 1: Run the full iOS test suite**

Run:
```bash
xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -25
```
Expected: `** TEST SUCCEEDED **` — including `TCGPlayerAffiliateLinkTests` (6) and `CameoDTODecodeTests` (2).

- [ ] **Step 2: Run the parser test + confirm RLS still passes**

Run:
```bash
deno test scripts/cameo_parse.test.ts
# Re-confirm RLS functionally (same REST probe as Task 1 Step 4)
eval "$(direnv export bash)"
curl -s -o /dev/null -w "anon select=%{http_code}\n" \
  "$SUPABASE_URL/rest/v1/cameo_subjects?select=id&limit=1" \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY" -H "Authorization: Bearer $SUPABASE_PUBLISHABLE_KEY"
```
Expected: Deno `ok | 2 passed`; `anon select=200`.

- [ ] **Step 3: Final commit (if any lint/format drift)**

```bash
git add -A && git commit -m "chore(cameo): regression pass green" || echo "nothing to commit"
```

---

## Self-review notes (coverage vs spec)

- Spec §1 data model → Task 1. §2 ingestion → Tasks 2–3. §3 read API → Tasks 5–6. §4 affiliate search link → Tasks 4, 7. §5 easter egg + secret screen → Tasks 8–11. Testing section → Tasks 1, 2, 4, 5, 12.
- Type consistency: `parseCameoSheet(rows, {generation, kind})` returns `ParsedSubject[]` (Task 2) consumed identically in Task 3; `CameoSubjectDTO`/`CameoCardDTO` field names (Task 5) are used unchanged in Tasks 6, 9, 10; `searchLink(query:subId:baseURL:)` (Task 4) is the only builder called by `TCGPlayerSearchLinkButton` (Task 7).
- Deferred per spec "out of scope": no product-ID matching, no offline caching, no IA/tab change.
- Risk flagged for the executor: the pinned Supabase Swift SDK's filter-builder method names (`ilike`, `order(nullsFirst:)`) and design tokens (`AppColor.surface`, `SlabFont.mono`) must be confirmed against the live codebase via LSP before trusting the literal text — noted inline in Tasks 6 and 9.
```
