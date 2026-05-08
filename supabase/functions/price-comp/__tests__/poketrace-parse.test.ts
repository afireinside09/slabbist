// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  extractTierPrice,
  tierPriceToBlock,
  parseHistoryResponse,
  type RawTierPrice,
} from "../poketrace/parse.ts";

Deno.test("extractTierPrice: walks data.prices.<source>.<tier>", () => {
  const card = {
    data: {
      id: "uuid-1",
      prices: {
        ebay:      { PSA_10: { avg: 185.00, low: 170.00, high: 199.99 } },
        tcgplayer: { NEAR_MINT: { avg: 95 } },
      },
    },
  };
  const tp = extractTierPrice(card, "PSA_10");
  assertEquals(tp?.avg, 185.0);
  assertEquals(tp?.low, 170.0);
  assertEquals(tp?.high, 199.99);
});

Deno.test("extractTierPrice: missing tier returns null", () => {
  const card = { data: { id: "uuid-1", prices: { ebay: { PSA_9: { avg: 50 } } } } };
  assertEquals(extractTierPrice(card, "PSA_10"), null);
});

Deno.test("extractTierPrice: missing prices returns null", () => {
  assertEquals(extractTierPrice({ data: { id: "uuid-1" } }, "PSA_10"), null);
});

Deno.test("tierPriceToBlock: dollars → cents, missing fields → null", () => {
  const raw: RawTierPrice = {
    avg: 185.50,
    low: 170,
    high: 199.99,
    avg30d: 180,
    median7d: 178.45,
    trend: "stable",
    confidence: "high",
    saleCount: 42,
  };
  const block = tierPriceToBlock(raw);
  assertEquals(block.avg_cents, 18550);
  assertEquals(block.low_cents, 17000);
  assertEquals(block.high_cents, 19999);
  assertEquals(block.avg_30d_cents, 18000);
  assertEquals(block.median_7d_cents, 17845);
  assertEquals(block.trend, "stable");
  assertEquals(block.confidence, "high");
  assertEquals(block.sale_count, 42);
  // Fields not present in raw → null
  assertEquals(block.avg_1d_cents, null);
  assertEquals(block.avg_7d_cents, null);
  assertEquals(block.median_3d_cents, null);
  assertEquals(block.median_30d_cents, null);
});

Deno.test("tierPriceToBlock: rounds half away from zero", () => {
  const block = tierPriceToBlock({ avg: 12.345 });
  // 12.345 * 100 = 1234.5 → round → 1235 (Math.round is half-to-positive)
  assertEquals(block.avg_cents, 1235);
});

Deno.test("tierPriceToBlock: rejects non-numeric trend/confidence", () => {
  // deno-lint-ignore no-explicit-any
  const block = tierPriceToBlock({ avg: 50, trend: "wat" as any, confidence: 7 as any });
  assertEquals(block.trend, null);
  assertEquals(block.confidence, null);
});

Deno.test("parseHistoryResponse: maps date+avg → ts+price_cents", () => {
  const resp = {
    data: [
      { date: "2026-04-08", source: "ebay", avg: 180 },
      { date: "2026-04-09", source: "ebay", avg: 182.5 },
      { date: "2026-04-10", source: "ebay" }, // missing avg → skipped
      { date: "2026-04-11", source: "ebay", avg: null }, // null avg → skipped
    ],
  };
  const points = parseHistoryResponse(resp);
  assertEquals(points.length, 2);
  assertEquals(points[0], { ts: "2026-04-08T00:00:00Z", price_cents: 18000 });
  assertEquals(points[1], { ts: "2026-04-09T00:00:00Z", price_cents: 18250 });
});

Deno.test("parseHistoryResponse: missing or non-array data → []", () => {
  assertEquals(parseHistoryResponse({} as Record<string, unknown>), []);
  assertEquals(parseHistoryResponse({ data: null }), []);
  assertEquals(parseHistoryResponse({ data: "nope" } as Record<string, unknown>), []);
});
