// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports.
// supabase/functions/cert-lookup/__tests__/psa.test.ts

import { assertEquals, assertRejects } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { fetchPSACert, PSAError } from "../psa.ts";

function fakeFetch(status: number, body: unknown): typeof fetch {
  return ((_url: string, _init?: RequestInit) =>
    Promise.resolve(
      new Response(typeof body === "string" ? body : JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
      }),
    )) as typeof fetch;
}

describe("fetchPSACert", () => {
  it("returns the parsed body on 200", async () => {
    const psa = await Deno.readTextFile(
      new URL("../__fixtures__/psa-charizard-base-1st.json", import.meta.url),
    );
    const body = await fetchPSACert({
      certNumber: "12345678",
      token: "tkn",
      fetchImpl: fakeFetch(200, JSON.parse(psa)),
    });
    assertEquals(body.PSACert.CertNumber, "12345678");
    assertEquals(body.PSACert.Subject, "CHARIZARD-HOLO");
  });

  it("maps 404 to not_found", async () => {
    await assertRejects(
      () => fetchPSACert({
        certNumber: "0", token: "t",
        fetchImpl: fakeFetch(404, { error: "not found" }),
      }),
      PSAError,
      "psa.not_found",
    );
  });

  it("maps 401 to unauthorized", async () => {
    await assertRejects(
      () => fetchPSACert({
        certNumber: "0", token: "t",
        fetchImpl: fakeFetch(401, { error: "bad" }),
      }),
      PSAError,
      "psa.unauthorized",
    );
  });

  it("maps 429 to rate_limited", async () => {
    await assertRejects(
      () => fetchPSACert({
        certNumber: "0", token: "t",
        fetchImpl: fakeFetch(429, { error: "slow" }),
      }),
      PSAError,
      "psa.rate_limited",
    );
  });

  it("treats null PSACert as not_found", async () => {
    await assertRejects(
      () => fetchPSACert({
        certNumber: "0", token: "t",
        fetchImpl: fakeFetch(200, { PSACert: null }),
      }),
      PSAError,
      "psa.not_found",
    );
  });

  it("encodes the cert number in the URL", async () => {
    let capturedUrl = "";
    const fetchImpl: typeof fetch = ((url: string) => {
      capturedUrl = url;
      return Promise.resolve(new Response(JSON.stringify({
        PSACert: { CertNumber: "abc 123", Brand: "POKEMON GAME", Category: "TCG CARDS",
          Subject: "X", CardGrade: "10" },
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }) as typeof fetch;
    await fetchPSACert({ certNumber: "abc 123", token: "t", fetchImpl });
    assertEquals(capturedUrl.endsWith("/cert/GetByCertNumber/abc%20123"), true);
  });
});
