import { describe, it, expect } from "vitest";
import { searchCardId, fetchPsa10, type PoketraceClient } from "@/graded/sources/poketrace.js";

function clientWith(handler: (path: string) => { status: number; json: unknown; daily?: string }): PoketraceClient {
  return {
    apiKey: "k",
    baseUrl: "https://x/v1",
    fetchImpl: async (input) => {
      const path = String(input).replace("https://x/v1", "");
      const { status, json, daily } = handler(path);
      return new Response(JSON.stringify(json), {
        status,
        headers: {
          "content-type": "application/json",
          ...(daily ? { "x-ratelimit-daily-remaining": daily } : {}),
        },
      });
    },
  };
}

describe("searchCardId", () => {
  it("returns the first match uuid and the daily-remaining header", async () => {
    const c = clientWith(() => ({ status: 200, json: { data: [{ id: "uuid-1" }] }, daily: "950" }));
    const r = await searchCardId(c, 12345);
    expect(r).toEqual({ cardId: "uuid-1", dailyRemaining: 950 });
  });

  it("returns null cardId on zero results (sentinel case)", async () => {
    const c = clientWith(() => ({ status: 200, json: { data: [] }, daily: "900" }));
    const r = await searchCardId(c, 12345);
    expect(r).toEqual({ cardId: null, dailyRemaining: 900 });
  });

  it("returns undefined cardId (transient) on non-200 so the caller skips writing a sentinel", async () => {
    const c = clientWith(() => ({ status: 503, json: {} }));
    const r = await searchCardId(c, 12345);
    expect(r.cardId).toBeUndefined();
  });
});

describe("fetchPsa10", () => {
  it("extracts PSA_10 avg as cents plus trend/confidence/saleCount", async () => {
    const c = clientWith(() => ({
      status: 200,
      json: { data: { prices: { ebay: { PSA_10: { avg: 50.5, trend: "up", confidence: "high", saleCount: 12 } } } } },
      daily: "800",
    }));
    const r = await fetchPsa10(c, "uuid-1");
    expect(r).toEqual({
      psa10PriceCents: 5050, ptTrend: "up", ptConfidence: "high", ptSaleCount: 12, dailyRemaining: 800,
    });
  });

  it("returns null price when the card has no PSA_10 tier", async () => {
    const c = clientWith(() => ({ status: 200, json: { data: { prices: { ebay: { PSA_9: { avg: 10 } } } } }, daily: "799" }));
    const r = await fetchPsa10(c, "uuid-1");
    expect(r.psa10PriceCents).toBeNull();
  });
});

describe("daily-remaining header parsing", () => {
  // A present-but-empty header must read as absent (null), NOT as 0 — otherwise
  // Number("") === 0 would look like "zero budget left" and trip a spurious stop.
  it("treats an empty-string x-ratelimit-daily-remaining as null, not 0", async () => {
    const c: PoketraceClient = {
      apiKey: "k",
      baseUrl: "https://x/v1",
      fetchImpl: async () =>
        new Response(JSON.stringify({ data: [{ id: "uuid-1" }] }), {
          status: 200,
          headers: { "content-type": "application/json", "x-ratelimit-daily-remaining": "" },
        }),
    };
    const r = await searchCardId(c, 12345);
    expect(r.dailyRemaining).toBeNull();
  });
});
