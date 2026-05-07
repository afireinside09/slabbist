// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { findTcgProductByGroupAndCard } from "../lib/tcg-products.ts";

interface FakeRow {
  product_id: number;
  group_id: number;
  name: string;
  card_number: string;
}

// Build a stub supabase client whose `from("tcg_products")` chain
// returns rows that match the recorded query. Records the last query
// args so tests can assert query shape.
interface FakeQuery {
  table: string;
  groupId: number | null;
  orFilter: string | null;
  limit: number | null;
}

function fakeSupabase(rows: FakeRow[]) {
  const lastQuery: FakeQuery = { table: "", groupId: null, orFilter: null, limit: null };
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
      // Naive emulation: parse "card_number.eq.X" / "card_number.ilike.X"
      // clauses, OR them together.
      const clauses = filter.split(",");
      filtered = filtered.filter((r) => {
        for (const cl of clauses) {
          const [col, op, ...rest] = cl.split(".");
          const v = rest.join(".");
          if (col !== "card_number") continue;
          const target = r.card_number;
          if (op === "eq" && target === v) return true;
          if (op === "ilike") {
            const re = new RegExp("^" + v.replace(/%/g, ".*") + "$", "i");
            if (re.test(target)) return true;
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
    // Path used when card_number is null on identity (no `or`).
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

// ── Happy paths ──────────────────────────────────────────────────────

Deno.test("findTcgProduct: PSA '199' matches '199/165' on exact-prefix → returns product", async () => {
  const stub = fakeSupabase([
    { product_id: 243172, group_id: 23237, name: "Charizard ex - 199/165", card_number: "199/165" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 23237,
    cardNumber: "199",
    cardName: "Charizard ex",
  });
  assert(got !== null, "should resolve");
  assertEquals(got!.productId, 243172);
  assertEquals(stub.lastQuery.table, "tcg_products");
  assertEquals(stub.lastQuery.groupId, 23237);
});

Deno.test("findTcgProduct: PSA '020' matches '020/198' (zero-padded prefix)", async () => {
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

Deno.test("findTcgProduct: PSA '020' matches '20/198' (leading-zero stripped)", async () => {
  const stub = fakeSupabase([
    { product_id: 444222, group_id: 99, name: "Charizard - 20/198", card_number: "20/198" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 99,
    cardNumber: "020",
    cardName: "Charizard",
  });
  assert(got !== null);
  assertEquals(got!.productId, 444222);
});

Deno.test("findTcgProduct: exact card_number match without slash → returns product", async () => {
  const stub = fakeSupabase([
    { product_id: 1, group_id: 2585, name: "Charizard V - SWSH285", card_number: "SWSH285" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 2585,
    cardNumber: "SWSH285",
    cardName: "Charizard V",
  });
  assert(got !== null);
  assertEquals(got!.productId, 1);
});

// ── Scoring / disambiguation ────────────────────────────────────────

Deno.test("findTcgProduct: number+name match outscores number-only on a different card", async () => {
  const stub = fakeSupabase([
    { product_id: 100, group_id: 23237, name: "Random Card - 199/165", card_number: "199/165" },
    { product_id: 200, group_id: 23237, name: "Charizard ex - 199/165", card_number: "199/165" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 23237,
    cardNumber: "199",
    cardName: "Charizard ex",
  });
  // Both have number match (+5). The Charizard row also has name overlap
  // (+2) → it wins.
  assertEquals(got?.productId, 200);
});

Deno.test("findTcgProduct: returns null when no candidate scores >= 5", async () => {
  // Same group_id, but no card_number candidates AND name doesn't match.
  const stub = fakeSupabase([
    { product_id: 1, group_id: 9999, name: "Some Other Card", card_number: "ZZZ" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 9999,
    cardNumber: "200",
    cardName: "Charizard",
  });
  assertEquals(got, null);
});

Deno.test("findTcgProduct: empty result set returns null", async () => {
  const stub = fakeSupabase([]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 12345,
    cardNumber: "1",
    cardName: "Anything",
  });
  assertEquals(got, null);
});

// ── Query shape ─────────────────────────────────────────────────────

Deno.test("findTcgProduct: emits OR filter with multiple card_number variants", async () => {
  const stub = fakeSupabase([
    { product_id: 1, group_id: 7, name: "X - 020/198", card_number: "020/198" },
  ]);
  await findTcgProductByGroupAndCard(stub.client, {
    groupId: 7,
    cardNumber: "020",
    cardName: "X",
  });
  const filter = stub.lastQuery.orFilter ?? "";
  // Should include exact, slash-suffix, leading-zero-stripped, and
  // exact-prefix variants.
  assert(filter.includes("card_number.eq.020"), `missing exact: ${filter}`);
  assert(filter.includes("card_number.ilike.020/%"), `missing slash variant: ${filter}`);
  assert(filter.includes("card_number.ilike.20/%"), `missing stripped slash: ${filter}`);
  assert(filter.includes("card_number.ilike.20%"), `missing exact-prefix: ${filter}`);
});

// ── Null card_number fallback ───────────────────────────────────────

Deno.test("findTcgProduct: null card_number → still matches on name overlap", async () => {
  const stub = fakeSupabase([
    { product_id: 88, group_id: 1, name: "Mew", card_number: "151/151" },
    { product_id: 99, group_id: 1, name: "Pikachu", card_number: "025/151" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 1,
    cardNumber: null,
    cardName: "Mew",
  });
  // No card_number filter → both rows reach scoring; "Mew" name overlap
  // is unique → product 88.
  assertEquals(got?.productId, 88);
});
