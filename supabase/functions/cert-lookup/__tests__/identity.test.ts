// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or relative `.ts` imports that Deno accepts.
// supabase/functions/cert-lookup/__tests__/identity.test.ts

import { assertEquals, assertThrows } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { mapPSAResponse, MappingError } from "../identity.ts";

async function loadFixture(name: string) {
  const text = await Deno.readTextFile(new URL(`../__fixtures__/${name}`, import.meta.url));
  return JSON.parse(text);
}

describe("mapPSAResponse", () => {
  it("maps an English Pokemon cert with a variety", async () => {
    const psa = await loadFixture("psa-charizard-base-1st.json");
    const out = mapPSAResponse(psa);
    assertEquals(out.identity.game, "pokemon");
    assertEquals(out.identity.language, "en");
    assertEquals(out.identity.set_name, "POKEMON GAME");
    assertEquals(out.identity.year, 1999);
    assertEquals(out.identity.card_number, "4");
    assertEquals(out.identity.card_name, "CHARIZARD-HOLO");
    assertEquals(out.identity.variant, "1ST EDITION");
    assertEquals(out.grade, "10");
    assertEquals(out.card.language, "en");
  });

  it("flags Japanese language from the brand", async () => {
    const psa = await loadFixture("psa-pokemon-japanese.json");
    const out = mapPSAResponse(psa);
    assertEquals(out.identity.language, "jp");
    assertEquals(out.identity.set_name, "POKEMON JAPANESE");
    // Empty Variety → null variant.
    assertEquals(out.identity.variant, null);
    assertEquals(out.grade, "9");
  });

  it("rejects non-Pokemon brands with not_pokemon", async () => {
    const psa = await loadFixture("psa-non-pokemon.json");
    assertThrows(
      () => mapPSAResponse(psa),
      MappingError,
      "mapping.not_pokemon",
    );
  });

  it("rejects when Subject is missing", () => {
    assertThrows(
      () => mapPSAResponse({ PSACert: {
        CertNumber: "1", Brand: "POKEMON GAME", Category: "TCG CARDS",
        Subject: "", CardGrade: "9",
      } } as never),
      MappingError,
      "mapping.missing_subject",
    );
  });

  it("rejects when CardGrade is missing", () => {
    assertThrows(
      () => mapPSAResponse({ PSACert: {
        CertNumber: "1", Brand: "POKEMON GAME", Category: "TCG CARDS",
        Subject: "CHARIZARD", CardGrade: "",
      } } as never),
      MappingError,
      "mapping.missing_grade",
    );
  });

  it("treats non-4-digit Year as null", () => {
    const out = mapPSAResponse({ PSACert: {
      CertNumber: "1", Brand: "POKEMON GAME", Category: "TCG CARDS",
      Subject: "CHARIZARD", CardGrade: "10", Year: "n/a",
    } } as never);
    assertEquals(out.identity.year, null);
  });
});
