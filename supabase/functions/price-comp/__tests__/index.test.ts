// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.
// supabase/functions/price-comp/__tests__/index.test.ts
// Pins down handler math against a known fixture. This asserts the exact
// expected aggregate values the full handler is expected to produce on
// mi-with-outlier.json (the fixture with 1 high outlier and 1 low outlier).
// A full handler e2e lives in manual smoke-test in Task 18.

import { assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { detectOutliers, trimmedMean } from "../stats/outliers.ts";
import { mean, median, low, high } from "../stats/aggregates.ts";
import { confidence } from "../stats/confidence.ts";

describe("handler math on fixture mi-with-outlier", () => {
  it("computes expected aggregates with two outliers", async () => {
    const text = await Deno.readTextFile(
      new URL("../__fixtures__/mi-with-outlier.json", import.meta.url),
    );
    const data = JSON.parse(text) as { itemSales: Array<{ lastSoldPrice: { value: string } }> };
    const prices = data.itemSales.map(s => Math.round(Number(s.lastSoldPrice.value) * 100));
    const flags = detectOutliers(prices);
    // Fixture: 1st ($2500) should be high outlier; 2nd ($1) should be low outlier.
    assertEquals(flags[0], true);
    assertEquals(flags[1], true);
    assertEquals(flags.slice(2).every(f => !f), true);

    const trimmed = trimmedMean(prices, flags);
    // Eight normal prices: 12000,12200,12500,12800,11500,13000,13500,11800
    // Sum = 99300; /8 = 12412.5; banker's rounding of .5 → even → 12412
    assertEquals(trimmed, 12412);

    // Mean of all 10 prices including outliers:
    // 250000 + 100 + 12000 + 12200 + 12500 + 12800 + 11500 + 13000 + 13500 + 11800 = 349400
    // /10 = 34940
    assertEquals(mean(prices), 34940);

    // Median of 10 → avg of 5th and 6th value of sorted ascending.
    // sorted: [100, 11500, 11800, 12000, 12200, 12500, 12800, 13000, 13500, 250000]
    // positions 5 and 6 → 12200 and 12500; avg = 12350
    assertEquals(median(prices), 12350);

    assertEquals(low(prices), 100);
    assertEquals(high(prices), 250000);
    assertEquals(confidence(10, 90), 1.0);
  });
});
