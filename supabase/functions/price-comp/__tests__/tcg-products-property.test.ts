// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// Property tests for findTcgProductByGroupAndCard — naming-convention
// Layer A of the comprehensive test plan. These tests are intentionally
// complementary to tcg-products.test.ts (which covers happy paths and
// query-shape assertions). This file stresses the resolver across
// additional real-production card_number formats and edge cases.

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { findTcgProductByGroupAndCard } from "../lib/tcg-products.ts";

// ── Fake Supabase ────────────────────────────────────────────────────
// Reuse the same pattern as tcg-products.test.ts.

interface FakeRow {
  product_id: number;
  group_id: number;
  name: string;
  card_number: string;
}

function fakeSupabase(rows: FakeRow[]) {
  const lastQuery = { table: "", groupId: null as number | null, orFilter: null as string | null, limit: null as number | null };
  let filtered = [...rows];

  const builder: any = {
    select(_cols: string) { return builder; },
    eq(col: string, value: unknown) {
      if (col === "group_id") {
        lastQuery.groupId = value as number;
        filtered = filtered.filter((r) => r.group_id === value);
      }
      return builder;
    },
    or(filter: string) {
      lastQuery.orFilter = filter;
      const clauses = filter.split(",");
      filtered = filtered.filter((r) => {
        for (const cl of clauses) {
          const [col, op, ...rest] = cl.split(".");
          const v = rest.join(".");
          if (col !== "card_number") continue;
          if (op === "eq" && r.card_number === v) return true;
          if (op === "ilike") {
            const re = new RegExp("^" + v.replace(/%/g, ".*") + "$", "i");
            if (re.test(r.card_number)) return true;
          }
        }
        return false;
      });
      return builder;
    },
    limit(n: number) {
      lastQuery.limit = n;
      filtered = filtered.slice(0, n);
      return Promise.resolve({ data: filtered, error: null });
    },
    then(resolve: (v: any) => void) {
      resolve({ data: filtered, error: null });
    },
  };

  return {
    lastQuery,
    client: {
      from(table: string) {
        lastQuery.table = table;
        filtered = [...rows];
        return builder;
      },
    },
  };
}

// ── Zero-padding asymmetry ───────────────────────────────────────────

Deno.test("property: PSA '4' matches tcg '04/62' (Fossil Dragonite — 1-digit to 2-digit pad)", async () => {
  const stub = fakeSupabase([
    { product_id: 106520, group_id: 630, name: "Dragonite (4)", card_number: "04/62" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 630,
    cardNumber: "4",
    cardName: "Dragonite",
  });
  assert(got !== null, "should resolve Fossil Dragonite");
  assertEquals(got!.productId, 106520);
});

Deno.test("property: PSA '04' matches tcg '04/62' (idempotent — already padded)", async () => {
  const stub = fakeSupabase([
    { product_id: 106520, group_id: 630, name: "Dragonite (4)", card_number: "04/62" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 630,
    cardNumber: "04",
    cardName: "Dragonite",
  });
  assert(got !== null, "should resolve with already-padded input");
  assertEquals(got!.productId, 106520);
});

Deno.test("property: PSA '199' matches tcg '199/165' (Charizard ex 151 — 3-digit exact prefix)", async () => {
  const stub = fakeSupabase([
    { product_id: 243172, group_id: 23237, name: "Charizard ex - 199/165", card_number: "199/165" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 23237,
    cardNumber: "199",
    cardName: "Charizard ex",
  });
  assert(got !== null);
  assertEquals(got!.productId, 243172);
});

Deno.test("property: PSA '020' matches tcg '020/198' (zero-padded slash format)", async () => {
  const stub = fakeSupabase([
    { product_id: 555111, group_id: 24163, name: "Pikachu - 020/198", card_number: "020/198" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 24163,
    cardNumber: "020",
    cardName: "Pikachu",
  });
  assert(got !== null);
  assertEquals(got!.productId, 555111);
});

Deno.test("property: PSA '217' matches tcg '217/187'", async () => {
  const stub = fakeSupabase([
    { product_id: 300001, group_id: 23821, name: "Umbreon ex - 217/187", card_number: "217/187" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 23821,
    cardNumber: "217",
    cardName: "Umbreon ex",
  });
  assert(got !== null);
  assertEquals(got!.productId, 300001);
});

// ── Alphanumeric suffix ──────────────────────────────────────────────

Deno.test("property: PSA '020' matches tcg '020/M-P' (alphanumeric denominator)", async () => {
  const stub = fakeSupabase([
    { product_id: 649586, group_id: 24423, name: "Pikachu - 020/M-P", card_number: "020/M-P" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 24423,
    cardNumber: "020",
    cardName: "Pikachu",
  });
  assert(got !== null, "should resolve alphanumeric denominator row");
  assertEquals(got!.productId, 649586);
});

// ── Reverse slash asymmetry ──────────────────────────────────────────

Deno.test("property: PSA card_number contains slash ('079/072') matches tcg '79/72' (denominator stripped)", async () => {
  // Less common but real: PSA occasionally includes the full fraction.
  // normalizeForCompare strips the slash suffix → "079" → "79";
  // tcg row "79/72" → "79". They match.
  const stub = fakeSupabase([
    { product_id: 400010, group_id: 23651, name: "Rayquaza ex - 79/72", card_number: "79/72" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 23651,
    cardNumber: "079/072",
    cardName: "Rayquaza ex",
  });
  assert(got !== null, "should resolve when PSA includes full fraction");
  assertEquals(got!.productId, 400010);
});

// ── Null card_number edge cases ──────────────────────────────────────

Deno.test("property: null card_number + unique name match → returns the product", async () => {
  const stub = fakeSupabase([
    { product_id: 88, group_id: 1, name: "Eevee", card_number: "133/151" },
    { product_id: 99, group_id: 1, name: "Pikachu", card_number: "025/151" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 1,
    cardNumber: null,
    cardName: "Eevee",
  });
  assert(got !== null, "unique name match should resolve");
  assertEquals(got!.productId, 88);
});

Deno.test("property: null card_number + ambiguous name match (2 'Pikachu' in group) → returns null", async () => {
  const stub = fakeSupabase([
    { product_id: 10, group_id: 5, name: "Pikachu", card_number: "025/151" },
    { product_id: 20, group_id: 5, name: "Pikachu", card_number: "086/165" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 5,
    cardNumber: null,
    cardName: "Pikachu",
  });
  assertEquals(got, null, "ambiguous two-row match must return null");
});

// ── Exact-vs-fuzzy disambiguation ───────────────────────────────────

Deno.test("property: exact card_number match wins over fuzzy-only matches when both present", async () => {
  // Row 100: card_number contains "199" somewhere but is a different card.
  // Row 200: exact card_number prefix "199/165" AND name matches.
  // Row 300: name fuzzy-matches but card_number doesn't.
  const stub = fakeSupabase([
    { product_id: 300, group_id: 23237, name: "Charizard ex", card_number: "012/165" },
    { product_id: 100, group_id: 23237, name: "Pikachu - 199/165", card_number: "199/165" },
    { product_id: 200, group_id: 23237, name: "Charizard ex - 199/165", card_number: "199/165" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 23237,
    cardNumber: "199",
    cardName: "Charizard ex",
  });
  // Row 200: +5 (exact number) + +2 (name overlap) = 7 — highest.
  // Row 100: +5 (exact number) + 0 (name miss) = 5.
  // Row 300: +0 (no number match, .eq filter excludes it) + 0 = excluded.
  assertEquals(got?.productId, 200, "exact+name winner should be product 200");
});
