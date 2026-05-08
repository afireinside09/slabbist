// supabase/functions/price-comp/poketrace/client.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// Minimal Poketrace HTTP client. Production code uses the global `fetch`
// implementation; tests inject a stub via `fetchImpl`. Authentication is
// `X-API-Key: <key>` per https://poketrace.com/docs/authentication.

export interface PoketraceClientOptions {
  apiKey: string;
  baseUrl: string;             // e.g. "https://api.poketrace.com/v1"
  fetchImpl?: typeof fetch;
  timeoutMs?: number;          // default 8000
}

export interface FetchResult<T> {
  status: number;
  body: T | null;
  dailyRemaining: number | null; // x-ratelimit-daily-remaining header
}

const DEFAULT_TIMEOUT_MS = 8000;

export async function fetchJson<T>(
  opts: PoketraceClientOptions,
  pathAndQuery: string,
): Promise<FetchResult<T>> {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const url = `${opts.baseUrl}${pathAndQuery}`;
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  async function once(): Promise<Response> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      return await fetchImpl(url, {
        method: "GET",
        headers: {
          "x-api-key": opts.apiKey,
          "accept": "application/json",
        },
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }
  }

  let resp: Response;
  try {
    resp = await once();
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") {
      throw new Error(`poketrace timeout after ${timeoutMs}ms: ${pathAndQuery}`);
    }
    throw e;
  }

  if (resp.status >= 500 && resp.status <= 599) {
    // One short retry — covers transient 5xx without amplifying outages.
    await new Promise((r) => setTimeout(r, 250));
    try { resp = await once(); }
    catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") {
        throw new Error(`poketrace timeout after ${timeoutMs}ms: ${pathAndQuery}`);
      }
      throw e;
    }
  }

  const dailyRemainingHeader = resp.headers.get("x-ratelimit-daily-remaining");
  const dailyRemaining = dailyRemainingHeader !== null && Number.isFinite(Number(dailyRemainingHeader))
    ? Number(dailyRemainingHeader)
    : null;

  let body: T | null = null;
  if (resp.headers.get("content-type")?.includes("application/json")) {
    try { body = (await resp.json()) as T; } catch { body = null; }
  }
  return { status: resp.status, body, dailyRemaining };
}
