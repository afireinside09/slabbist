// tests/graded/ingest/ebay-sold.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { runEbaySoldIngest } from "@/graded/ingest/ebay-sold.js";
import { makeFakeSupabase } from "../../_helpers/fake-supabase.js";

const F = (...p: string[]) => join(dirname(fileURLToPath(import.meta.url)), "../../fixtures", ...p);

describe("runEbaySoldIngest", () => {
  beforeEach(() => { vi.restoreAllMocks(); });

  it("ingests sold listings from scrape fixture, creates identities, upserts sales + aggregates", async () => {
    const htmlBody = readFileSync(F("ebay/sold-items-page.html"), "utf8");
    vi.stubGlobal("fetch", vi.fn().mockImplementation(
      () => Promise.resolve(new Response(htmlBody, { status: 200 })),
    ));

    const supa = makeFakeSupabase() as any;
    const res = await runEbaySoldIngest({
      supabase: supa, userAgent: "t",
      queries: [`"PSA 10" pokemon`, `"BGS 9.5" pokemon`],
    });

    expect(res.status).toBe("completed");

    const sales = await supa._debug.pool.query("select * from public.graded_market_sales");
    expect(sales.rows.length).toBeGreaterThanOrEqual(2);

    const market = await supa._debug.pool.query("select * from public.graded_market");
    expect(market.rows.length).toBeGreaterThanOrEqual(1);
  });

  it("collapses two listings for the same slab into one identity row (Issue 1 regression)", async () => {
    // Two PSA-10 Charizard listings with slightly different raw titles.
    // After cleanTitle strips "PSA 10" and cert noise they should map to the same cardName
    // and therefore the same identity row.
    const html = `<ul class="srp-results">
  <li class="s-item">
    <div class="s-item__title">1999 Pokemon Base Set Charizard Holo PSA 10 Gem Mint</div>
    <span class="s-item__price">$5800.00</span>
    <a class="s-item__link" href="https://www.ebay.com/itm/100000000001"></a>
    <span class="s-item__ended-date">Apr 20, 2026</span>
  </li>
  <li class="s-item">
    <div class="s-item__title">1999 Pokemon Base Set Charizard Holo PSA 10 Cert #12345678</div>
    <span class="s-item__price">$6100.00</span>
    <a class="s-item__link" href="https://www.ebay.com/itm/100000000002"></a>
    <span class="s-item__ended-date">Apr 21, 2026</span>
  </li>
</ul>`;

    vi.stubGlobal("fetch", vi.fn().mockImplementation(
      () => Promise.resolve(new Response(html, { status: 200 })),
    ));

    const supa = makeFakeSupabase() as any;
    const res = await runEbaySoldIngest({
      supabase: supa, userAgent: "t",
      queries: [`"PSA 10" pokemon`],
    });

    expect(res.status).toBe("completed");

    const sales = await supa._debug.pool.query("select * from public.graded_market_sales");
    const identities = await supa._debug.pool.query("select * from public.graded_card_identities");

    // Two sales should exist (different listing IDs)
    expect(sales.rows.length).toBe(2);
    // But they must share a single identity row — not one per listing
    expect(identities.rows.length).toBe(1);
    // Both sales must point to the same identity
    const identityIds = new Set(sales.rows.map((r: any) => r.identity_id));
    expect(identityIds.size).toBe(1);
  });
});
