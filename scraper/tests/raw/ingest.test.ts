// tests/raw/ingest.test.ts
import { describe, it, expect, beforeEach, vi } from "vitest";
import { ingestTcgcsvForCategory } from "@/raw/ingest.js";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { makeFakeSupabase } from "../_helpers/fake-supabase.js";

const F = join(dirname(fileURLToPath(import.meta.url)), "../fixtures/tcgcsv");

function mockOk(body: unknown) {
  return vi.fn().mockResolvedValue(new Response(JSON.stringify(body), {
    status: 200, headers: { "content-type": "application/json" },
  }));
}

describe("ingestTcgcsvForCategory", () => {
  beforeEach(() => { vi.restoreAllMocks(); });

  it("ingests one category end-to-end and records a completed run", async () => {
    const groups = JSON.parse(readFileSync(join(F, "groups-cat3.json"), "utf8"));
    const products = JSON.parse(readFileSync(join(F, "products-group3-sv4.json"), "utf8"));
    const prices = JSON.parse(readFileSync(join(F, "prices-group3-sv4.json"), "utf8"));
    const seq = [groups, products, prices];
    const fetchMock = vi.fn().mockImplementation(async () =>
      new Response(JSON.stringify(seq.shift()), { status: 200, headers: { "content-type": "application/json" } }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const supa = makeFakeSupabase() as any;
    const result = await ingestTcgcsvForCategory({
      categoryId: 3,
      supabase: supa,
      userAgent: "test",
      concurrency: 1,
      delayMs: 0,
    });

    expect(result.status).toBe("completed");
    expect(result.groupsDone).toBe(1);
    expect(result.productsUpserted).toBe(2);
    expect(result.pricesUpserted).toBe(3);

    const products2 = await supa._debug.pool.query("select * from public.tcg_products");
    expect(products2.rows).toHaveLength(2);
    const history = await supa._debug.pool.query("select * from public.tcg_price_history");
    expect(history.rows).toHaveLength(3);
  });
});
