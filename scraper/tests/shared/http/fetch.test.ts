import { describe, it, expect, vi, beforeEach } from "vitest";
import { httpJson } from "@/shared/http/fetch.js";

describe("httpJson", () => {
  beforeEach(() => { vi.restoreAllMocks(); });

  it("returns parsed JSON on 200", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ a: 1 }), { status: 200, headers: { "content-type": "application/json" } })
    ));
    const out = await httpJson("https://example.com/x", { userAgent: "ua/1" });
    expect(out).toEqual({ a: 1 });
  });

  it("throws retryable error on 429", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
      new Response("", { status: 429, headers: { "retry-after": "2" } })
    ));
    await expect(httpJson("https://example.com", { userAgent: "ua/1", maxAttempts: 1, initialMs: 1, multiplier: 2 }))
      .rejects.toMatchObject({ retryable: true, retryAfterMs: 2000 });
  });

  it("throws non-retryable error on 404", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("nope", { status: 404 })));
    await expect(httpJson("https://example.com", { userAgent: "ua/1", maxAttempts: 1, initialMs: 1, multiplier: 2 }))
      .rejects.toMatchObject({ retryable: false });
  });

  it("sends User-Agent header", async () => {
    const spy = vi.fn().mockResolvedValue(new Response("{}", { status: 200, headers: { "content-type": "application/json" } }));
    vi.stubGlobal("fetch", spy);
    await httpJson("https://example.com", { userAgent: "my-ua/9" });
    const req = spy.mock.calls[0]![1] as RequestInit;
    expect((req.headers as Record<string, string>)["User-Agent"]).toBe("my-ua/9");
  });
});
