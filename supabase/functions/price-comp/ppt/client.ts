// supabase/functions/price-comp/ppt/client.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.

const BASE_URL = "https://www.pokemonpricetracker.com";

let pausedUntil = 0;

export interface ClientOptions {
  token: string;
  baseUrl?: string;
  now?: () => number;
}

export interface ClientResponse {
  status: number;
  body: unknown;
  paused?: boolean;
  creditsConsumed?: number;
}

export function _resetPause(): void { pausedUntil = 0; }

function urlFor(opts: ClientOptions, path: string, params: Record<string, string>): string {
  const url = new URL(path, opts.baseUrl ?? BASE_URL);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  return url.toString();
}

async function doFetch(url: string, token: string): Promise<ClientResponse> {
  const res = await fetch(url, {
    method: "GET",
    headers: {
      authorization: `Bearer ${token}`,
      "x-api-version": "v1",
      accept: "application/json",
    },
  });
  let body: unknown = null;
  try { body = await res.json(); } catch { body = null; }
  const consumedRaw = res.headers.get("x-api-calls-consumed");
  const credits = consumedRaw ? Number(consumedRaw) : undefined;
  return { status: res.status, body, creditsConsumed: Number.isFinite(credits) ? credits : undefined };
}

export async function get(
  opts: ClientOptions,
  path: string,
  params: Record<string, string>,
): Promise<ClientResponse> {
  const now = (opts.now ?? Date.now)();
  if (now < pausedUntil) {
    return { status: 429, body: { code: "PAUSED" }, paused: true };
  }
  const url = urlFor(opts, path, params);
  const first = await doFetch(url, opts.token);
  if (first.status === 429) {
    pausedUntil = now + 60_000;
    return first;
  }
  if (first.status === 401) {
    return await doFetch(url, opts.token);
  }
  return first;
}
