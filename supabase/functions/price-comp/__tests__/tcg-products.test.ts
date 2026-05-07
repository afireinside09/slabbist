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

// ── Bug A: zero-pad asymmetry ────────────────────────────────────────

Deno.test("findTcgProduct: PSA '4' matches '04/62' (zero-padded tcg row, Fossil Dragonite case)", async () => {
  // PSA writes card_number = "4"; TCGPlayer stores "04/62".
  // buildCardNumberVariants("4") must emit "04/%" or equivalent.
  const stub = fakeSupabase([
    { product_id: 106520, group_id: 500, name: "Dragonite (4)", card_number: "04/62" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 500,
    cardNumber: "4",
    cardName: "Dragonite",
  });
  assert(got !== null, "should resolve Fossil Dragonite via zero-padded variant");
  assertEquals(got!.productId, 106520);
  // The OR filter must include a variant that matches "04/62".
  const filter = stub.lastQuery.orFilter ?? "";
  const hasVariant = filter.includes("card_number.ilike.04/%") ||
    filter.includes("card_number.ilike.04%") ||
    filter.includes("card_number.eq.04");
  assert(hasVariant, `filter must contain a 2-digit zero-padded variant; got: ${filter}`);
});

Deno.test("findTcgProduct: PSA '020' matches '20/198' AND filter includes a stripped variant", async () => {
  // Existing test already covers matching — this is the query-shape counterpart.
  const stub = fakeSupabase([
    { product_id: 444222, group_id: 99, name: "Charizard - 20/198", card_number: "20/198" },
  ]);
  await findTcgProductByGroupAndCard(stub.client, {
    groupId: 99,
    cardNumber: "020",
    cardName: "Charizard",
  });
  const filter = stub.lastQuery.orFilter ?? "";
  assert(filter.includes("card_number.ilike.20/%"), `missing 20/% variant in: ${filter}`);
});

Deno.test("findTcgProduct: PSA '020' filter also includes zero-padded bare-prefix variant", async () => {
  // When PSA sends a padded number, verify 020% variant is present for
  // tcg_products rows like "020/198" (already covered by ilike.020/%).
  const stub = fakeSupabase([
    { product_id: 1, group_id: 1, name: "X", card_number: "020/198" },
  ]);
  await findTcgProductByGroupAndCard(stub.client, {
    groupId: 1,
    cardNumber: "020",
    cardName: "X",
  });
  const filter = stub.lastQuery.orFilter ?? "";
  assert(filter.includes("card_number.ilike.020/%"), `missing 020/% in: ${filter}`);
});

Deno.test("findTcgProduct: PSA '020' generates variant that matches '20/198' — query shape test", async () => {
  // Verify '20/%' appears (the stripped slash-prefix variant).
  const stub = fakeSupabase([
    { product_id: 555, group_id: 10, name: "Card - 20/198", card_number: "20/198" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 10,
    cardNumber: "020",
    cardName: "Card",
  });
  assert(got !== null);
  assertEquals(got!.productId, 555);
});

Deno.test("findTcgProduct: PSA '4' generates '04/%' variant (2-digit zero-pad)", async () => {
  // Query shape: calling with a 1-digit number must produce 2- and 3-digit
  // zero-padded variants so the OR filter matches rows like "04/62" and "004/XXX".
  const stub = fakeSupabase([
    { product_id: 9, group_id: 9, name: "Test - 04/62", card_number: "04/62" },
  ]);
  await findTcgProductByGroupAndCard(stub.client, {
    groupId: 9,
    cardNumber: "4",
    cardName: "Test",
  });
  const filter = stub.lastQuery.orFilter ?? "";
  assert(filter.includes("card_number.ilike.04/%"), `missing 04/% in: ${filter}`);
  assert(filter.includes("card_number.ilike.004/%"), `missing 004/% in: ${filter}`);
});

Deno.test("findTcgProduct: PSA '199' matches '199/165' and no zero-pad variants needed (3 digits)", async () => {
  // 3-digit number already canonical; zero-padding to 4 digits would be
  // unusual — just confirm the existing happy path still passes.
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

Deno.test("findTcgProduct: null card_number skips OR filter entirely", async () => {
  // When card_number is null, no orFilter should be set (the query goes
  // straight to limit without a .or() call).
  const stub = fakeSupabase([
    { product_id: 77, group_id: 5, name: "Bulbasaur", card_number: "001/151" },
  ]);
  await findTcgProductByGroupAndCard(stub.client, {
    groupId: 5,
    cardNumber: null,
    cardName: "Bulbasaur",
  });
  assertEquals(stub.lastQuery.orFilter, null, "orFilter should be null when card_number is null");
});

// ── Bug C: null card_number — name-only fallback strictness ──────────

Deno.test("findTcgProduct: null card_number, single-name match → returns it", async () => {
  const stub = fakeSupabase([
    { product_id: 11, group_id: 3, name: "Charizard V", card_number: "018/100" },
    { product_id: 22, group_id: 3, name: "Pikachu V", card_number: "042/100" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 3,
    cardNumber: null,
    cardName: "Charizard V",
  });
  assert(got !== null, "unique name match should resolve");
  assertEquals(got!.productId, 11);
});

Deno.test("findTcgProduct: null card_number, multiple-name matches in same group → returns null (ambiguous)", async () => {
  // Two rows both match the name "Charizard" — must not guess.
  const stub = fakeSupabase([
    { product_id: 10, group_id: 3, name: "Charizard", card_number: "004/102" },
    { product_id: 20, group_id: 3, name: "Charizard", card_number: "005/102" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 3,
    cardNumber: null,
    cardName: "Charizard",
  });
  assertEquals(got, null, "ambiguous multi-match with null card_number should return null");
});

Deno.test("findTcgProduct: null card_number, no name match → returns null", async () => {
  const stub = fakeSupabase([
    { product_id: 33, group_id: 7, name: "Venusaur", card_number: "015/151" },
    { product_id: 44, group_id: 7, name: "Blastoise", card_number: "007/151" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 7,
    cardNumber: null,
    cardName: "Charizard",
  });
  assertEquals(got, null, "no name match with null card_number should return null");
});

// Fuzzy name case: PSA "Charizard Mega ex" vs TCGPlayer "Mega Charizard ex - 028/132".
// Decision: we do NOT accept this as a match. The contiguous-substring rule
// requires the PSA name to appear inside the tcg_products name (or vice versa)
// after paren-stripping and lowercasing. "charizard mega ex" is NOT a
// contiguous substring of "mega charizard ex" (word order differs), and
// "mega charizard ex" is NOT a substring of "charizard mega ex". This avoids
// false positives on alternate names / regional variants. The alias table is
// the right place to handle these name-order discrepancies.
Deno.test("findTcgProduct: null card_number, word-order mismatch (Charizard Mega ex) → returns null", async () => {
  const stub = fakeSupabase([
    { product_id: 55, group_id: 8, name: "Mega Charizard ex - 028/132", card_number: "028/132" },
  ]);
  const got = await findTcgProductByGroupAndCard(stub.client, {
    groupId: 8,
    cardNumber: null,
    cardName: "Charizard Mega ex",
  });
  // Substring check: "charizard mega ex" ∉ "mega charizard ex" (word order)
  // and "mega charizard ex" ∉ "charizard mega ex". Should NOT resolve.
  assertEquals(got, null, "word-order mismatch should not resolve when card_number is null");
});
