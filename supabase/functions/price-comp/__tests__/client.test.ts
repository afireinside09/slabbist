// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { get, _resetPause } from "../ppt/client.ts";

function startServer(handler: (req: Request) => Response | Promise<Response>): { url: string; close: () => Promise<void> } {
  const ac = new AbortController();
  const server = Deno.serve({ port: 0, signal: ac.signal }, handler);
  const url = `http://localhost:${(server.addr as Deno.NetAddr).port}`;
  return { url, async close() { ac.abort(); try { await server.finished; } catch {} } };
}

Deno.test("get: sends Authorization Bearer and X-API-Version headers", async () => {
  let captured: { authorization: string | null; apiVersion: string | null } = { authorization: null, apiVersion: null };
  const srv = startServer((req) => {
    captured.authorization = req.headers.get("authorization");
    captured.apiVersion = req.headers.get("x-api-version");
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
  });
  try {
    _resetPause();
    const r = await get({ token: "abc-123", baseUrl: srv.url, now: () => Date.now() }, "/api/v2/cards", { search: "x" });
    assertEquals(r.status, 200);
    assertEquals(captured.authorization, "Bearer abc-123");
    assertEquals(captured.apiVersion, "v1");
  } finally {
    await srv.close();
  }
});

Deno.test("get: 401 triggers a single retry", async () => {
  let calls = 0;
  const srv = startServer(() => {
    calls++;
    if (calls === 1) return new Response("nope", { status: 401 });
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
  });
  try {
    _resetPause();
    const r = await get({ token: "t", baseUrl: srv.url, now: () => Date.now() }, "/api/v2/cards", { search: "x" });
    assertEquals(r.status, 200);
    assertEquals(calls, 2);
  } finally {
    await srv.close();
  }
});

Deno.test("get: 401 twice returns 401 to caller", async () => {
  const srv = startServer(() => new Response("still nope", { status: 401 }));
  try {
    _resetPause();
    const r = await get({ token: "t", baseUrl: srv.url, now: () => Date.now() }, "/api/v2/cards", { search: "x" });
    assertEquals(r.status, 401);
  } finally {
    await srv.close();
  }
});

Deno.test("get: 429 sets a 60s in-isolate pause; subsequent calls return paused 429 without hitting the network", async () => {
  let calls = 0;
  const srv = startServer(() => { calls++; return new Response("rate-limited", { status: 429 }); });
  try {
    _resetPause();
    let now = 1_000_000;
    const r1 = await get({ token: "t", baseUrl: srv.url, now: () => now }, "/api/v2/cards", { search: "x" });
    assertEquals(r1.status, 429);
    assertEquals(calls, 1);
    // Within the 60s pause, no network call.
    now += 30_000;
    const r2 = await get({ token: "t", baseUrl: srv.url, now: () => now }, "/api/v2/cards", { search: "x" });
    assertEquals(r2.status, 429);
    assert(r2.paused === true);
    assertEquals(calls, 1);
    // After the pause, fresh call.
    now += 31_000;
    const r3 = await get({ token: "t", baseUrl: srv.url, now: () => now }, "/api/v2/cards", { search: "x" });
    assertEquals(r3.status, 429);
    assertEquals(calls, 2);
  } finally {
    await srv.close();
  }
});
