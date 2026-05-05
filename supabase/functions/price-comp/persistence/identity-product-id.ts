// supabase/functions/price-comp/persistence/identity-product-id.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { SupabaseClient } from "@supabase/supabase-js";

export async function persistIdentityProductId(
  supabase: SupabaseClient,
  identityId: string,
  productId: string,
  productUrl: string,
): Promise<void> {
  const { error } = await supabase
    .from("graded_card_identities")
    .update({
      pricecharting_product_id: productId,
      pricecharting_url: productUrl,
    })
    .eq("id", identityId);
  if (error) throw new Error(`graded_card_identities update: ${error.message}`);
}

// Used to clear a stale id when the cached product is deleted upstream
// (PriceCharting 404 on /api/product?id=…). Next scan re-runs search.
export async function clearIdentityProductId(
  supabase: SupabaseClient,
  identityId: string,
): Promise<void> {
  const { error } = await supabase
    .from("graded_card_identities")
    .update({ pricecharting_product_id: null, pricecharting_url: null })
    .eq("id", identityId);
  if (error) throw new Error(`graded_card_identities clear: ${error.message}`);
}
