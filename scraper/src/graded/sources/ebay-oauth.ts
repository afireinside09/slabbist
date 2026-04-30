// src/graded/sources/ebay-oauth.ts
// Mint an OAuth2 application token for the eBay Browse API using a
// client-credentials grant. Browse calls only need the public scope,
// so this avoids the user-consent flow entirely. Tokens last ~2h —
// plenty for a single ingest run; we mint once and pass the result
// through to the active-listings fetcher.
import { z } from "zod";
import { httpJson } from "@/shared/http/fetch.js";

const TOKEN_URL = "https://api.ebay.com/identity/v1/oauth2/token";
const PUBLIC_SCOPE = "https://api.ebay.com/oauth/api_scope";

const TokenResponse = z.object({
  access_token: z.string(),
  token_type: z.string(),
  expires_in: z.number(),
});

export interface MintTokenOpts {
  appId: string;
  certId: string;
  userAgent: string;
  /// Override scope for callers that need more than public Browse
  /// (e.g. Marketplace Insights). Defaults to the public scope.
  scope?: string;
}

export interface MintedToken {
  accessToken: string;
  expiresAt: Date;
}

export async function mintEbayBrowseToken(
  opts: MintTokenOpts,
): Promise<MintedToken> {
  // Basic auth header is base64(<appId>:<certId>). Bun and Node
  // both accept Buffer; fall back to btoa for portability.
  const credentials = `${opts.appId}:${opts.certId}`;
  const basic = typeof Buffer !== "undefined"
    ? Buffer.from(credentials, "utf8").toString("base64")
    : btoa(credentials);

  const body = new URLSearchParams({
    grant_type: "client_credentials",
    scope: opts.scope ?? PUBLIC_SCOPE,
  }).toString();

  const json = await httpJson(TOKEN_URL, {
    userAgent: opts.userAgent,
    method: "POST",
    headers: {
      Authorization: `Basic ${basic}`,
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body,
  });
  const parsed = TokenResponse.parse(json);
  // Subtract 60s of slack so we don't try to use a token whose
  // remaining lifetime is borderline.
  const expiresAt = new Date(Date.now() + (parsed.expires_in - 60) * 1000);
  return { accessToken: parsed.access_token, expiresAt };
}
