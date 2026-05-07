// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fetchCard, searchCards, _resetPauseForTests } from "../ppt/cards.ts";

function startServer(handler: (req: Request) => Response | Promise<Response>): { url: string; close: () => Promise<void> } {
  const ac = new AbortController();
  const server = Deno.serve({ port: 0, signal: ac.signal }, handler);
  const url = `http://localhost:${(server.addr as Deno.NetAddr).port}`;
  return { url, async close() { ac.abort(); try { await server.finished; } catch {} } };
}

const fullLadder = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/ppt/full-ladder.json", import.meta.url)),
);

Deno.test("fetchCard: by tcgPlayerId, returns first card from response", async () => {
  let receivedQuery: URLSearchParams | null = null;
  const srv = startServer((req) => {
    const u = new URL(req.url);
    receivedQuery = u.searchParams;
    return new Response(JSON.stringify([fullLadder]), { status: 200, headers: { "content-type": "application/json" } });
  });
  try {
    _resetPauseForTests();
    const r = await fetchCard({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { tcgPlayerId: "243172" });
    assertEquals(r.status, 200);
    assert(r.card?.tcgPlayerId === "243172");
    assertEquals(receivedQuery?.get("tcgPlayerId"), "243172");
    assertEquals(receivedQuery?.get("includeEbay"), "true");
    assertEquals(receivedQuery?.get("includeHistory"), "true");
    assertEquals(receivedQuery?.get("days"), "180");
    assertEquals(receivedQuery?.get("maxDataPoints"), "30");
  } finally {
    await srv.close();
  }
});

Deno.test("fetchCard: by search, sends search + limit=1", async () => {
  let receivedQuery: URLSearchParams | null = null;
  const srv = startServer((req) => {
    receivedQuery = new URL(req.url).searchParams;
    return new Response(JSON.stringify([fullLadder]), { status: 200, headers: { "content-type": "application/json" } });
  });
  try {
    _resetPauseForTests();
    const r = await fetchCard({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { search: "Charizard Base Set" });
    assertEquals(r.status, 200);
    assertEquals(receivedQuery?.get("search"), "Charizard Base Set");
    assertEquals(receivedQuery?.get("limit"), "1");
  } finally {
    await srv.close();
  }
});

Deno.test("fetchCard: empty array → status 200, card = null", async () => {
  const srv = startServer(() => new Response(JSON.stringify([]), { status: 200 }));
  try {
    _resetPauseForTests();
    const r = await fetchCard({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { search: "nope" });
    assertEquals(r.status, 200);
    assertEquals(r.card, null);
  } finally {
    await srv.close();
  }
});

Deno.test("fetchCard: response wrapper { data: [card] } also supported", async () => {
  const srv = startServer(() => new Response(JSON.stringify({ data: [fullLadder] }), { status: 200 }));
  try {
    _resetPauseForTests();
    const r = await fetchCard({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { tcgPlayerId: "243172" });
    assertEquals(r.status, 200);
    assert(r.card?.tcgPlayerId === "243172");
  } finally {
    await srv.close();
  }
});

Deno.test("fetchCard: 5xx propagates, card = null", async () => {
  const srv = startServer(() => new Response("down", { status: 503 }));
  try {
    _resetPauseForTests();
    const r = await fetchCard({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { tcgPlayerId: "243172" });
    assertEquals(r.status, 503);
    assertEquals(r.card, null);
  } finally {
    await srv.close();
  }
});

Deno.test("searchCards: bare-array shape, default limit=10, no ebay/history", async () => {
  let receivedQuery: URLSearchParams | null = null;
  const srv = startServer((req) => {
    receivedQuery = new URL(req.url).searchParams;
    return new Response(JSON.stringify([fullLadder, fullLadder]), { status: 200, headers: { "content-type": "application/json" } });
  });
  try {
    _resetPauseForTests();
    const r = await searchCards({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { search: "Charizard" });
    assertEquals(r.status, 200);
    assertEquals(r.cards.length, 2);
    assertEquals(receivedQuery?.get("search"), "Charizard");
    assertEquals(receivedQuery?.get("limit"), "10");
    // The cheap-search variant must NOT request ebay or history.
    assertEquals(receivedQuery?.get("includeEbay"), null);
    assertEquals(receivedQuery?.get("includeHistory"), null);
  } finally {
    await srv.close();
  }
});

Deno.test("searchCards: response wrapper { data: [...] } also supported", async () => {
  const srv = startServer(() => new Response(JSON.stringify({ data: [fullLadder] }), { status: 200 }));
  try {
    _resetPauseForTests();
    const r = await searchCards({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { search: "Charizard" });
    assertEquals(r.status, 200);
    assertEquals(r.cards.length, 1);
    assert(r.cards[0]?.tcgPlayerId === "243172");
  } finally {
    await srv.close();
  }
});

Deno.test("searchCards: set + search combo passes both params", async () => {
  let receivedQuery: URLSearchParams | null = null;
  const srv = startServer((req) => {
    receivedQuery = new URL(req.url).searchParams;
    return new Response(JSON.stringify([fullLadder]), { status: 200 });
  });
  try {
    _resetPauseForTests();
    await searchCards({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { search: "Charizard", set: "151" });
    assertEquals(receivedQuery?.get("search"), "Charizard");
    assertEquals(receivedQuery?.get("set"), "151");
    assertEquals(receivedQuery?.get("limit"), "10");
  } finally {
    await srv.close();
  }
});

Deno.test("searchCards: explicit limit override", async () => {
  let receivedQuery: URLSearchParams | null = null;
  const srv = startServer((req) => {
    receivedQuery = new URL(req.url).searchParams;
    return new Response(JSON.stringify([]), { status: 200 });
  });
  try {
    _resetPauseForTests();
    await searchCards({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { search: "Charizard", limit: 20 });
    assertEquals(receivedQuery?.get("limit"), "20");
  } finally {
    await srv.close();
  }
});

Deno.test("searchCards: empty array → status 200, cards = []", async () => {
  const srv = startServer(() => new Response(JSON.stringify([]), { status: 200 }));
  try {
    _resetPauseForTests();
    const r = await searchCards({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { search: "nope" });
    assertEquals(r.status, 200);
    assertEquals(r.cards, []);
  } finally {
    await srv.close();
  }
});

Deno.test("searchCards: no args → 400 status, empty cards", async () => {
  const srv = startServer(() => new Response(JSON.stringify([]), { status: 200 }));
  try {
    _resetPauseForTests();
    const r = await searchCards({ token: "t", baseUrl: srv.url, now: () => Date.now() }, {});
    assertEquals(r.status, 400);
    assertEquals(r.cards, []);
  } finally {
    await srv.close();
  }
});

Deno.test("searchCards: 5xx propagates, cards = []", async () => {
  const srv = startServer(() => new Response("down", { status: 503 }));
  try {
    _resetPauseForTests();
    const r = await searchCards({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { search: "Charizard" });
    assertEquals(r.status, 503);
    assertEquals(r.cards, []);
  } finally {
    await srv.close();
  }
});
