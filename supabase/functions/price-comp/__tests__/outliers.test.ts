// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.

// supabase/functions/price-comp/__tests__/outliers.test.ts
import { assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { detectOutliers, trimmedMean } from "../stats/outliers.ts";

describe("detectOutliers (MAD, 3σ threshold)", () => {
  it("flags nothing on tight cluster", () => {
    const prices = [12000, 12200, 12500, 12800, 13000, 13200];
    assertEquals(detectOutliers(prices), [false, false, false, false, false, false]);
  });

  it("flags one high outlier at 2x median", () => {
    const prices = [12000, 12200, 12500, 12800, 13000, 13200, 25000];
    const flags = detectOutliers(prices);
    assertEquals(flags[flags.length - 1], true);
    assertEquals(flags.slice(0, -1).every(f => !f), true);
  });

  it("flags one low outlier below median", () => {
    const prices = [100, 12000, 12200, 12500, 12800, 13000, 13200];
    const flags = detectOutliers(prices);
    assertEquals(flags[0], true);
    assertEquals(flags.slice(1).every(f => !f), true);
  });

  it("flags nothing when all identical (MAD = 0)", () => {
    assertEquals(detectOutliers([12000, 12000, 12000, 12000]), [false, false, false, false]);
  });

  it("flags nothing for n = 1", () => {
    assertEquals(detectOutliers([12000]), [false]);
  });
});

describe("trimmedMean", () => {
  it("equals mean when no outliers", () => {
    assertEquals(trimmedMean([100, 200, 300], [false, false, false]), 200);
  });

  it("excludes outliers from the mean", () => {
    assertEquals(trimmedMean([100, 200, 300, 10000], [false, false, false, true]), 200);
  });

  it("falls back to full mean if every row flagged", () => {
    assertEquals(trimmedMean([100, 200, 300], [true, true, true]), 200);
  });
});
