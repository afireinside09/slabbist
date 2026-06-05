// scraper/src/graded/sources/poketrace.ts
// Minimal Poketrace client for the grade-comp backfill. Mirrors the
// edge function's poketrace/client.ts auth + parsing, scoped to the two
// calls the backfill needs: tcgplayer-id search and PSA 10 detail.

export interface PoketraceClient {
  apiKey: string;
  baseUrl: string;            // e.g. https://api.poketrace.com/v1
  fetchImpl?: typeof fetch;
  timeoutMs?: number;         // default 8000
}

export interface SearchResult { cardId: string | null | undefined; dailyRemaining: number | null }
// cardId: string = match; null = zero results (write sentinel); undefined = transient (do NOT write).

export interface Psa10Result {
  psa10PriceCents: number | null;
  ptSaleCount: number | null;
  dailyRemaining: number | null;
}

async function get(c: PoketraceClient, path: string): Promise<{ status: number; body: any; daily: number | null }> {
  const fetchImpl = c.fetchImpl ?? fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), c.timeoutMs ?? 8000);
  let resp: Response;
  try {
    resp = await fetchImpl(`${c.baseUrl}${path}`, {
      method: "GET",
      headers: { "x-api-key": c.apiKey, accept: "application/json" },
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
  const dh = resp.headers.get("x-ratelimit-daily-remaining");
  // Treat an empty/whitespace header as absent — Number("") is 0, which would
  // otherwise read as "zero budget remaining" and trip a spurious budget stop.
  const daily = dh !== null && dh.trim() !== "" && Number.isFinite(Number(dh)) ? Number(dh) : null;
  let body: any = null;
  if (resp.headers.get("content-type")?.includes("application/json")) {
    try { body = await resp.json(); } catch { body = null; }
  }
  return { status: resp.status, body, daily };
}

export async function searchCardId(c: PoketraceClient, tcgplayerId: number): Promise<SearchResult> {
  const { status, body, daily } = await get(c, `/cards?tcgplayer_ids=${encodeURIComponent(String(tcgplayerId))}&limit=20`);
  if (status !== 200 || !body?.data) return { cardId: undefined, dailyRemaining: daily };
  if (body.data.length === 0) return { cardId: null, dailyRemaining: daily };
  return { cardId: String(body.data[0].id), dailyRemaining: daily };
}

function dollarsToCents(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? Math.round(v * 100) : null;
}

export async function fetchPsa10(c: PoketraceClient, cardId: string): Promise<Psa10Result> {
  const { status, body, daily } = await get(c, `/cards/${encodeURIComponent(cardId)}`);
  const empty: Psa10Result = { psa10PriceCents: null, ptSaleCount: null, dailyRemaining: daily };
  if (status !== 200 || !body?.data?.prices) return empty;
  const prices: Record<string, Record<string, any>> = body.data.prices;
  for (const src of Object.keys(prices)) {
    const tp = prices[src]?.PSA_10;
    if (tp) {
      return {
        psa10PriceCents: dollarsToCents(tp.avg),
        ptSaleCount: typeof tp.saleCount === "number" && Number.isFinite(tp.saleCount) ? tp.saleCount : null,
        dailyRemaining: daily,
      };
    }
  }
  return empty;
}
