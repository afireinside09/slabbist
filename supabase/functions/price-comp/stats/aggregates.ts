// supabase/functions/price-comp/stats/aggregates.ts

function assertNonEmpty(xs: number[]): void {
  if (xs.length === 0) throw new Error("aggregate: empty input");
}

export function mean(xs: number[]): number {
  assertNonEmpty(xs);
  const sum = xs.reduce((a, b) => a + b, 0);
  const q = sum / xs.length;
  const floor = Math.floor(q);
  const frac = q - floor;
  if (frac < 0.5) return floor;
  if (frac > 0.5) return floor + 1;
  return floor % 2 === 0 ? floor : floor + 1;
}

export function median(xs: number[]): number {
  assertNonEmpty(xs);
  const sorted = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[mid]!;
  return Math.round((sorted[mid - 1]! + sorted[mid]!) / 2);
}

export function low(xs: number[]): number {
  assertNonEmpty(xs);
  return xs.reduce((a, b) => (a < b ? a : b));
}

export function high(xs: number[]): number {
  assertNonEmpty(xs);
  return xs.reduce((a, b) => (a > b ? a : b));
}
