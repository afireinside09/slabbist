import { describe, it, expect, vi, beforeEach } from "vitest";
import { mintEbayBrowseToken } from "@/graded/sources/ebay-oauth.js";

describe("mintEbayBrowseToken", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("posts client-credentials with the public scope and returns the token", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          access_token: "abc.def.ghi",
          token_type: "Application Access Token",
          expires_in: 7200,
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
    vi.stubGlobal("fetch", fetchMock);

    const out = await mintEbayBrowseToken({
      appId: "MyApp-PRD-abc",
      certId: "PRD-secret",
      userAgent: "slabbist-test",
    });

    expect(out.accessToken).toBe("abc.def.ghi");
    expect(out.expiresAt.getTime()).toBeGreaterThan(Date.now());

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0]!;
    expect(url).toBe("https://api.ebay.com/identity/v1/oauth2/token");

    const initObj = init as RequestInit;
    expect(initObj.method).toBe("POST");
    const headers = (initObj.headers ?? {}) as Record<string, string>;
    expect(headers.Authorization).toMatch(/^Basic /);
    // Decode the basic header back to verify the credentials format.
    const encoded = headers.Authorization!.replace(/^Basic /, "");
    const decoded = Buffer.from(encoded, "base64").toString("utf8");
    expect(decoded).toBe("MyApp-PRD-abc:PRD-secret");
    expect(headers["Content-Type"]).toBe("application/x-www-form-urlencoded");
    expect(initObj.body).toContain("grant_type=client_credentials");
    expect(initObj.body).toContain("scope=https%3A%2F%2Fapi.ebay.com%2Foauth%2Fapi_scope");
  });

  it("propagates a non-2xx as a thrown error after retries", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response("invalid_client", { status: 401 }),
      ),
    );
    await expect(
      mintEbayBrowseToken({
        appId: "wrong",
        certId: "wrong",
        userAgent: "slabbist-test",
      }),
    ).rejects.toThrow();
  });
});
