// @ts-nocheck — this file runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports; runtime is correct.
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

/** Service-role client. Use for writes that bypass RLS in trusted Edge code. */
export function serviceRoleClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set');
  return createClient(url, key, { auth: { persistSession: false } });
}

/** User-scoped client built from the request's bearer token. RLS applies. */
export function userClient(req: Request): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  if (!url || !anon) throw new Error('SUPABASE_URL / SUPABASE_ANON_KEY not set');
  const auth = req.headers.get('Authorization') ?? '';
  return createClient(url, anon, {
    auth: { persistSession: false },
    global: { headers: { Authorization: auth } },
  });
}
