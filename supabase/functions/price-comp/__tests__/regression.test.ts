// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// REGRESSION SUITE
//
// This file asserts that resolveCard()'s outcomes match a frozen baseline
// captured from production on 2026-05-07. When the resolver intentionally
// changes behavior (alias CSV edit, scoring tweak, JP fallback rules), a
// regression test will fail — that's the test's job.
//
// To re-baseline:
//   1. deno run --allow-read --allow-write --allow-net /tmp/capture-regression-baseline.ts
//      (script captures from production using the publishable key in the env)
//   2. Inspect the JSON diff in supabase/functions/price-comp/__fixtures__/regression-baseline.json
//   3. If the diff matches your intent, commit. Otherwise debug.
//
// Tests are deterministic — NO live API calls are made. All PPT responses
// and Supabase query results come from the frozen JSON fixture.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { resolveCard, type IdentityForMatch } from "../ppt/match.ts";
import { _resetPauseForTests } from "../ppt/cards.ts";

// ── Baseline fixture ──────────────────────────────────────────────────
const baselineRaw = await Deno.readTextFile(
  new URL("../__fixtures__/regression-baseline.json", import.meta.url).pathname,
);
const baseline = JSON.parse(baselineRaw);

// ── Scenario types ────────────────────────────────────────────────────
interface IdentityRow {
  id: string;
  card_name: string;
  card_number: string | null;
  set_name: string;
  year: number | null;
  ppt_tcgplayer_id: string | null;
}

interface ProductRow {
  product_id: number;
  group_id: number;
  name: string | null;
  card_number: string | null;
}

interface PptResponse {
  language: "english" | "japanese";
  card: Record<string, unknown> | null;
}

interface Scenario {
  identity: IdentityRow;
  tcg_groups: unknown[];
  tcg_products: ProductRow[];
  ppt_response_for_tcgplayer_id: Record<string, PptResponse>;
  expected: {
    tier_matched: string | null;
    ppt_tcgplayer_id: string | null;
    resolved_language: string | null;
  };
}

// ── Fake Supabase builder ─────────────────────────────────────────────
//
// Returns a Supabase-compatible shim that replays the frozen tcg_products
// rows from the fixture when the resolver queries tcg_products. The shim
// mirrors the same PostgREST builder contract that the real tests use
// (see match.test.ts → fakeSupabaseForTcg).
//
function makeFakeSupabaseFromScenario(scenario: Scenario) {
  const rows = [...scenario.tcg_products];

  return {
    from(table: string) {
      if (table !== "tcg_products") {
        throw new Error(`regression fakeSupabase: unexpected table '${table}'`);
      }
      let filtered = [...rows];
      const builder: any = {
        select(_cols: string) { return builder; },
        eq(col: string, value: unknown) {
          if (col === "group_id") {
            filtered = filtered.filter((r) => r.group_id === value);
          }
          return builder;
        },
        or(filter: string) {
          const clauses = filter.split(",");
          filtered = filtered.filter((r) => {
            for (const cl of clauses) {
              const [col, op, ...rest] = cl.split(".");
              const v = rest.join(".");
              if (col !== "card_number") continue;
              if (op === "eq" && r.card_number === v) return true;
              if (op === "ilike") {
                // Escape special regex chars in the literal parts (anything
                // that isn't the ILIKE wildcard '%'), then replace '%' → '.*'.
                // Important: escape BEFORE replacing '%' so the substituted
                // '.*' is NOT re-escaped.
                const escaped = v
                  .split("%")
                  .map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
                  .join(".*");
                const re = new RegExp("^" + escaped + "$", "i");
                if (re.test(r.card_number ?? "")) return true;
              }
            }
            return false;
          });
          return builder;
        },
        ilike(col: string, pattern: string) {
          // null card_number path: name-based filter
          if (col === "name") {
            const escaped = pattern
              .split("%")
              .map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
              .join(".*");
            const re = new RegExp("^" + escaped + "$", "i");
            filtered = filtered.filter((r) => re.test(r.name ?? ""));
          }
          return builder;
        },
        limit(n: number) {
          filtered = filtered.slice(0, n);
          return Promise.resolve({ data: filtered, error: null });
        },
        then(resolve: (v: unknown) => void) {
          resolve({ data: filtered, error: null });
        },
      };
      return builder;
    },
  };
}

// ── Stub PPT client builder ───────────────────────────────────────────
//
// Instead of spinning up a real HTTP server, we intercept at the HTTP
// layer by providing a custom `baseUrl` pointing at a per-test Deno.serve
// instance. This mirrors the exact pattern used by the existing match.test.ts
// integration tests.
//
// The server reads the tcgPlayerId param from the request URL and returns
// the captured PPT response from the fixture. Any unknown tcgPlayerId returns
// an empty array (treated as "no card").
//
function makeStubServer(scenario: Scenario): { url: string; close: () => Promise<void> } {
  const ac = new AbortController();
  const server = Deno.serve({ port: 0, signal: ac.signal }, (req) => {
    const u = new URL(req.url);
    const tcgId = u.searchParams.get("tcgPlayerId");
    const langParam = u.searchParams.get("language");

    if (!tcgId) {
      // searchCards call (no tcgPlayerId) — return empty; regression tests
      // focus on Tier A behavior where the frozen tcg_products rows are the
      // gate. B/C/D search tiers will produce empty results and the resolver
      // will either use Tier A's result or return null.
      return new Response(JSON.stringify([]), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }

    const entry = scenario.ppt_response_for_tcgplayer_id[tcgId];
    if (!entry || !entry.card) {
      return new Response(JSON.stringify([]), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }

    // For Tier A's EN-then-JP fallback: only return the card if the requested
    // language matches, or if no language was captured (default to english).
    const requestedLang = langParam ?? "english";
    if (entry.language === requestedLang) {
      return new Response(
        JSON.stringify([entry.card]),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    // Language mismatch — return empty (resolver will retry with other language).
    return new Response(JSON.stringify([]), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  });

  const url = `http://localhost:${(server.addr as Deno.NetAddr).port}`;
  return {
    url,
    async close() {
      ac.abort();
      try { await server.finished; } catch { /* swallow */ }
    },
  };
}

// ── Test loop ─────────────────────────────────────────────────────────
for (const scenario of baseline.scenarios as Scenario[]) {
  const { identity, expected } = scenario;
  const label = `regression: ${identity.set_name} | ${identity.card_name}`;

  Deno.test(label, async () => {
    _resetPauseForTests();

    const fakeSupabase = makeFakeSupabaseFromScenario(scenario);
    const stub = makeStubServer(scenario);

    try {
      const result = await resolveCard(
        {
          client: { token: "fixture-stub", baseUrl: stub.url, now: () => Date.now() },
          supabase: fakeSupabase,
        },
        {
          card_name: identity.card_name,
          card_number: identity.card_number,
          set_name: identity.set_name,
          year: identity.year,
        } satisfies IdentityForMatch,
      );

      // ── Core assertions ──────────────────────────────────────────────
      assertEquals(
        result.tierMatched,
        expected.tier_matched,
        `tierMatched mismatch. attemptLog: ${JSON.stringify(result.attemptLog)}`,
      );

      assertEquals(
        result.card?.tcgPlayerId ?? null,
        expected.ppt_tcgplayer_id ?? null,
        `tcgPlayerId mismatch (tier=${result.tierMatched}). attemptLog: ${JSON.stringify(result.attemptLog)}`,
      );

      if (expected.resolved_language) {
        assertEquals(
          result.resolvedLanguage ?? null,
          expected.resolved_language,
          `resolvedLanguage mismatch`,
        );
      }
    } finally {
      await stub.close();
    }
  });
}
