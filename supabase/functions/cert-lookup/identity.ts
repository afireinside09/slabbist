// @ts-nocheck — runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports.
// supabase/functions/cert-lookup/identity.ts
//
// Map a PSA cert response to a `graded_card_identities` row + upsert it
// alongside the corresponding `graded_cards` row.
//
// PSA does not give us a clean "set name" field for Pokémon — `Brand` is the
// closest signal but is usually one of "POKEMON GAME" / "POKEMON JAPANESE"
// / "POKEMON". For v1 we use Brand as the set_name surrogate; this keeps
// (set_name, card_number, card_name, variant) deterministic for a given cert
// so the same scan always resolves to the same identity. A later pass can
// enrich set resolution from PSA SpecID → set lookups.

import type { CertLookupCard, GradingService, PSACertResponse } from "./types.ts";

export interface MappedIdentity {
  identity: {
    game: "pokemon";
    language: "en" | "jp";
    set_name: string;
    set_code: string | null;
    year: number | null;
    card_number: string | null;
    card_name: string;
    variant: string | null;
  };
  card: CertLookupCard;
  grade: string;
}

export class MappingError extends Error {
  constructor(public code: "not_pokemon" | "missing_subject" | "missing_grade") {
    super(`mapping.${code}`);
  }
}

function normalize(s: string | undefined | null): string {
  return (s ?? "").trim();
}

/** Pure mapping — no DB calls. Tested in identity.test.ts. */
export function mapPSAResponse(psa: PSACertResponse): MappedIdentity {
  const cert = psa.PSACert;
  const brand = normalize(cert.Brand).toUpperCase();
  const category = normalize(cert.Category).toUpperCase();

  // Pokémon-only gate. Some PSA certs come back with category "TCG CARDS" and
  // brand starting with POKEMON; reject everything else so we don't pollute
  // the graded table with non-Pokémon identities.
  const isPokemon = brand.includes("POKEMON") || brand.includes("POKÉMON") ||
    (category === "TCG CARDS" && brand.includes("POK"));
  if (!isPokemon) throw new MappingError("not_pokemon");

  const subject = normalize(cert.Subject);
  if (!subject) throw new MappingError("missing_subject");

  const grade = normalize(cert.CardGrade);
  if (!grade) throw new MappingError("missing_grade");

  const language: "en" | "jp" = brand.includes("JAPAN") ? "jp" : "en";
  const yearRaw = normalize(cert.Year);
  const year = yearRaw && /^\d{4}$/.test(yearRaw) ? Number(yearRaw) : null;
  const cardNumber = normalize(cert.CardNumber) || null;
  const variantRaw = normalize(cert.Variety);
  const variant = variantRaw ? variantRaw : null;

  // Use PSA's Brand as the set_name surrogate. Stable per cert; sufficient for
  // identity uniqueness keyed on (game, language, set_name, card_number,
  // variant, card_name).
  const setName = brand || "POKEMON";

  return {
    identity: {
      game: "pokemon",
      language,
      set_name: setName,
      set_code: null,
      year,
      card_number: cardNumber,
      card_name: subject,
      variant,
    },
    card: {
      set_name: setName,
      card_number: cardNumber,
      card_name: subject,
      variant,
      year,
      language,
    },
    grade,
  };
}

interface UpsertArgs {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  mapped: MappedIdentity;
  grader: GradingService;
  certNumber: string;
  rawPSA: PSACertResponse;
}

export interface UpsertResult {
  identityId: string;
  gradedCardId: string;
  cacheHit: boolean;
}

/** Upserts identity and graded_card rows. Returns ids and whether the cert
 * was already on file (cacheHit means the graded_cards row existed before
 * this call — useful for telemetry but not for response correctness). */
export async function upsertIdentityAndCard(args: UpsertArgs): Promise<UpsertResult> {
  const { supabase, mapped, grader, certNumber, rawPSA } = args;

  // 1. Look up an existing graded_cards row first — if the cert was scanned
  //    before, return its identity directly without touching identities.
  const { data: existingCard } = await supabase
    .from("graded_cards")
    .select("id, identity_id")
    .eq("grading_service", grader)
    .eq("cert_number", certNumber)
    .maybeSingle();

  if (existingCard) {
    return {
      identityId: existingCard.identity_id as string,
      gradedCardId: existingCard.id as string,
      cacheHit: true,
    };
  }

  // 2. Find-or-create the identity by the unique tuple. Postgres's `on
  //    conflict` doesn't play well with our partial unique index that uses
  //    `coalesce(variant, '')`, so we do a pre-select on normalized values
  //    and fall back to an insert.
  const { data: existingIdentity } = await supabase
    .from("graded_card_identities")
    .select("id")
    .eq("game", mapped.identity.game)
    .eq("language", mapped.identity.language)
    .eq("set_name", mapped.identity.set_name)
    .eq("card_name", mapped.identity.card_name)
    .filter("card_number", mapped.identity.card_number === null ? "is" : "eq", mapped.identity.card_number ?? "null")
    .filter("variant", mapped.identity.variant === null ? "is" : "eq", mapped.identity.variant ?? "null")
    .limit(1)
    .maybeSingle();

  let identityId: string;
  if (existingIdentity) {
    identityId = existingIdentity.id as string;
  } else {
    const { data: inserted, error: insertErr } = await supabase
      .from("graded_card_identities")
      .insert(mapped.identity)
      .select("id")
      .single();
    if (insertErr || !inserted) throw new Error(`identity_insert_failed: ${insertErr?.message ?? "unknown"}`);
    identityId = inserted.id as string;
  }

  // 3. Insert the graded_cards row. Unique index on (grading_service,
  //    cert_number) means a concurrent insert will conflict; we re-read on
  //    that path.
  const { data: cardInsert, error: cardErr } = await supabase
    .from("graded_cards")
    .insert({
      identity_id: identityId,
      grading_service: grader,
      cert_number: certNumber,
      grade: mapped.grade,
      source_payload: rawPSA as unknown as Record<string, unknown>,
    })
    .select("id")
    .single();

  if (cardInsert) {
    return { identityId, gradedCardId: cardInsert.id as string, cacheHit: false };
  }

  // Conflict — re-read.
  if (cardErr) {
    const { data: raced } = await supabase
      .from("graded_cards")
      .select("id, identity_id")
      .eq("grading_service", grader)
      .eq("cert_number", certNumber)
      .maybeSingle();
    if (raced) {
      return {
        identityId: raced.identity_id as string,
        gradedCardId: raced.id as string,
        cacheHit: true,
      };
    }
    throw new Error(`graded_card_insert_failed: ${cardErr.message}`);
  }

  throw new Error("graded_card_insert_failed: unknown");
}
