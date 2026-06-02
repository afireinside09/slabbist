import { describe, it, expect, vi } from "vitest";
import { backfillProducts, type CompProduct, type BackfillDeps } from "@/graded/ingest/poketrace-comp.js";

const NOW = Date.parse("2026-06-01T00:00:00Z");
const day = 86_400_000;

function deps(over: Partial<BackfillDeps> = {}): BackfillDeps {
  return {
    now: () => NOW,
    dailyFloor: 200,
    maxRequests: Infinity,
    search: async () => ({ cardId: "uuid", dailyRemaining: 5000 }),
    detail: async () => ({ psa10PriceCents: 5000, ptTrend: null, ptConfidence: null, ptSaleCount: null, dailyRemaining: 5000 }),
    upsert: vi.fn(async () => {}),
    ...over,
  };
}

describe("backfillProducts", () => {
  it("skips products resolved within 7 days", async () => {
    const upsert = vi.fn(async () => {});
    const products: CompProduct[] = [
      { productId: 1, resolvedAt: new Date(NOW - 2 * day).toISOString() }, // fresh → skip
      { productId: 2, resolvedAt: null },                                   // never → process
    ];
    const r = await backfillProducts(products, deps({ upsert }));
    expect(r.skippedFresh).toBe(1);
    expect(upsert).toHaveBeenCalledTimes(1);
    expect(upsert).toHaveBeenCalledWith(expect.objectContaining({ product_id: 2, psa10_price_cents: 5000 }));
  });

  it("writes the empty-string sentinel on zero search results", async () => {
    const upsert = vi.fn(async () => {});
    const r = await backfillProducts([{ productId: 9, resolvedAt: null }],
      deps({ upsert, search: async () => ({ cardId: null, dailyRemaining: 5000 }) }));
    expect(r.noMatch).toBe(1);
    expect(upsert).toHaveBeenCalledWith(expect.objectContaining({ product_id: 9, poketrace_card_id: "", psa10_price_cents: null }));
  });

  it("does NOT write on transient failure (undefined cardId)", async () => {
    const upsert = vi.fn(async () => {});
    const r = await backfillProducts([{ productId: 9, resolvedAt: null }],
      deps({ upsert, search: async () => ({ cardId: undefined, dailyRemaining: 5000 }) }));
    expect(upsert).not.toHaveBeenCalled();
    expect(r.transient).toBe(1);
  });

  it("stops when daily-remaining drops below the floor", async () => {
    const upsert = vi.fn(async () => {});
    const products: CompProduct[] = [
      { productId: 1, resolvedAt: null },
      { productId: 2, resolvedAt: null },
    ];
    // First search returns just-above-floor; detail returns below-floor → stop before product 2.
    const r = await backfillProducts(products, deps({
      upsert,
      search: async () => ({ cardId: "uuid", dailyRemaining: 250 }),
      detail: async () => ({ psa10PriceCents: 5000, ptTrend: null, ptConfidence: null, ptSaleCount: null, dailyRemaining: 150 }),
    }));
    expect(r.covered).toBe(1);
    expect(r.stoppedOnBudget).toBe(true);
    expect(upsert).toHaveBeenCalledTimes(1);
  });
});
