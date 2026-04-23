import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { ebayFetchRecentSoldViaApi, ebayFetchRecentSoldViaScrape } from "@/graded/sources/ebay.js";

const F = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/ebay");
const mockOk = (body: string, headers: Record<string, string> = {}) =>
  vi.fn().mockResolvedValue(new Response(body, { status: 200, headers }));

describe("ebay source", () => {
  beforeEach(() => { vi.restoreAllMocks(); });

  it("api path: normalizes Marketplace Insights sold items", async () => {
    vi.stubGlobal("fetch", mockOk(readFileSync(join(F, "browse-sold-sample.json"), "utf8"), { "content-type": "application/json" }));
    const sales = await ebayFetchRecentSoldViaApi(`PSA 10 pokemon`, { token: "t", userAgent: "t" });
    expect(sales).toHaveLength(2);
    expect(sales[0]!.soldPrice).toBe(5800);
    expect(sales[0]!.title).toContain("Charizard");
    expect(sales[0]!.source).toBe("ebay");
    expect(sales[0]!.sourceListingId).toBe("115512345678");
  });

  it("scrape path: parses sold-items HTML", async () => {
    vi.stubGlobal("fetch", mockOk(readFileSync(join(F, "sold-items-page.html"), "utf8")));
    const sales = await ebayFetchRecentSoldViaScrape(`"PSA 10" pokemon`, { userAgent: "t" });
    expect(sales.length).toBeGreaterThanOrEqual(2);
    expect(sales.find((s) => s.title.includes("Charizard"))?.soldPrice).toBe(5800);
  });
});
