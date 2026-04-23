// @ts-nocheck — this file runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports; runtime is correct.
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function handleOptions(): Response {
  return new Response('ok', { headers: corsHeaders });
}
