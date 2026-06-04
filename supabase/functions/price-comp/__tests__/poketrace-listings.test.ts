// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fetchPoketraceListings } from "../poketrace/listings.ts";

Deno.test("200 → parsed listings", async () => {
  const r = await fetchPoketraceListings(
    { apiKey: "k", baseUrl: "http://x" }, "uuid", "PSA", "10",
    {
      fetchJsonImpl: async () => ({
        status: 200,
        body: {
          data: [
            {
              sourceItemId: "e1", title: "t", price: 100, soldAt: "2026-05-01T00:00:00Z",
              grader: "PSA", grade: "10", listingUrl: "u",
            },
          ],
        },
      }),
    },
  );
  assertEquals(r.status, 200);
  assertEquals(r.listings.length, 1);
});

Deno.test("403 UPGRADE_REQUIRED → empty, no throw", async () => {
  const r = await fetchPoketraceListings(
    { apiKey: "k", baseUrl: "http://x" }, "uuid", "PSA", "10",
    { fetchJsonImpl: async () => ({ status: 403, body: { code: "UPGRADE_REQUIRED" } }) },
  );
  assertEquals(r.status, 403);
  assertEquals(r.listings, []);
});
