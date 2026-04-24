// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.
// supabase/functions/price-comp/ebay/oauth.ts

const TOKEN_URL = "https://api.ebay.com/identity/v1/oauth2/token";
const SAFETY_MS = 5 * 60 * 1000;

interface CachedToken {
  value: string;
  expiresAtMs: number;
}

let cache: CachedToken | null = null;

export function __resetTokenCacheForTests(): void {
  cache = null;
}

export interface GetOAuthTokenOpts {
  appId: string;
  certId: string;
  scope: string;
  fetchFn?: typeof fetch;
  now?: () => number;
}

export async function getOAuthToken(opts: GetOAuthTokenOpts): Promise<string> {
  const { appId, certId, scope, fetchFn = fetch, now = Date.now } = opts;
  const t = now();
  if (cache && cache.expiresAtMs - SAFETY_MS > t) return cache.value;
  const basic = btoa(`${appId}:${certId}`);
  const body = new URLSearchParams({ grant_type: "client_credentials", scope });
  const res = await fetchFn(TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${basic}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });
  if (!res.ok) throw new Error(`oauth: ${res.status} ${await res.text()}`);
  const data = await res.json() as { access_token: string; expires_in: number };
  cache = { value: data.access_token, expiresAtMs: t + data.expires_in * 1000 };
  return cache.value;
}
