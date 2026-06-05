import { describe, it, expect, vi } from "vitest";
import { backfillProducts, type CompProduct, type BackfillDeps } from "@/graded/ingest/poketrace-comp.js";

const NOW = Date.parse("2026-06-01T00:00:00Z");
const day = 86_400_000;
const SEVEN_DAYS = 7 * day;

function deps(over: Partial<BackfillDeps> = {}): BackfillDeps {
  return {
    now: () => NOW,
    dailyFloor: 200,
    maxRequests: Infinity,
    search: async () => ({ cardId: "uuid", dailyRemaining: 5000 }),
    detail: async () => ({ psa10PriceCents: 5000, ptSaleCount: null, dailyRemaining: 5000 }),
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

  it("writes nothing and counts noMatch on zero search results", async () => {
    // No-match products are no longer cached — we persist nothing so the table
    // holds only rows the Grade Gains page reads.
    const upsert = vi.fn(async () => {});
    const r = await backfillProducts([{ productId: 9, resolvedAt: null }],
      deps({ upsert, search: async () => ({ cardId: null, dailyRemaining: 5000 }) }));
    expect(r.noMatch).toBe(1);
    expect(r.covered).toBe(0);
    expect(upsert).not.toHaveBeenCalled();
  });

  it("writes nothing and counts noPrice when a matched card has no PSA 10 price", async () => {
    // Matched the card (2 requests spent) but it carries no PSA 10 price → not
    // useful to the consumer, so persist nothing.
    const upsert = vi.fn(async () => {});
    const r = await backfillProducts([{ productId: 7, resolvedAt: null }],
      deps({ upsert, detail: async () => ({ psa10PriceCents: null, ptSaleCount: null, dailyRemaining: 5000 }) }));
    expect(r.noPrice).toBe(1);
    expect(r.covered).toBe(0);
    expect(r.requests).toBe(2); // search + detail both spent
    expect(upsert).not.toHaveBeenCalled();
  });

  it("does NOT write on transient failure (undefined cardId)", async () => {
    const upsert = vi.fn(async () => {});
    const r = await backfillProducts([{ productId: 9, resolvedAt: null }],
      deps({ upsert, search: async () => ({ cardId: undefined, dailyRemaining: 5000 }) }));
    expect(upsert).not.toHaveBeenCalled();
    expect(r.transient).toBe(1);
  });

  it("persists only the PSA 10 price + sale count (no trend/confidence)", async () => {
    const upsert = vi.fn(async () => {});
    await backfillProducts([{ productId: 3, resolvedAt: null }],
      deps({ upsert, detail: async () => ({ psa10PriceCents: 4200, ptSaleCount: 11, dailyRemaining: 5000 }) }));
    expect(upsert).toHaveBeenCalledTimes(1);
    const row = (upsert as ReturnType<typeof vi.fn>).mock.calls[0]![0] as Record<string, unknown>;
    expect(row).toMatchObject({ product_id: 3, poketrace_card_id: "uuid", psa10_price_cents: 4200, pt_sale_count: 11 });
    expect(row).not.toHaveProperty("pt_trend");
    expect(row).not.toHaveProperty("pt_confidence");
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
      detail: async () => ({ psa10PriceCents: 5000, ptSaleCount: null, dailyRemaining: 150 }),
    }));
    expect(r.covered).toBe(1);
    expect(r.stoppedOnBudget).toBe(true);
    expect(upsert).toHaveBeenCalledTimes(1);
  });

  it("stops at the maxRequests cap mid-list", async () => {
    // Each matched product costs 2 requests (search + detail). With a cap of 2,
    // product 1 exhausts the budget; products 2 and 3 are never touched.
    const upsert = vi.fn(async () => {});
    const products: CompProduct[] = [
      { productId: 1, resolvedAt: null },
      { productId: 2, resolvedAt: null },
      { productId: 3, resolvedAt: null },
    ];
    const r = await backfillProducts(products, deps({ upsert, maxRequests: 2 }));
    expect(r.covered).toBe(1);
    expect(r.requests).toBe(2);
    expect(r.stoppedOnBudget).toBe(true);
    expect(upsert).toHaveBeenCalledTimes(1);
    expect(upsert).toHaveBeenCalledWith(expect.objectContaining({ product_id: 1 }));
  });

  it("counts noMatch then stops when search daily-remaining is below the floor", async () => {
    // Post-search floor guard on the no-match branch: product 1 is counted but
    // nothing is written, and the run halts before product 2.
    const upsert = vi.fn(async () => {});
    const products: CompProduct[] = [
      { productId: 1, resolvedAt: null },
      { productId: 2, resolvedAt: null },
    ];
    const r = await backfillProducts(products, deps({
      upsert,
      search: async () => ({ cardId: null, dailyRemaining: 150 }), // no match, below floor 200
    }));
    expect(r.noMatch).toBe(1);
    expect(r.stoppedOnBudget).toBe(true);
    expect(upsert).not.toHaveBeenCalled();
  });

  it("applies the 7-day skip at the exact boundary", async () => {
    // < 7 days old → skip; >= 7 days old → process. Probe both sides of the edge.
    const upsert = vi.fn(async () => {});
    const products: CompProduct[] = [
      { productId: 1, resolvedAt: new Date(NOW - SEVEN_DAYS + 1).toISOString() }, // just inside → skip
      { productId: 2, resolvedAt: new Date(NOW - SEVEN_DAYS - 1).toISOString() }, // just outside → process
    ];
    const r = await backfillProducts(products, deps({ upsert }));
    expect(r.skippedFresh).toBe(1);
    expect(upsert).toHaveBeenCalledTimes(1);
    expect(upsert).toHaveBeenCalledWith(expect.objectContaining({ product_id: 2 }));
  });
});
