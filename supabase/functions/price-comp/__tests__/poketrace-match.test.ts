// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { resolvePoketraceCardId } from "../poketrace/match.ts";

type IdentityRow = {
  id: string;
  ppt_tcgplayer_id: string | null;
  poketrace_card_id: string | null;
  poketrace_card_id_resolved_at: string | null;
};

function fakeSupabase(identity: IdentityRow, calls: { updates: number }) {
  return {
    from(_t: string) {
      return {
        update(patch: Record<string, unknown>) {
          calls.updates += 1;
          identity.poketrace_card_id = (patch.poketrace_card_id as string | null) ?? null;
          identity.poketrace_card_id_resolved_at = (patch.poketrace_card_id_resolved_at as string | null) ?? null;
          return { eq: (_c: string, _v: string) => ({ error: null }) };
        },
      };
    },
  } as unknown;
}

Deno.test("resolvePoketraceCardId: returns cached UUID without an HTTP call", async () => {
  const identity: IdentityRow = {
    id: "id1",
    ppt_tcgplayer_id: "243172",
    poketrace_card_id: "11111111-1111-1111-1111-111111111111",
    poketrace_card_id_resolved_at: new Date().toISOString(),
  };
  const calls = { updates: 0 };
  let httpCalls = 0;
  const result = await resolvePoketraceCardId(
    {
      supabase: fakeSupabase(identity, calls),
      client: { apiKey: "k", baseUrl: "https://api.poketrace.com/v1" },
      now: () => Date.now(),
    },
    identity,
    {
      fetchJsonImpl: () => { httpCalls += 1; return Promise.resolve({ status: 200, body: null, dailyRemaining: null }); },
    },
  );
  assertEquals(result, "11111111-1111-1111-1111-111111111111");
  assertEquals(httpCalls, 0);
  assertEquals(calls.updates, 0);
});

Deno.test("resolvePoketraceCardId: empty-string sentinel within 7d returns null", async () => {
  const identity: IdentityRow = {
    id: "id2",
    ppt_tcgplayer_id: "243172",
    poketrace_card_id: "",
    poketrace_card_id_resolved_at: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
  };
  const calls = { updates: 0 };
  let httpCalls = 0;
  const result = await resolvePoketraceCardId(
    {
      supabase: fakeSupabase(identity, calls),
      client: { apiKey: "k", baseUrl: "https://api.poketrace.com/v1" },
      now: () => Date.now(),
    },
    identity,
    { fetchJsonImpl: () => { httpCalls += 1; return Promise.resolve({ status: 200, body: null, dailyRemaining: null }); } },
  );
  assertEquals(result, null);
  assertEquals(httpCalls, 0);
});

Deno.test("resolvePoketraceCardId: uncached → cross-walk → persists UUID and returns it", async () => {
  const identity: IdentityRow = {
    id: "id3",
    ppt_tcgplayer_id: "243172",
    poketrace_card_id: null,
    poketrace_card_id_resolved_at: null,
  };
  const calls = { updates: 0 };
  let observedPath = "";
  const result = await resolvePoketraceCardId(
    {
      supabase: fakeSupabase(identity, calls),
      client: { apiKey: "k", baseUrl: "https://api.poketrace.com/v1" },
      now: () => Date.now(),
    },
    identity,
    {
      fetchJsonImpl: (_opts, path) => {
        observedPath = path;
        return Promise.resolve({
          status: 200,
          dailyRemaining: 499,
          body: { data: [{ id: "22222222-2222-2222-2222-222222222222", name: "Charizard", cardNumber: "4" }] },
        });
      },
    },
  );
  assertEquals(result, "22222222-2222-2222-2222-222222222222");
  assert(observedPath.startsWith("/cards?"));
  assert(observedPath.includes("tcgplayer_ids=243172"));
  assertEquals(calls.updates, 1);
  assertEquals(identity.poketrace_card_id, "22222222-2222-2222-2222-222222222222");
});

Deno.test("resolvePoketraceCardId: cross-walk returns 0 results → persists '' sentinel", async () => {
  const identity: IdentityRow = {
    id: "id4",
    ppt_tcgplayer_id: "999999",
    poketrace_card_id: null,
    poketrace_card_id_resolved_at: null,
  };
  const calls = { updates: 0 };
  const result = await resolvePoketraceCardId(
    {
      supabase: fakeSupabase(identity, calls),
      client: { apiKey: "k", baseUrl: "https://api.poketrace.com/v1" },
      now: () => Date.now(),
    },
    identity,
    {
      fetchJsonImpl: () => Promise.resolve({ status: 200, dailyRemaining: 499, body: { data: [] } }),
    },
  );
  assertEquals(result, null);
  assertEquals(calls.updates, 1);
  assertEquals(identity.poketrace_card_id, "");
});

Deno.test("resolvePoketraceCardId: identity has no ppt_tcgplayer_id → returns null without HTTP call", async () => {
  const identity: IdentityRow = {
    id: "id5",
    ppt_tcgplayer_id: null,
    poketrace_card_id: null,
    poketrace_card_id_resolved_at: null,
  };
  const calls = { updates: 0 };
  let httpCalls = 0;
  const result = await resolvePoketraceCardId(
    {
      supabase: fakeSupabase(identity, calls),
      client: { apiKey: "k", baseUrl: "https://api.poketrace.com/v1" },
      now: () => Date.now(),
    },
    identity,
    { fetchJsonImpl: () => { httpCalls += 1; return Promise.resolve({ status: 200, body: null, dailyRemaining: null }); } },
  );
  assertEquals(result, null);
  assertEquals(httpCalls, 0);
});
