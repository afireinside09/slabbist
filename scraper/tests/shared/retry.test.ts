import { describe, it, expect, vi } from "vitest";
import { withRetry } from "@/shared/retry.js";

describe("withRetry", () => {
  it("returns on first success", async () => {
    const fn = vi.fn().mockResolvedValue("ok");
    const out = await withRetry(fn, { maxAttempts: 3, initialMs: 1, multiplier: 2 });
    expect(out).toBe("ok");
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("retries on retryable errors and eventually succeeds", async () => {
    const fn = vi.fn()
      .mockRejectedValueOnce(Object.assign(new Error("rate-limited"), { retryable: true }))
      .mockResolvedValue("ok");
    const out = await withRetry(fn, { maxAttempts: 3, initialMs: 1, multiplier: 2 });
    expect(out).toBe("ok");
    expect(fn).toHaveBeenCalledTimes(2);
  });

  it("throws after maxAttempts", async () => {
    const err = Object.assign(new Error("persistent"), { retryable: true });
    const fn = vi.fn().mockRejectedValue(err);
    await expect(
      withRetry(fn, { maxAttempts: 3, initialMs: 1, multiplier: 2 })
    ).rejects.toThrow("persistent");
    expect(fn).toHaveBeenCalledTimes(3);
  });

  it("does not retry non-retryable errors", async () => {
    const err = new Error("client error");
    const fn = vi.fn().mockRejectedValue(err);
    await expect(
      withRetry(fn, { maxAttempts: 3, initialMs: 1, multiplier: 2 })
    ).rejects.toThrow("client error");
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("honors retryAfterMs hint from the thrown error", async () => {
    const fn = vi.fn()
      .mockRejectedValueOnce(Object.assign(new Error("429"), { retryable: true, retryAfterMs: 5 }))
      .mockResolvedValue("ok");
    const t0 = Date.now();
    await withRetry(fn, { maxAttempts: 3, initialMs: 1, multiplier: 2 });
    expect(Date.now() - t0).toBeGreaterThanOrEqual(5);
  });
});
