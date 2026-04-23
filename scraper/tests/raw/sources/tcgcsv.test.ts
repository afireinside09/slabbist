import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { fetchGroups, fetchProducts, fetchPrices } from "@/raw/sources/tcgcsv.js";

const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/tcgcsv");
const load = (name: string) => JSON.parse(readFileSync(join(FIXTURES, name), "utf8"));

function mockOk(body: unknown) {
  return vi.fn().mockResolvedValue(
    new Response(JSON.stringify(body), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
}

describe("tcgcsv source", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("fetchGroups parses the category 3 groups payload", async () => {
    vi.stubGlobal("fetch", mockOk(load("groups-cat3.json")));
    const groups = await fetchGroups(3, { userAgent: "t" });
    expect(groups).toHaveLength(1);
    expect(groups[0]!.groupId).toBe(3188);
    expect(groups[0]!.categoryId).toBe(3);
  });

  it("fetchProducts parses the products payload", async () => {
    vi.stubGlobal("fetch", mockOk(load("products-group3-sv4.json")));
    const prods = await fetchProducts(3, 3188, { userAgent: "t" });
    expect(prods).toHaveLength(2);
    expect(prods[0]!.productId).toBe(500001);
    expect(prods[0]!.extendedData.length).toBeGreaterThan(0);
  });

  it("fetchPrices parses the prices payload", async () => {
    vi.stubGlobal("fetch", mockOk(load("prices-group3-sv4.json")));
    const prices = await fetchPrices(3, 3188, { userAgent: "t" });
    expect(prices).toHaveLength(3);
    expect(prices.find((p) => p.subTypeName === "Holofoil")?.marketPrice).toBe(17.8);
  });

  it("rejects malformed payload via zod", async () => {
    vi.stubGlobal("fetch", mockOk({ success: true, errors: [], results: [{ wrong: "shape" }] }));
    await expect(fetchGroups(3, { userAgent: "t" })).rejects.toThrow();
  });
});
