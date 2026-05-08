// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fetchJson } from "../poketrace/client.ts";

Deno.test("fetchJson: sends X-API-Key header and returns parsed body", async () => {
  let observedHeaders: Headers | null = null;
  const stubFetch: typeof fetch = (input, init) => {
    observedHeaders = new Headers(init?.headers ?? {});
    return Promise.resolve(new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "content-type": "application/json", "x-ratelimit-daily-remaining": "499" },
    }));
  };
  const result = await fetchJson(
    { apiKey: "k", baseUrl: "https://api.poketrace.com/v1", fetchImpl: stubFetch },
    "/health",
  );
  assertEquals(result.status, 200);
  assertEquals(result.body, { ok: true });
  assertEquals(result.dailyRemaining, 499);
  assert(observedHeaders);
  assertEquals(observedHeaders!.get("x-api-key"), "k");
});

Deno.test("fetchJson: retries once on 502", async () => {
  let calls = 0;
  const stubFetch: typeof fetch = () => {
    calls += 1;
    if (calls === 1) return Promise.resolve(new Response("nope", { status: 502 }));
    return Promise.resolve(new Response(JSON.stringify({ ok: true }), {
      status: 200, headers: { "content-type": "application/json" },
    }));
  };
  const result = await fetchJson(
    { apiKey: "k", baseUrl: "https://api.poketrace.com/v1", fetchImpl: stubFetch },
    "/cards/abc",
  );
  assertEquals(calls, 2);
  assertEquals(result.status, 200);
});

Deno.test("fetchJson: returns the 4xx response without retrying", async () => {
  let calls = 0;
  const stubFetch: typeof fetch = () => {
    calls += 1;
    return Promise.resolve(new Response('{"error":"not found"}', {
      status: 404, headers: { "content-type": "application/json" },
    }));
  };
  const result = await fetchJson(
    { apiKey: "k", baseUrl: "https://api.poketrace.com/v1", fetchImpl: stubFetch },
    "/cards/missing",
  );
  assertEquals(calls, 1);
  assertEquals(result.status, 404);
});

Deno.test("fetchJson: timeout aborts the request", async () => {
  const stubFetch: typeof fetch = (_input, init) =>
    new Promise((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
      // never resolves
    });
  let threw = false;
  try {
    await fetchJson(
      { apiKey: "k", baseUrl: "https://api.poketrace.com/v1", fetchImpl: stubFetch, timeoutMs: 10 },
      "/cards/slow",
    );
  } catch (e) {
    threw = e instanceof Error && e.message.includes("timeout");
  }
  assert(threw, "expected fetchJson to throw on timeout");
});
