import { describe, it, expect } from "vitest";
import { findOrCreateIdentity, normalizeIdentityKey } from "@/graded/identity.js";
import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js";

describe("normalizeIdentityKey", () => {
  it("strips punctuation, lowercases, collapses whitespace", () => {
    expect(normalizeIdentityKey({
      game: "pokemon", language: "en",
      setName: "Base Set (Shadowless)", cardName: "Charizard-Holo!",
      cardNumber: "4/102", variant: "1st Edition",
    })).toEqual({
      game: "pokemon", language: "en",
      setName: "base set shadowless", cardName: "charizard holo",
      cardNumber: "4/102", variant: "1st edition",
    });
  });

  it("treats missing variant as empty string for matching", () => {
    const a = normalizeIdentityKey({ game: "pokemon", language: "en", setName: "Jungle", cardName: "Snorlax", cardNumber: "11" });
    const b = normalizeIdentityKey({ game: "pokemon", language: "en", setName: "Jungle", cardName: "Snorlax", cardNumber: "11", variant: null });
    expect(a.variant).toBe("");
    expect(b.variant).toBe("");
  });

  it("preserves JP-language keys distinctly from EN", () => {
    const en = normalizeIdentityKey({ game: "pokemon", language: "en", setName: "s1", cardName: "x", cardNumber: "1" });
    const jp = normalizeIdentityKey({ game: "pokemon", language: "jp", setName: "s1", cardName: "x", cardNumber: "1" });
    expect(en.language).toBe("en");
    expect(jp.language).toBe("jp");
  });
});

describe("findOrCreateIdentity error handling", () => {
  it("throws when the DB rejects an insert (e.g. unique-index collision)", async () => {
    const dupError: PostgrestError = {
      message: 'duplicate key value violates unique constraint "graded_card_identities_unique_idx"',
      details: "", hint: "", code: "23505", name: "PostgrestError",
    } as unknown as PostgrestError;
    const stub = {
      from: (_t: string) => ({
        select: (_c: string) => ({ eq: async (_col: string, _v: unknown) => ({ data: [], error: null }) }),
        insert: async (_row: unknown) => ({ error: dupError }),
      }),
    } as unknown as SupabaseClient;

    await expect(
      findOrCreateIdentity(stub, {
        game: "pokemon", language: "en",
        setName: "Skyridge", cardName: "Crystal Charizard",
        cardNumber: "146/144", variant: null,
      }),
    ).rejects.toThrow(/duplicate key|unique constraint/);
  });

  it("throws when the initial select returns an error", async () => {
    const selectError: PostgrestError = {
      message: "boom", details: "", hint: "", code: "XX000", name: "PostgrestError",
    } as unknown as PostgrestError;
    const stub = {
      from: (_t: string) => ({
        select: (_c: string) => ({ eq: async (_col: string, _v: unknown) => ({ data: null, error: selectError }) }),
        insert: async (_row: unknown) => ({ error: null }),
      }),
    } as unknown as SupabaseClient;

    await expect(
      findOrCreateIdentity(stub, {
        game: "pokemon", language: "en",
        setName: "X", cardName: "Y", cardNumber: "1",
      }),
    ).rejects.toThrow(/boom/);
  });
});
