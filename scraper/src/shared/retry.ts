export interface RetryOptions {
  maxAttempts: number;
  initialMs: number;
  multiplier: number;
}

export interface RetryableError extends Error {
  retryable?: boolean;
  retryAfterMs?: number;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function withRetry<T>(fn: () => Promise<T>, opts: RetryOptions): Promise<T> {
  let attempt = 0;
  let delay = opts.initialMs;
  let lastErr: unknown;
  while (attempt < opts.maxAttempts) {
    try {
      return await fn();
    } catch (e) {
      lastErr = e;
      const err = e as RetryableError;
      if (!err.retryable) throw e;
      attempt += 1;
      if (attempt >= opts.maxAttempts) break;
      const wait = err.retryAfterMs ?? delay;
      await sleep(wait);
      delay *= opts.multiplier;
    }
  }
  throw lastErr;
}
