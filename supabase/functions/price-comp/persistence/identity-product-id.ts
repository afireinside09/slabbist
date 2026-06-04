// supabase/functions/price-comp/persistence/identity-product-id.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// Poketrace-only identity helpers. PPT helpers (persistIdentityPPTId,
// clearIdentityPPTId) removed; tcgplayer_product_id is now the canonical
// column name (renamed from ppt_tcgplayer_id in migration 20260604120000).
import type { SupabaseClient } from "@supabase/supabase-js";

// ---- Poketrace UUID cache ---------------------------------------------------
//
// Cache the Poketrace card UUID on graded_card_identities so we don't re-do
// the tcgplayer_ids cross-walk on every scan. Empty string '' is the
// "tried, no match" sentinel — re-attempt after 7 days.

const POKETRACE_NEGATIVE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export async function persistIdentityPoketraceCardId(
  supabase: SupabaseClient,
  identityId: string,
  cardId: string, // empty string for "no match" sentinel
): Promise<void> {
  const { error } = await supabase
    .from("graded_card_identities")
    .update({
      poketrace_card_id: cardId,
      poketrace_card_id_resolved_at: new Date().toISOString(),
    })
    .eq("id", identityId);
  if (error) throw new Error(`identity poketrace_card_id update: ${error.message}`);
}

export async function clearIdentityPoketraceCardId(
  supabase: SupabaseClient,
  identityId: string,
): Promise<void> {
  const { error } = await supabase
    .from("graded_card_identities")
    .update({
      poketrace_card_id: null,
      poketrace_card_id_resolved_at: null,
    })
    .eq("id", identityId);
  if (error) throw new Error(`identity poketrace_card_id clear: ${error.message}`);
}

/**
 * True when an empty-string sentinel is fresh enough that we should NOT
 * re-attempt the cross-walk.
 */
export function poketraceNegativeCacheStillFresh(
  resolvedAtIso: string | null,
  nowMs: number,
): boolean {
  if (!resolvedAtIso) return false;
  const resolvedMs = Date.parse(resolvedAtIso);
  if (!Number.isFinite(resolvedMs)) return false;
  return nowMs - resolvedMs < POKETRACE_NEGATIVE_TTL_MS;
}
