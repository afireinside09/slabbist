// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  extractLadder,
  pickTier,
  ladderHasAnyPrice,
  parsePriceHistory,
  priceHistoryForTier,
  productUrl,
} from "../ppt/parse.ts";

const full = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/ppt/full-ladder.json", import.meta.url)),
);
const partial = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/ppt/partial-ladder.json", import.meta.url)),
);
const empty = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/ppt/no-prices.json", import.meta.url)),
);

Deno.test("extractLadder: full ladder, dollars→cents from salesByGrade.{key}.smartMarketPrice.price", () => {
  assertEquals(extractLadder(full), {
    loose:    400,
    psa_7:   2400,
    psa_8:   3400,
    psa_9:   6800,
    psa_9_5:11200,
    psa_10: 18500,
    bgs_10: 21500,
    cgc_10: 16800,
    sgc_10: 16500,
  });
});

Deno.test("extractLadder: partial ladder, missing keys are null", () => {
  const ladder = extractLadder(partial);
  assertEquals(ladder.loose, 500);
  assertEquals(ladder.psa_9, 4200);
  assertEquals(ladder.psa_10, 18000);
  assertEquals(ladder.psa_7, null);
  assertEquals(ladder.psa_8, null);
  assertEquals(ladder.psa_9_5, null);
  assertEquals(ladder.bgs_10, null);
  assertEquals(ladder.cgc_10, null);
  assertEquals(ladder.sgc_10, null);
});

Deno.test("extractLadder: no-prices card → all null", () => {
  const ladder = extractLadder(empty);
  for (const v of Object.values(ladder)) assertEquals(v, null);
});

Deno.test("extractLadder: prices.market preferred over ebay.salesByGrade.ungraded for loose", () => {
  const card = {
    prices: { market: 7.50 },
    ebay: { salesByGrade: { ungraded: { smartMarketPrice: { price: 4.00 } } } },
  };
  assertEquals(extractLadder(card).loose, 750);
});

Deno.test("extractLadder: falls back to ebay.salesByGrade.ungraded.smartMarketPrice when prices.market absent", () => {
  const card = {
    prices: {},
    ebay: { salesByGrade: { ungraded: { smartMarketPrice: { price: 4.00 } } } },
  };
  assertEquals(extractLadder(card).loose, 400);
});

Deno.test("extractLadder: a tier with smartMarketPrice = null is treated as missing", () => {
  const card = {
    ebay: {
      salesByGrade: {
        psa10: { count: 0, smartMarketPrice: { price: null } },
      },
    },
  };
  assertEquals(extractLadder(card).psa_10, null);
});

Deno.test("pickTier: (PSA, '10') picks psa10", () => {
  assertEquals(pickTier(full, "PSA", "10"), 18500);
});

Deno.test("pickTier: (BGS, '10') picks bgs10", () => {
  assertEquals(pickTier(full, "BGS", "10"), 21500);
});

Deno.test("pickTier: (PSA, '9.5') picks psa9_5", () => {
  assertEquals(pickTier(full, "PSA", "9.5"), 11200);
});

Deno.test("pickTier: (TAG, '10') returns null in v1", () => {
  assertEquals(pickTier(full, "TAG", "10"), null);
});

Deno.test("ladderHasAnyPrice: full → true, empty → false", () => {
  assert(ladderHasAnyPrice(extractLadder(full)));
  assert(!ladderHasAnyPrice(extractLadder(empty)));
});

Deno.test("parsePriceHistory: date-keyed dict → chronologically-sorted [{ts, price_cents}] anchored at midnight UTC", () => {
  const psa10History = full.ebay.priceHistory.psa10;
  assertEquals(parsePriceHistory(psa10History), [
    { ts: "2025-11-08T00:00:00Z", price_cents: 16200 },
    { ts: "2025-11-15T00:00:00Z", price_cents: 16850 },
    { ts: "2025-11-22T00:00:00Z", price_cents: 17500 },
    { ts: "2025-12-01T00:00:00Z", price_cents: 18000 },
    { ts: "2026-05-01T00:00:00Z", price_cents: 18500 },
  ]);
});

Deno.test("parsePriceHistory: emitted ts decodes as a JS Date (RFC 3339)", () => {
  const out = parsePriceHistory(full.ebay.priceHistory.psa10);
  for (const p of out) {
    assert(!Number.isNaN(Date.parse(p.ts)), `ts ${p.ts} should parse as a Date`);
  }
});

Deno.test("parsePriceHistory: empty dict → []", () => {
  assertEquals(parsePriceHistory({}), []);
});

Deno.test("parsePriceHistory: missing input → []", () => {
  assertEquals(parsePriceHistory(undefined), []);
  assertEquals(parsePriceHistory(null), []);
});

Deno.test("parsePriceHistory: array input (wrong shape) → []", () => {
  assertEquals(parsePriceHistory([{ date: "2025-11-08", price: 100 }]), []);
});

Deno.test("parsePriceHistory: malformed entries dropped silently", () => {
  const series = {
    "2025-11-08": { average: 162.00, count: 1 },
    "bad-date":   { average: 100, count: 1 },
    "2025-11-15": { count: 2 },                     // missing average
    "2025-11-22": { average: null, count: 1 },      // null average
    "2025-12-01": { average: "not-a-number" },      // non-numeric
    "2026-05-01": { average: 180.00, count: 1 },
  };
  const out = parsePriceHistory(series);
  assertEquals(out.length, 2);
  assertEquals(out[0].ts, "2025-11-08T00:00:00Z");
  assertEquals(out[1].ts, "2026-05-01T00:00:00Z");
});

Deno.test("priceHistoryForTier: (PSA, '10') returns the psa10 series", () => {
  const series = priceHistoryForTier(full, "psa_10");
  assertEquals(typeof series, "object");
  // Spot-check: the series contains the 2026-05-01 daily aggregate.
  assert((series as Record<string, unknown>)["2026-05-01"], "psa10 series includes 2026-05-01");
});

Deno.test("priceHistoryForTier: (BGS, '10') returns null when no bgs10 history exists", () => {
  assertEquals(priceHistoryForTier(full, "bgs_10"), null);
});

Deno.test("priceHistoryForTier: 'loose' returns null", () => {
  assertEquals(priceHistoryForTier(full, "loose"), null);
});

Deno.test("priceHistoryForTier: null tier returns null", () => {
  assertEquals(priceHistoryForTier(full, null), null);
});

Deno.test("productUrl: returns card.tcgPlayerUrl when present", () => {
  assertEquals(productUrl(full), "https://www.tcgplayer.com/product/243172");
});

Deno.test("productUrl: derives a TCGPlayer URL from tcgPlayerId when tcgPlayerUrl is missing", () => {
  const card = { tcgPlayerId: "243172", name: "Charizard" };
  const url = productUrl(card);
  assertEquals(url, "https://www.tcgplayer.com/product/243172");
});

Deno.test("productUrl: rejects http (non-https) tcgPlayerUrl, falls back to synthesized", () => {
  const card = { tcgPlayerId: "243172", tcgPlayerUrl: "http://www.tcgplayer.com/product/243172" };
  assertEquals(productUrl(card), "https://www.tcgplayer.com/product/243172");
});

Deno.test("productUrl: rejects off-host tcgPlayerUrl, falls back to synthesized", () => {
  const card = { tcgPlayerId: "243172", tcgPlayerUrl: "https://attacker.example.com/charizard" };
  assertEquals(productUrl(card), "https://www.tcgplayer.com/product/243172");
});

Deno.test("productUrl: rejects malformed tcgPlayerUrl, falls back to synthesized", () => {
  const card = { tcgPlayerId: "243172", tcgPlayerUrl: "not a url" };
  assertEquals(productUrl(card), "https://www.tcgplayer.com/product/243172");
});

Deno.test("productUrl: accepts subdomain on tcgplayer.com", () => {
  const card = { tcgPlayerId: "243172", tcgPlayerUrl: "https://infinite.tcgplayer.com/product/243172" };
  assertEquals(productUrl(card), "https://infinite.tcgplayer.com/product/243172");
});
