// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { extractLadder, pickTier, productUrl, ladderHasAnyPrice } from "../pricecharting/parse.ts";

const full = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/pricecharting/product-full-ladder.json", import.meta.url)),
);
const partial = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/pricecharting/product-partial-ladder.json", import.meta.url)),
);
const empty = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/pricecharting/product-no-prices.json", import.meta.url)),
);

Deno.test("extractLadder: full ladder", () => {
  assertEquals(extractLadder(full), {
    loose:    400,
    grade_7: 2400,
    grade_8: 3400,
    grade_9: 6800,
    grade_9_5: 11200,
    psa_10: 18500,
    bgs_10: 21500,
    cgc_10: 16800,
    sgc_10: 16500,
  });
});

Deno.test("extractLadder: partial ladder, missing keys are null", () => {
  assertEquals(extractLadder(partial), {
    loose:    500,
    grade_7:  null,
    grade_8:  null,
    grade_9: 4200,
    grade_9_5: null,
    psa_10: 18000,
    bgs_10: null,
    cgc_10: null,
    sgc_10: null,
  });
});

Deno.test("extractLadder: no prices at all", () => {
  const ladder = extractLadder(empty);
  for (const v of Object.values(ladder)) assertEquals(v, null);
});

Deno.test("pickTier: PSA 10 from full ladder", () => {
  assertEquals(pickTier(full, "PSA", "10"), 18500);
});

Deno.test("pickTier: BGS 9.5 from full ladder", () => {
  assertEquals(pickTier(full, "BGS", "9.5"), 11200);
});

Deno.test("pickTier: tier missing in partial -> null", () => {
  assertEquals(pickTier(partial, "BGS", "10"), null);
});

Deno.test("pickTier: unknown grade returns null", () => {
  assertEquals(pickTier(full, "PSA", "1"), null);
});

Deno.test("ladderHasAnyPrice: empty -> false, partial -> true, full -> true", () => {
  assertEquals(ladderHasAnyPrice(extractLadder(empty)), false);
  assertEquals(ladderHasAnyPrice(extractLadder(partial)), true);
  assertEquals(ladderHasAnyPrice(extractLadder(full)), true);
});

Deno.test("productUrl: derives a stable URL from console-name and product-name", () => {
  const url = productUrl(full);
  assert(url.startsWith("https://www.pricecharting.com/game/"));
  assert(url.includes("pokemon-surging-sparks"));
});
