// @ts-nocheck — runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports.
// supabase/functions/cert-lookup/index.ts
//
// Resolves a `(grader, cert_number)` pair to a `graded_card_identities` row
// (with a backing `graded_cards` row) by calling the PSA Public API.
//
// Today: PSA only. Other graders return 415 `UNSUPPORTED_GRADER` — extending
// to CGC/BGS/SGC/TAG is a per-grader source addition.
//
// Secrets read from env:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (Supabase platform-provided)
//   PSA_API_TOKEN (operator-set: `supabase secrets set PSA_API_TOKEN=...`)

import { createClient } from "@supabase/supabase-js";
import type { CertLookupRequest, CertLookupResponse, GradingService } from "./types.ts";
import { fetchPSACert, PSAError } from "./psa.ts";
import { mapPSAResponse, MappingError, upsertIdentityAndCard } from "./identity.ts";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function env(name: string): string {
  const v = Deno.env.get(name);
  if (v === undefined || v === "") throw new Error(`missing env: ${name}`);
  return v;
}

function isValidGrader(g: unknown): g is GradingService {
  return g === "PSA" || g === "BGS" || g === "CGC" || g === "SGC" || g === "TAG";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "access-control-allow-origin": "*",
        "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
        "access-control-allow-methods": "POST, OPTIONS",
      },
    });
  }
  if (req.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });

  let body: CertLookupRequest;
  try {
    body = await req.json() as CertLookupRequest;
  } catch {
    return json(400, { code: "INVALID_JSON" });
  }
  if (!body || !isValidGrader(body.grader) || typeof body.cert_number !== "string" || !body.cert_number.trim()) {
    return json(400, { code: "MISSING_FIELDS" });
  }
  if (body.grader !== "PSA") {
    return json(415, { code: "UNSUPPORTED_GRADER", grader: body.grader });
  }

  const certNumber = body.cert_number.trim();

  let supabase;
  let psaToken: string;
  try {
    supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false },
    });
    psaToken = env("PSA_API_TOKEN");
  } catch (e) {
    console.error("cert-lookup.config.failed", { message: (e as Error).message });
    return json(500, { code: "SERVER_MISCONFIGURED" });
  }

  // Fast path: we've already resolved this cert before. Skip the PSA call.
  const { data: existingCard } = await supabase
    .from("graded_cards")
    .select("id, identity_id, grade")
    .eq("grading_service", body.grader)
    .eq("cert_number", certNumber)
    .maybeSingle();

  if (existingCard) {
    const { data: identity } = await supabase
      .from("graded_card_identities")
      .select("set_name, card_number, card_name, variant, year, language")
      .eq("id", existingCard.identity_id)
      .single();
    if (identity) {
      const response: CertLookupResponse = {
        identity_id: existingCard.identity_id as string,
        graded_card_id: existingCard.id as string,
        grading_service: body.grader,
        grade: existingCard.grade as string,
        card: {
          set_name: identity.set_name as string,
          card_number: (identity.card_number as string | null) ?? null,
          card_name: identity.card_name as string,
          variant: (identity.variant as string | null) ?? null,
          year: (identity.year as number | null) ?? null,
          language: ((identity.language as string) === "jp" ? "jp" : "en") as "en" | "jp",
        },
        cache_hit: true,
      };
      return json(200, response);
    }
  }

  let psa;
  try {
    psa = await fetchPSACert({ certNumber, token: psaToken });
  } catch (e) {
    if (e instanceof PSAError) {
      if (e.code === "not_found") return json(404, { code: "CERT_NOT_FOUND" });
      if (e.code === "unauthorized") {
        console.error("cert-lookup.psa.unauthorized", { status: e.status });
        return json(502, { code: "UPSTREAM_UNAUTHORIZED" });
      }
      if (e.code === "rate_limited") return json(429, { code: "UPSTREAM_RATE_LIMITED" });
      console.error("cert-lookup.psa.upstream", { status: e.status });
      return json(502, { code: "UPSTREAM_FAILED" });
    }
    console.error("cert-lookup.psa.unexpected", { message: (e as Error).message });
    return json(502, { code: "UPSTREAM_FAILED" });
  }

  let mapped;
  try {
    mapped = mapPSAResponse(psa);
  } catch (e) {
    if (e instanceof MappingError && e.code === "not_pokemon") {
      return json(415, { code: "NOT_POKEMON" });
    }
    console.error("cert-lookup.map.failed", { message: (e as Error).message });
    return json(422, { code: "PSA_MAPPING_FAILED" });
  }

  let upsert;
  try {
    upsert = await upsertIdentityAndCard({
      supabase,
      mapped,
      grader: body.grader,
      certNumber,
      rawPSA: psa,
    });
  } catch (e) {
    console.error("cert-lookup.upsert.failed", { message: (e as Error).message });
    return json(500, { code: "PERSIST_FAILED" });
  }

  const response: CertLookupResponse = {
    identity_id: upsert.identityId,
    graded_card_id: upsert.gradedCardId,
    grading_service: body.grader,
    grade: mapped.grade,
    card: mapped.card,
    cache_hit: upsert.cacheHit,
  };

  console.log("cert-lookup.live", {
    grader: body.grader,
    cache_hit: upsert.cacheHit,
    identity_id: upsert.identityId,
  });

  return json(200, response);
});
