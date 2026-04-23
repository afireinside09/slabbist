import { describe, it, expect } from "vitest";
import { normalizeIdentityKey } from "@/graded/identity.js";

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
