// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.
import { assertEquals, assertRejects } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { getOAuthToken, __resetTokenCacheForTests } from "../ebay/oauth.ts";

function mockFetch(response: Response): typeof fetch {
  let calls = 0;
  const fn = async (..._args: Parameters<typeof fetch>) => {
    calls++;
    return response.clone();
  };
  (fn as any).calls = () => calls;
  return fn as unknown as typeof fetch;
}

describe("getOAuthToken", () => {
  it("requests a token and returns it", async () => {
    __resetTokenCacheForTests();
    const fetchFn = mockFetch(new Response(
      JSON.stringify({ access_token: "abc123", expires_in: 7200 }),
      { status: 200 },
    ));
    const token = await getOAuthToken({
      appId: "app", certId: "cert",
      scope: "https://api.ebay.com/oauth/api_scope/buy.marketplace.insights",
      fetchFn,
      now: () => 1_000_000,
    });
    assertEquals(token, "abc123");
    assertEquals((fetchFn as any).calls(), 1);
  });

  it("caches and does not re-fetch within expiry window", async () => {
    __resetTokenCacheForTests();
    const fetchFn = mockFetch(new Response(
      JSON.stringify({ access_token: "abc", expires_in: 7200 }),
      { status: 200 },
    ));
    let now = 1_000_000;
    await getOAuthToken({ appId: "a", certId: "c", scope: "s", fetchFn, now: () => now });
    now += 1000;
    await getOAuthToken({ appId: "a", certId: "c", scope: "s", fetchFn, now: () => now });
    assertEquals((fetchFn as any).calls(), 1);
  });

  it("refreshes once cache reaches the 5-min safety window", async () => {
    __resetTokenCacheForTests();
    const fetchFn = mockFetch(new Response(
      JSON.stringify({ access_token: "abc", expires_in: 7200 }),
      { status: 200 },
    ));
    let now = 1_000_000;
    await getOAuthToken({ appId: "a", certId: "c", scope: "s", fetchFn, now: () => now });
    now += (7200 - 299) * 1000;
    await getOAuthToken({ appId: "a", certId: "c", scope: "s", fetchFn, now: () => now });
    assertEquals((fetchFn as any).calls(), 2);
  });

  it("throws on non-2xx", async () => {
    __resetTokenCacheForTests();
    const fetchFn = mockFetch(new Response("bad", { status: 401 }));
    await assertRejects(() => getOAuthToken({
      appId: "a", certId: "c", scope: "s", fetchFn, now: () => 0,
    }));
  });
});
