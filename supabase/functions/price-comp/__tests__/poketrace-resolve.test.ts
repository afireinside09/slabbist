// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { resolvePoketraceCard } from "../poketrace/resolve.ts";

const baseIdentity = {
  id: "id-1",
  card_name: "Charizard",
  card_number: "4",
  set_name: "Base Set",
  tcgplayer_product_id: null,
  poketrace_card_id: null,
  poketrace_card_id_resolved_at: null,
};

// A supabase stub that captures the persisted poketrace_card_id.
// onPersist(value) is called with the value written.
function fakeSupabase(onPersist?: (v: string) => void) {
  return {
    from(_t: string) {
      return {
        update(patch: Record<string, unknown>) {
          if (onPersist && "poketrace_card_id" in patch) {
            onPersist(patch.poketrace_card_id as string);
          }
          return {
            eq(_col: string, _val: unknown) {
              return { error: null };
            },
          };
        },
      };
    },
  } as unknown;
}

function fakeClient() {
  return { apiKey: "k", baseUrl: "http://x" };
}

Deno.test("positive cache hit returns cached UUID without any fetch", async () => {
  let calls = 0;
  const id = await resolvePoketraceCard(
    {
      supabase: fakeSupabase(),
      client: fakeClient(),
      now: () => 0,
      findTcgProduct: async () => { calls++; return null; },
      fetchJsonImpl: async () => { calls++; return { status: 200, body: { data: [] } }; },
    },
    { ...baseIdentity, poketrace_card_id: "cached-uuid" },
  );
  assertEquals(id, "cached-uuid");
  assertEquals(calls, 0);
});

Deno.test("Tier A: tcg_products → tcgplayer_ids cross-walk", async () => {
  const id = await resolvePoketraceCard(
    {
      supabase: fakeSupabase(),
      client: fakeClient(),
      now: () => 0,
      findTcgProduct: async () => ({ productId: 12345, cardName: "Charizard", cardNumber: "4/102" }),
      fetchJsonImpl: async (_c, path) => {
        if (path.includes("tcgplayer_ids=12345")) return { status: 200, body: { data: [{ id: "uuid-A" }] } };
        return { status: 200, body: { data: [] } };
      },
    },
    baseIdentity,
  );
  assertEquals(id, "uuid-A");
});

Deno.test("Tier B: search fallback when Tier A misses", async () => {
  const id = await resolvePoketraceCard(
    {
      supabase: fakeSupabase(),
      client: fakeClient(),
      now: () => 0,
      findTcgProduct: async () => null, // alias/tcg_products miss
      fetchJsonImpl: async (_c, path) => {
        if (path.includes("search=")) {
          return {
            status: 200,
            body: { data: [
              { id: "uuid-B", name: "Charizard", cardNumber: "4/102", set: { name: "Base Set" } },
            ] },
          };
        }
        return { status: 200, body: { data: [] } };
      },
    },
    baseIdentity,
  );
  assertEquals(id, "uuid-B");
});

Deno.test("total miss persists '' sentinel and returns null", async () => {
  let persisted: string | null = "unset";
  const id = await resolvePoketraceCard(
    {
      supabase: fakeSupabase((v) => { persisted = v; }),
      client: fakeClient(),
      now: () => 0,
      findTcgProduct: async () => null,
      fetchJsonImpl: async () => ({ status: 200, body: { data: [] } }),
    },
    baseIdentity,
  );
  assertEquals(id, null);
  assertEquals(persisted, "");
});
