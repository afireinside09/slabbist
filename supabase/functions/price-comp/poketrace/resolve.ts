// supabase/functions/price-comp/poketrace/resolve.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// PPT-free identity resolver. Resolves a graded_card_identity to a
// Poketrace card UUID and caches it on graded_card_identities.poketrace_card_id.
//   Tier A: alias → tcg_products → tcgplayer product_id → /cards?tcgplayer_ids=
//           Also tries tcgplayer_product_id already stored on the identity.
//   Tier B: native /cards?search=<name>&card_number=<n> with scoring.
//   '' sentinel = looked, no match (re-attempt after 7 days).

import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchJson, type FetchResult, type PoketraceClientOptions } from "./client.ts";
import { scoreSearchCard, type SearchCardLite } from "./parse.ts";
import { aliasForPsaSet } from "../lib/psa-aliases.ts";
import { findTcgProductByGroupAndCard, type TcgProductMatch } from "../lib/tcg-products.ts";
import {
  persistIdentityPoketraceCardId,
  poketraceNegativeCacheStillFresh,
} from "../persistence/identity-product-id.ts";

export interface IdentityForResolve {
  id: string;
  card_name: string;
  card_number: string | null;
  set_name: string;
  tcgplayer_product_id: string | null;
  poketrace_card_id: string | null;
  poketrace_card_id_resolved_at: string | null;
}

export interface ResolveDeps {
  supabase: SupabaseClient;
  client: PoketraceClientOptions;
  now: () => number;
  // Test seams (default to the real impls).
  findTcgProduct?: (
    sb: unknown,
    a: { groupId: number; cardNumber: string | null; cardName: string },
  ) => Promise<TcgProductMatch | null>;
  fetchJsonImpl?: <T>(opts: PoketraceClientOptions, path: string) => Promise<FetchResult<T>>;
}

interface CardSearch { data: SearchCardLite[] }

export async function resolvePoketraceCard(
  deps: ResolveDeps,
  identity: IdentityForResolve,
): Promise<string | null> {
  const fetchImpl = deps.fetchJsonImpl ?? fetchJson;
  const findProduct = deps.findTcgProduct ?? findTcgProductByGroupAndCard;

  // 1. Positive cache hit.
  if (identity.poketrace_card_id && identity.poketrace_card_id !== "") {
    return identity.poketrace_card_id;
  }

  // 2. Negative cache fresh → skip.
  if (
    identity.poketrace_card_id === "" &&
    poketraceNegativeCacheStillFresh(identity.poketrace_card_id_resolved_at, deps.now())
  ) {
    return null;
  }

  // 3. Tier A — alias → tcg_products → tcgplayer_ids cross-walk.
  //    Collect product ids: from the identity first, then from tcg_products.
  const productIds: string[] = [];
  if (identity.tcgplayer_product_id) productIds.push(identity.tcgplayer_product_id);
  const alias = aliasForPsaSet(identity.set_name);
  if (alias) {
    const groupIds = [alias.groupId, alias.altGroupId].filter(
      (g): g is number => typeof g === "number",
    );
    for (const gid of groupIds) {
      const product = await findProduct(deps.supabase, {
        groupId: gid,
        cardNumber: identity.card_number,
        cardName: identity.card_name,
      });
      if (product) {
        productIds.push(String(product.productId));
        break;
      }
    }
  }
  for (const pid of productIds) {
    const res = await fetchImpl<CardSearch>(
      deps.client,
      `/cards?tcgplayer_ids=${encodeURIComponent(pid)}&limit=20`,
    );
    if (res.status === 200 && res.body?.data?.length) {
      const uuid = res.body.data[0].id;
      await persistIdentityPoketraceCardId(deps.supabase, identity.id, uuid);
      return uuid;
    }
  }

  // 4. Tier B — native search by name (+ card number), scored.
  const searchPaths = [
    `/cards?search=${encodeURIComponent(identity.card_name)}${
      identity.card_number
        ? `&card_number=${encodeURIComponent(identity.card_number)}`
        : ""
    }&limit=20`,
    `/cards?search=${encodeURIComponent(identity.card_name)}&limit=20`,
  ];
  for (const path of searchPaths) {
    const res = await fetchImpl<CardSearch>(deps.client, path);
    if (res.status !== 200 || !res.body?.data?.length) continue;
    let best: { card: SearchCardLite; score: number } | null = null;
    for (const card of res.body.data) {
      const sc = scoreSearchCard(card, identity);
      if (sc.accept && (!best || sc.score > best.score)) best = { card, score: sc.score };
    }
    if (best) {
      await persistIdentityPoketraceCardId(deps.supabase, identity.id, best.card.id);
      return best.card.id;
    }
  }

  // 5. Total miss → negative sentinel.
  await persistIdentityPoketraceCardId(deps.supabase, identity.id, "");
  return null;
}
