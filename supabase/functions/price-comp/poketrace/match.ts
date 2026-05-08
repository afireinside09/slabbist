// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
// supabase/functions/price-comp/poketrace/match.ts
//
// Resolve a graded_card_identity to a Poketrace card UUID using the
// previously-persisted ppt_tcgplayer_id. Cache the UUID on the identity
// so subsequent scans skip the cross-walk.
//
//   * Hit (non-empty UUID cached): return it.
//   * Negative-hit ('' sentinel within 7d): return null without retrying.
//   * Miss: GET /cards?tcgplayer_ids=<id>. Persist the first result's UUID
//     (or '' when 0 results).

import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchJson, type FetchResult, type PoketraceClientOptions } from "./client.ts";
import {
  persistIdentityPoketraceCardId,
  poketraceNegativeCacheStillFresh,
} from "../persistence/identity-product-id.ts";

interface IdentityForMatch {
  id: string;
  ppt_tcgplayer_id: string | null;
  poketrace_card_id: string | null;
  poketrace_card_id_resolved_at: string | null;
}

export interface ResolveDeps {
  supabase: SupabaseClient;
  client: PoketraceClientOptions;
  now: () => number;
}

export interface ResolveOverrides {
  fetchJsonImpl?: <T>(opts: PoketraceClientOptions, path: string) => Promise<FetchResult<T>>;
}

interface CardSearchResponse {
  data: Array<{ id: string }>;
}

/**
 * Returns the resolved Poketrace card UUID, or null if no match exists.
 * Persists the result on `graded_card_identities`.
 */
export async function resolvePoketraceCardId(
  deps: ResolveDeps,
  identity: IdentityForMatch,
  overrides: ResolveOverrides = {},
): Promise<string | null> {
  // 1. Positive cache hit
  if (identity.poketrace_card_id && identity.poketrace_card_id !== "") {
    return identity.poketrace_card_id;
  }

  // 2. Negative cache (recently looked up, no match) — skip retry for 7d
  if (
    identity.poketrace_card_id === "" &&
    poketraceNegativeCacheStillFresh(identity.poketrace_card_id_resolved_at, deps.now())
  ) {
    return null;
  }

  // 3. No tcgPlayerId on identity → cannot cross-walk
  if (!identity.ppt_tcgplayer_id) {
    return null;
  }

  // 4. Live cross-walk
  const fetchImpl = overrides.fetchJsonImpl ?? fetchJson;
  const path = `/cards?tcgplayer_ids=${encodeURIComponent(identity.ppt_tcgplayer_id)}&limit=20&has_graded=true`;
  const res = await fetchImpl<CardSearchResponse>(deps.client, path);

  if (res.status !== 200 || !res.body?.data) {
    // Don't poison the cache on transient failures — return null and try
    // again next scan. Only the empty-array case persists the sentinel.
    return null;
  }

  if (res.body.data.length === 0) {
    await persistIdentityPoketraceCardId(deps.supabase, identity.id, "");
    return null;
  }

  const cardId = res.body.data[0].id;
  await persistIdentityPoketraceCardId(deps.supabase, identity.id, cardId);
  return cardId;
}
