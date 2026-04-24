// supabase/functions/price-comp/__tests__/aggregates.test.ts
import { assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { mean, median, low, high } from "../stats/aggregates.ts";

describe("aggregates", () => {
  it("mean rounds half-to-even for integer cents", () => {
    assertEquals(mean([100, 200, 300]), 200);
    // 100.5 → half-to-even → 100 (nearest even)
    assertEquals(mean([100, 101]), 100);
  });

  it("median handles odd and even lengths", () => {
    assertEquals(median([100, 200, 300]), 200);
    assertEquals(median([100, 200, 300, 400]), 250);
  });

  it("low and high on single-element arrays", () => {
    assertEquals(low([42]), 42);
    assertEquals(high([42]), 42);
  });

  it("throws on empty input", () => {
    let threw = false;
    try { mean([]); } catch { threw = true; }
    assertEquals(threw, true);
  });
});
