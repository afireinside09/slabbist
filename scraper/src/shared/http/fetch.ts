import { withRetry, type RetryableError, type RetryOptions } from "@/shared/retry.js";

export interface HttpJsonOptions extends Partial<RetryOptions> {
  userAgent: string;
  headers?: Record<string, string>;
  method?: string;
  body?: string;
}

const RETRYABLE_STATUS = new Set([408, 425, 429, 500, 502, 503, 504]);

function classify(status: number, retryAfter: string | null): RetryableError {
  const err = new Error(`HTTP ${status}`) as RetryableError;
  err.retryable = RETRYABLE_STATUS.has(status);
  if (retryAfter) {
    const n = Number(retryAfter);
    if (Number.isFinite(n)) err.retryAfterMs = n * 1000;
  }
  return err;
}

export async function httpJson<T = unknown>(url: string, opts: HttpJsonOptions): Promise<T> {
  const retry: RetryOptions = {
    maxAttempts: opts.maxAttempts ?? 3,
    initialMs: opts.initialMs ?? 2000,
    multiplier: opts.multiplier ?? 2,
  };
  return withRetry<T>(async () => {
    let res: Response;
    try {
      const fetchOpts: RequestInit = {
        method: opts.method ?? "GET",
        headers: { "User-Agent": opts.userAgent, Accept: "application/json", ...(opts.headers ?? {}) },
      };
      if (opts.body !== undefined) {
        fetchOpts.body = opts.body;
      }
      res = await fetch(url, fetchOpts);
    } catch (e) {
      const err = e as RetryableError;
      err.retryable = true;
      throw err;
    }
    if (!res.ok) throw classify(res.status, res.headers.get("retry-after"));
    return (await res.json()) as T;
  }, retry);
}

export async function httpText(url: string, opts: HttpJsonOptions): Promise<string> {
  const retry: RetryOptions = {
    maxAttempts: opts.maxAttempts ?? 3,
    initialMs: opts.initialMs ?? 2000,
    multiplier: opts.multiplier ?? 2,
  };
  return withRetry<string>(async () => {
    let res: Response;
    try {
      const fetchOpts: RequestInit = {
        method: opts.method ?? "GET",
        headers: { "User-Agent": opts.userAgent, ...(opts.headers ?? {}) },
      };
      if (opts.body !== undefined) {
        fetchOpts.body = opts.body;
      }
      res = await fetch(url, fetchOpts);
    } catch (e) {
      const err = e as RetryableError;
      err.retryable = true;
      throw err;
    }
    if (!res.ok) throw classify(res.status, res.headers.get("retry-after"));
    return await res.text();
  }, retry);
}
