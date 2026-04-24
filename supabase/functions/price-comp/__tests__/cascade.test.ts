// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.
import { assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { runCascade } from "../ebay/cascade.ts";
import type { GradedCardIdentity, SoldListingRaw } from "../types.ts";

const identity: GradedCardIdentity = {
  id: "abc", game: "pokemon", language: "en", set_code: null,
  set_name: "Surging Sparks", card_number: "247/191",
  card_name: "Pikachu ex", variant: null, year: 2024,
};

async function loadFixture(name: string): Promise<SoldListingRaw[]> {
  const text = await Deno.readTextFile(
    new URL(`../__fixtures__/${name}`, import.meta.url),
  );
  const data = JSON.parse(text) as { itemSales: Array<{ itemId: string; title: string; lastSoldDate: string; lastSoldPrice: { value: string }; itemWebUrl: string }> };
  return data.itemSales.map(s => ({
    sold_price_cents: Math.round(Number(s.lastSoldPrice.value) * 100),
    sold_at: s.lastSoldDate,
    title: s.title,
    url: s.itemWebUrl,
    source_listing_id: s.itemId.split("|")[1] ?? s.itemId,
  }));
}

describe("runCascade", () => {
  it("stops at first bucket with >= minResults after title-parse validation", async () => {
    const dense = await loadFixture("mi-dense.json");
    let calls = 0;
    const result = await runCascade(identity, "PSA", "10", {
      minResults: 10,
      fetchBucket: async (_q) => { calls++; return { status: 200, listings: dense }; },
    });
    assertEquals(result.sampleWindowDays, 90);
    assertEquals(result.bucketHit, 1);
    assertEquals(calls, 1);
    assertEquals(result.listings.length, 10);
  });

  it("falls through to bucket 2 when bucket 1 sparse", async () => {
    const sparse = await loadFixture("mi-sparse.json");
    const dense = await loadFixture("mi-dense.json");
    let call = 0;
    const result = await runCascade(identity, "PSA", "10", {
      minResults: 10,
      fetchBucket: async (_q) => {
        call++;
        return call === 1
          ? { status: 200, listings: sparse }
          : { status: 200, listings: dense };
      },
    });
    assertEquals(result.bucketHit, 2);
    assertEquals(result.listings.length, 10);
  });

  it("returns best available when all buckets sparse", async () => {
    const sparse = await loadFixture("mi-sparse.json");
    const result = await runCascade(identity, "PSA", "10", {
      minResults: 10,
      fetchBucket: async (_q) => ({ status: 200, listings: sparse }),
    });
    assertEquals(result.listings.length, 3);
    assertEquals(result.sampleWindowDays === 90 || result.sampleWindowDays === 365, true);
  });

  it("returns empty when every bucket is empty", async () => {
    const result = await runCascade(identity, "PSA", "10", {
      minResults: 10,
      fetchBucket: async (_q) => ({ status: 200, listings: [] }),
    });
    assertEquals(result.listings.length, 0);
    assertEquals(result.bucketHit, null);
  });

  it("drops listings that fail title-parse validation (wrong grade)", async () => {
    const mixed: SoldListingRaw[] = [
      { sold_price_cents: 10000, sold_at: "2026-04-20T00:00:00Z", title: "PSA 10 card", url: "u", source_listing_id: "1" },
      { sold_price_cents: 20000, sold_at: "2026-04-19T00:00:00Z", title: "PSA 9 card", url: "u", source_listing_id: "2" },
    ];
    const result = await runCascade(identity, "PSA", "10", {
      minResults: 10,
      fetchBucket: async () => ({ status: 200, listings: mixed }),
    });
    assertEquals(result.listings.length, 1);
    assertEquals(result.listings[0].sold_price_cents, 10000);
  });
});
