// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.
import { assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { callBrowseApi } from "../ebay/browse.ts";
import { __resetTokenCacheForTests } from "../ebay/oauth.ts";

interface FetchCall { url: string; init?: RequestInit }

function makeFetch(responses: Array<Response | ((call: FetchCall) => Response)>): {
  fn: typeof fetch;
  calls: () => FetchCall[];
} {
  const calls: FetchCall[] = [];
  let i = 0;
  const fn = async (input: string | URL | Request, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input.toString();
    calls.push({ url, init });
    const next = responses[i++] ?? responses[responses.length - 1]!;
    if (typeof next === "function") return next({ url, init }).clone();
    return next.clone();
  };
  return { fn: fn as unknown as typeof fetch, calls: () => calls };
}

const tokenResponse = () => new Response(
  JSON.stringify({ access_token: "test-token", expires_in: 7200 }),
  { status: 200 },
);

const browseResponse = (items: unknown[]) => new Response(
  JSON.stringify({ total: items.length, itemSummaries: items }),
  { status: 200 },
);

describe("callBrowseApi", () => {
  it("mints OAuth token then calls Browse search", async () => {
    __resetTokenCacheForTests();
    const { fn, calls } = makeFetch([
      tokenResponse(),
      browseResponse([
        {
          itemId: "v1|111|0",
          legacyItemId: "111",
          title: "Charizard PSA 10",
          price: { value: "1234.56", currency: "USD" },
          itemWebUrl: "https://ebay.com/itm/111",
          itemEndDate: "2026-06-01T00:00:00.000Z",
          buyingOptions: ["FIXED_PRICE"],
        },
      ]),
    ]);
    const result = await callBrowseApi({
      appId: "app", certId: "cert",
      q: "charizard psa 10", categoryId: "183454",
      limit: 50, windowDays: 90, fetchFn: fn,
      now: () => 1_000_000,
    });
    assertEquals(result.status, 200);
    assertEquals(result.listings.length, 1);
    assertEquals(result.listings[0].sold_price_cents, 123456);
    assertEquals(result.listings[0].title, "Charizard PSA 10");
    assertEquals(result.listings[0].url, "https://ebay.com/itm/111");
    assertEquals(result.listings[0].source_listing_id, "111");
    assertEquals(result.listings[0].sold_at, "2026-06-01T00:00:00.000Z");

    const browseCall = calls()[1]!;
    const u = new URL(browseCall.url);
    assertEquals(u.host, "api.ebay.com");
    assertEquals(u.pathname, "/buy/browse/v1/item_summary/search");
    assertEquals(u.searchParams.get("q"), "charizard psa 10");
    assertEquals(u.searchParams.get("category_ids"), "183454");
    assertEquals(u.searchParams.get("limit"), "50");
    const headers = new Headers(browseCall.init?.headers as HeadersInit | undefined);
    assertEquals(headers.get("authorization"), "Bearer test-token");
    assertEquals(headers.get("x-ebay-c-marketplace-id"), "EBAY_US");
  });

  it("skips items with non-USD currency", async () => {
    __resetTokenCacheForTests();
    const { fn } = makeFetch([
      tokenResponse(),
      browseResponse([
        { itemId: "1", title: "USD card PSA 10", price: { value: "10.00", currency: "USD" }, itemEndDate: "2026-06-01T00:00:00.000Z" },
        { itemId: "2", title: "EUR card PSA 10", price: { value: "10.00", currency: "EUR" }, itemEndDate: "2026-06-01T00:00:00.000Z" },
      ]),
    ]);
    const result = await callBrowseApi({
      appId: "a", certId: "c", q: "x", categoryId: "183454",
      limit: 50, windowDays: 90, fetchFn: fn,
    });
    assertEquals(result.listings.length, 1);
    assertEquals(result.listings[0].title, "USD card PSA 10");
  });

  it("returns empty listings on HTTP error without throwing", async () => {
    __resetTokenCacheForTests();
    const { fn } = makeFetch([
      tokenResponse(),
      new Response("err", { status: 500 }),
    ]);
    const result = await callBrowseApi({
      appId: "a", certId: "c", q: "x", categoryId: "183454",
      limit: 50, windowDays: 90, fetchFn: fn,
    });
    assertEquals(result.status, 500);
    assertEquals(result.listings.length, 0);
  });

  it("falls back to legacyItemId when itemId is unset", async () => {
    __resetTokenCacheForTests();
    const { fn } = makeFetch([
      tokenResponse(),
      browseResponse([
        { legacyItemId: "9999", title: "card PSA 10", price: { value: "1.00", currency: "USD" }, itemEndDate: "2026-06-01T00:00:00.000Z" },
      ]),
    ]);
    const result = await callBrowseApi({
      appId: "a", certId: "c", q: "x", categoryId: "183454",
      limit: 50, windowDays: 90, fetchFn: fn,
    });
    assertEquals(result.listings[0].source_listing_id, "9999");
  });
});
