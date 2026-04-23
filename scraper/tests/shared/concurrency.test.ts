import { describe, it, expect } from "vitest";
import { mapConcurrent } from "@/shared/concurrency.js";

describe("mapConcurrent", () => {
  it("preserves order and runs with bounded concurrency", async () => {
    let active = 0;
    let maxActive = 0;
    const out = await mapConcurrent([1, 2, 3, 4, 5], 2, async (n) => {
      active += 1; maxActive = Math.max(maxActive, active);
      await new Promise((r) => setTimeout(r, 5));
      active -= 1;
      return n * 2;
    });
    expect(out).toEqual([2, 4, 6, 8, 10]);
    expect(maxActive).toBeLessThanOrEqual(2);
  });

  it("applies delay between task starts when delayMs provided", async () => {
    const starts: number[] = [];
    await mapConcurrent([1, 2, 3], 1, async (_n) => { starts.push(Date.now()); }, { delayMs: 10 });
    expect(starts[1]! - starts[0]!).toBeGreaterThanOrEqual(10);
    expect(starts[2]! - starts[1]!).toBeGreaterThanOrEqual(10);
  });
});
