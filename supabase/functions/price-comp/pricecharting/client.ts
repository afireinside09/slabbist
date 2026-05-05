// supabase/functions/price-comp/pricecharting/client.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.

const BASE_URL = "https://www.pricecharting.com";

// Module-scope rate-limit pause. After a 429, all live fetches in this
// isolate sleep until `pausedUntil` passes. Outside callers handle the
// `paused` flag in the response.
let pausedUntil = 0;

export interface ClientOptions {
  token: string;
  // For tests / mock servers; defaults to the production base URL.
  baseUrl?: string;
  // For tests; injects a controllable clock.
  now?: () => number;
}

export interface ClientResponse {
  status: number;
  body: unknown;
  // Distinct from a real 5xx — set when the in-isolate pause is active.
  paused?: boolean;
}

function urlFor(opts: ClientOptions, path: string, params: Record<string, string>): string {
  const url = new URL(path, opts.baseUrl ?? BASE_URL);
  url.searchParams.set("t", opts.token);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  return url.toString();
}

async function doFetch(url: string): Promise<ClientResponse> {
  const res = await fetch(url, {
    method: "GET",
    headers: { accept: "application/json" },
  });
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  return { status: res.status, body };
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
  const first = await doFetch(url);

  if (first.status === 429) {
    // 60s in-isolate pause, then surface 429 to the caller.
    pausedUntil = now + 60_000;
    return first;
  }

  // 401 once may be a transient token-refresh artifact; retry exactly once.
  if (first.status === 401) {
    const second = await doFetch(url);
    return second;
  }

  return first;
}
