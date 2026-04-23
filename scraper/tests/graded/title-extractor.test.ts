import { describe, it, expect } from "vitest";
import { extractIdentityFromEbayTitle } from "@/graded/title-extractor.js";

describe("extractIdentityFromEbayTitle", () => {
  it("parses a typical Base Set Charizard PSA 10 listing", () => {
    const id = extractIdentityFromEbayTitle(
      "1999 Pokemon Base Set Charizard Holo #4 PSA 10 GEM MINT", "PSA", "10",
    );
    expect(id.year).toBe(1999);
    expect(id.cardNumber).toBe("4");
    expect(id.language).toBe("en");
    expect(id.cardName).toBe("base set charizard holo");
    expect(id.setName).toBe("");
    expect(id.variant).toBeNull();
  });

  it("parses Pikachu Promo CGC 10 without a card number", () => {
    const id = extractIdentityFromEbayTitle(
      "Pikachu Illustrator Promo CGC 10 PRISTINE", "CGC", "10",
    );
    expect(id.cardNumber).toBeNull();
    expect(id.cardName).toContain("pikachu illustrator promo");
    expect(id.year).toBeNull();
  });

  it("parses a Japanese listing and sets language=jp", () => {
    const id = extractIdentityFromEbayTitle(
      "1996 Pokemon Japanese Base Set Charizard Holo #6 PSA 10", "PSA", "10",
    );
    expect(id.language).toBe("jp");
    expect(id.cardNumber).toBe("6");
    expect(id.cardName).not.toContain("japanese");
    expect(id.cardName).not.toContain("pokemon");
  });

  it("parses a fraction-form card number like 174/172", () => {
    const id = extractIdentityFromEbayTitle(
      "2022 Pokemon Sword & Shield Brilliant Stars Charizard VSTAR 174/172 PSA 10", "PSA", "10",
    );
    expect(id.cardNumber).toBe("174/172");
    expect(id.year).toBe(2022);
  });

  it("keeps variant-like tokens (1st Edition, Shadowless) in cardName for now", () => {
    const id = extractIdentityFromEbayTitle(
      "1999 Pokemon Base Set Shadowless 1st Edition Charizard Holo #4 PSA 10", "PSA", "10",
    );
    expect(id.cardName).toContain("1st edition");
    expect(id.cardName).toContain("shadowless");
  });

  it("collapses two listings of the same card into matching identities", () => {
    const a = extractIdentityFromEbayTitle("1999 Pokemon Base Set Charizard Holo #4 PSA 10 GEM MINT", "PSA", "10");
    const b = extractIdentityFromEbayTitle("1999 Pokemon Base Set Charizard Holo #4 PSA 10 cert 12345678", "PSA", "10");
    expect(a.cardName).toBe(b.cardName);
    expect(a.cardNumber).toBe(b.cardNumber);
    expect(a.year).toBe(b.year);
    expect(a.language).toBe(b.language);
  });

  it("does NOT confuse years inside card numbers", () => {
    const id = extractIdentityFromEbayTitle("2023 Pokemon #2024 PSA 10", "PSA", "10");
    expect(id.year).toBe(2023);
    expect(id.cardNumber).toBe("2024");
  });
});
