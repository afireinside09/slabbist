// supabase/functions/price-comp/persistence/identity-product-id.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { SupabaseClient } from "@supabase/supabase-js";

export async function persistIdentityPPTId(
  supabase: SupabaseClient,
  identityId: string,
  tcgPlayerId: string,
  pptUrl: string,
): Promise<void> {
  const { error } = await supabase
    .from("graded_card_identities")
    .update({ ppt_tcgplayer_id: tcgPlayerId, ppt_url: pptUrl })
    .eq("id", identityId);
  if (error) throw new Error(`graded_card_identities update: ${error.message}`);
}

// Used to clear a stale id when the cached card is deleted upstream
// (PPT 404 / empty array). Next scan re-runs search.
export async function clearIdentityPPTId(
  supabase: SupabaseClient,
  identityId: string,
): Promise<void> {
  const { error } = await supabase
    .from("graded_card_identities")
    .update({ ppt_tcgplayer_id: null, ppt_url: null })
    .eq("id", identityId);
  if (error) throw new Error(`graded_card_identities clear: ${error.message}`);
}
