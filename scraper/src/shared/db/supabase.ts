import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { PostgrestError } from "@supabase/supabase-js";
import { loadConfig } from "@/shared/config.js";

let cached: SupabaseClient | null = null;

export function getSupabase(): SupabaseClient {
  if (cached) return cached;
  const cfg = loadConfig();
  cached = createClient(cfg.supabase.url, cfg.supabase.secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { "x-slabbist-service": "tcgcsv-ingest" } },
  });
  return cached;
}

export function resetSupabaseForTesting(): void { cached = null; }

/**
 * Awaits a supabase-js write call and throws if the result contains an error.
 * Accepts both Promise<T> and direct T (PromiseLike<T>) so it works with the
 * pg-mem fake-supabase helper which returns resolved values directly.
 */
export async function throwIfError<T extends { error: PostgrestError | null }>(p: PromiseLike<T> | T): Promise<T> {
  const res = await p;
  if (res.error) throw new Error(`supabase: ${res.error.message}`);
  return res;
}
