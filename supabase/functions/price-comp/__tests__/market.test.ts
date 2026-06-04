// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { upsertMarketLadder, readMarketLadder } from "../persistence/market.ts";

// Minimal supabase stub that captures upsert input and returns controllable read data.
function makeSupabaseStub(opts: {
  upsertCapture?: { rows: any[] };
  readData?: Record<string, unknown> | null;
}) {
  return {
    from(_t: string) {
      return {
        upsert(row: any, _options?: any) {
          if (opts.upsertCapture) opts.upsertCapture.rows.push(row);
          return Promise.resolve({ error: null });
        },
        select(_cols: string) {
          return {
            eq(_c: string, _v: unknown) {
              return {
                eq(_c: string, _v: unknown) {
                  return {
                    eq(_c: string, _v: unknown) {
                      return {
                        eq(_c: string, _v: unknown) {
                          return {
                            maybeSingle() {
                              return Promise.resolve({ data: opts.readData ?? null, error: null });
                            },
                          };
                        },
                      };
                    },
                  };
                },
              };
            },
          };
        },
      };
    },
  } as unknown;
}

Deno.test("upsertMarketLadder: writes row with source='poketrace' and correct pt_avg", async () => {
  const captured: any[] = [];
  const sb = makeSupabaseStub({ upsertCapture: { rows: captured } });
  await upsertMarketLadder(sb as any, {
    identityId: "id-1",
    gradingService: "PSA",
    grade: "10",
    headlinePriceCents: 18550,
    priceHistory: [{ ts: "2026-05-01T00:00:00Z", price_cents: 18000 }],
    poketrace: {
      avgCents: 18550, lowCents: 17000, highCents: 20000,
      avg1dCents: null, avg7dCents: null, avg30dCents: 18000,
      median3dCents: null, median7dCents: 17845, median30dCents: null,
      trend: "stable", confidence: "high", saleCount: 42,
      tierPricesCents: { psa_10: 18550, psa_9: 12000 },
    },
  });
  assertEquals(captured.length, 1);
  const row = captured[0];
  assertEquals(row.source, "poketrace");
  assertEquals(row.pt_avg, 185.5);
  assertEquals(row.pt_low, 170);
  assertEquals(row.pt_high, 200);
  assertEquals(row.pt_avg_30d, 180);
  assertEquals(row.pt_median_7d, 178.45);
  assertEquals(row.pt_trend, "stable");
  assertEquals(row.pt_confidence, "high");
  assertEquals(row.pt_sale_count, 42);
  assertEquals(row.pt_tier_prices_cents, { psa_10: 18550, psa_9: 12000 });
  assertEquals(row.headline_price, 185.5);
  assertEquals(row.identity_id, "id-1");
  assertEquals(row.grading_service, "PSA");
  assertEquals(row.grade, "10");
});

Deno.test("readMarketLadder: null data returns null", async () => {
  const sb = makeSupabaseStub({ readData: null });
  const r = await readMarketLadder(sb as any, "id-1", "PSA", "10");
  assertEquals(r, null);
});

Deno.test("readMarketLadder: decimal → cents conversion is correct", async () => {
  const sb = makeSupabaseStub({
    readData: {
      headline_price: "185.50",
      price_history: [{ ts: "2026-05-01T00:00:00Z", price_cents: 18000 }],
      updated_at: "2026-05-02T00:00:00Z",
      pt_avg: "185.50",
      pt_low: "170.00",
      pt_high: null,
      pt_avg_1d: null, pt_avg_7d: null, pt_avg_30d: "180.00",
      pt_median_3d: null, pt_median_7d: "178.45", pt_median_30d: null,
      pt_trend: "stable", pt_confidence: "high",
      pt_sale_count: 42,
      pt_tier_prices_cents: { psa_10: 18550 },
    },
  });
  const r = await readMarketLadder(sb as any, "id-1", "PSA", "10");
  assertEquals(r?.headlinePriceCents, 18550);
  assertEquals(r?.poketrace.avgCents, 18550);
  assertEquals(r?.poketrace.lowCents, 17000);
  assertEquals(r?.poketrace.highCents, null);
  assertEquals(r?.poketrace.avg30dCents, 18000);
  assertEquals(r?.poketrace.median7dCents, 17845);
  assertEquals(r?.poketrace.saleCount, 42);
  assertEquals(r?.poketrace.tierPricesCents, { psa_10: 18550 });
  assertEquals(r?.priceHistory.length, 1);
});
