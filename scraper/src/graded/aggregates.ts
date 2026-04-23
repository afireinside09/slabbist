export interface SaleRow {
  sold_price: number;
  sold_at: string;
}

export interface MarketAggregate {
  lowPrice: number | null;
  medianPrice: number | null;
  highPrice: number | null;
  lastSalePrice: number | null;
  lastSaleAt: string | null;
  sampleCount30d: number;
  sampleCount90d: number;
}

function median(xs: readonly number[]): number | null {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b);
  const mid = s.length >> 1;
  return s.length % 2 ? s[mid]! : (s[mid - 1]! + s[mid]!) / 2;
}

export function computeMarketAggregate(sales: readonly SaleRow[]): MarketAggregate {
  const now = Date.now();
  const d30 = now - 30 * 86_400_000;
  const d90 = now - 90 * 86_400_000;

  let last: SaleRow | null = null;
  const in30: number[] = [];
  let sample90 = 0;

  for (const s of sales) {
    const t = Date.parse(s.sold_at);
    if (t >= d30) in30.push(s.sold_price);
    if (t >= d90) sample90 += 1;
    if (!last || t > Date.parse(last.sold_at)) last = s;
  }

  return {
    lowPrice: in30.length ? Math.min(...in30) : null,
    medianPrice: median(in30),
    highPrice: in30.length ? Math.max(...in30) : null,
    lastSalePrice: last?.sold_price ?? null,
    lastSaleAt: last?.sold_at ?? null,
    sampleCount30d: in30.length,
    sampleCount90d: sample90,
  };
}
