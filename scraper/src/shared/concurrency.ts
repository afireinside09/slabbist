import pLimit from "p-limit";

export interface MapConcurrentOptions {
  delayMs?: number;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function mapConcurrent<T, R>(
  items: readonly T[],
  concurrency: number,
  fn: (item: T, index: number) => Promise<R>,
  opts: MapConcurrentOptions = {},
): Promise<R[]> {
  const limit = pLimit(concurrency);
  const delay = opts.delayMs ?? 0;
  let nextStart = Date.now();
  return Promise.all(items.map((item, i) => limit(async () => {
    if (delay > 0) {
      const wait = nextStart - Date.now();
      if (wait > 0) await sleep(wait);
      nextStart = Math.max(Date.now(), nextStart) + delay;
    }
    return fn(item, i);
  })));
}
