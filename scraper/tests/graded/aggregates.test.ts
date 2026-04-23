import { describe, it, expect } from "vitest";
import { computeMarketAggregate } from "@/graded/aggregates.js";

const sale = (price: number, daysAgo: number) => ({
  sold_price: price,
  sold_at: new Date(Date.now() - daysAgo * 86_400_000).toISOString(),
});

describe("computeMarketAggregate", () => {
  it("returns nulls for empty input", () => {
    const out = computeMarketAggregate([]);
    expect(out.sampleCount30d).toBe(0);
    expect(out.medianPrice).toBeNull();
    expect(out.lastSalePrice).toBeNull();
  });

  it("computes 30d median/high/low and 90d sample count", () => {
    const sales = [sale(100, 5), sale(120, 10), sale(140, 20), sale(200, 60), sale(50, 100)];
    const out = computeMarketAggregate(sales);
    expect(out.sampleCount30d).toBe(3);
    expect(out.sampleCount90d).toBe(4);
    expect(out.lowPrice).toBe(100);
    expect(out.highPrice).toBe(140);
    expect(out.medianPrice).toBe(120);
  });

  it("tracks latest sale across any window", () => {
    const sales = [sale(100, 5), sale(300, 1)];
    const out = computeMarketAggregate(sales);
    expect(out.lastSalePrice).toBe(300);
  });
});
