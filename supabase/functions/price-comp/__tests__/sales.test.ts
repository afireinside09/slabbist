// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { upsertSoldListings } from "../persistence/sales.ts";

Deno.test("upserts listings with identity + tier, dollars→numeric", async () => {
  let captured: any[] = [];
  const sb = {
    from: () => ({
      upsert: async (rows: any[], _opts?: any) => {
        captured = rows;
        return { error: null };
      },
    }),
  };
  await upsertSoldListings(sb as any, "id-1", "PSA", "10", [
    {
      source_listing_id: "e1", title: "t", price_cents: 12050, sold_at: "2026-05-01T00:00:00Z",
      grader: "PSA", grade: "10", condition: "Graded", url: "u", anomaly_flag: null,
    },
  ]);
  assertEquals(captured.length, 1);
  assertEquals(captured[0].sold_price, 120.5);
  assertEquals(captured[0].identity_id, "id-1");
  assertEquals(captured[0].grading_service, "PSA");
  assertEquals(captured[0].grade, "10");
  assertEquals(captured[0].source, "ebay");
  assertEquals(captured[0].source_listing_id, "e1");
});

Deno.test("empty list is a no-op", async () => {
  let called = false;
  const sb = {
    from: () => ({
      upsert: async () => {
        called = true;
        return { error: null };
      },
    }),
  };
  await upsertSoldListings(sb as any, "id-1", "PSA", "10", []);
  assertEquals(called, false);
});
