// @ts-nocheck — runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports.
// supabase/functions/cert-lookup/psa.ts
//
// Thin client over PSA's Public API. The bearer token is the PSA-issued
// access token (long-lived), read from the `PSA_API_TOKEN` Supabase secret.
// Docs: https://www.psacard.com/publicapi

import type { PSACertResponse } from "./types.ts";

export class PSAError extends Error {
  constructor(public code: "not_found" | "unauthorized" | "rate_limited" | "upstream", public status?: number) {
    super(`psa.${code}${status ? `.${status}` : ""}`);
  }
}

export interface FetchCertOptions {
  certNumber: string;
  token: string;
  /** Override for tests. Defaults to PSA's production base URL. */
  baseURL?: string;
  /** Override for tests. Defaults to global fetch. */
  fetchImpl?: typeof fetch;
}

/** Calls PSA `cert/GetByCertNumber/{certNumber}` and returns the parsed JSON.
 *
 * Maps HTTP statuses to typed errors so the handler can return clean codes:
 * - 404 → `not_found`
 * - 401/403 → `unauthorized` (bad/expired token; should page an operator)
 * - 429 → `rate_limited`
 * - other non-2xx → `upstream`
 */
export async function fetchPSACert(opts: FetchCertOptions): Promise<PSACertResponse> {
  const base = opts.baseURL ?? "https://api.psacard.com/publicapi";
  const url = `${base}/cert/GetByCertNumber/${encodeURIComponent(opts.certNumber)}`;
  const fetchFn = opts.fetchImpl ?? fetch;

  const res = await fetchFn(url, {
    method: "GET",
    headers: {
      // PSA's docs use lowercase `bearer`; either works at runtime.
      Authorization: `bearer ${opts.token}`,
      Accept: "application/json",
    },
  });

  if (res.status === 404) throw new PSAError("not_found", 404);
  if (res.status === 401 || res.status === 403) throw new PSAError("unauthorized", res.status);
  if (res.status === 429) throw new PSAError("rate_limited", 429);
  if (!res.ok) throw new PSAError("upstream", res.status);

  const body = await res.json() as PSACertResponse;
  // PSA returns `{ "PSACert": null }` for unknown certs in some cases instead of 404.
  if (!body || !body.PSACert || !body.PSACert.CertNumber) {
    throw new PSAError("not_found", 404);
  }
  return body;
}
