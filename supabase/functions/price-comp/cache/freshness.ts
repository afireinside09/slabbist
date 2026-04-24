// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.
// supabase/functions/price-comp/cache/freshness.ts
import type { CacheState } from "../types.ts";

export interface FreshnessOpts {
  updatedAtMs: number | null;
  nowMs: number;
  ttlSeconds: number;
}

export function evaluateFreshness(opts: FreshnessOpts): CacheState {
  if (opts.updatedAtMs === null) return "miss";
  const ageMs = opts.nowMs - opts.updatedAtMs;
  if (ageMs <= opts.ttlSeconds * 1000) return "hit";
  return "stale";
}
