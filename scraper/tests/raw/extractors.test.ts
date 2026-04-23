import { describe, it, expect } from "vitest";
import { extractPokemonFields } from "@/raw/extractors.js";

describe("extractPokemonFields", () => {
  it("extracts all five fields when present", () => {
    const out = extractPokemonFields([
      { name: "Number", displayName: "Number", value: "4/102" },
      { name: "Rarity", displayName: "Rarity", value: "Holo Rare" },
      { name: "CardType", displayName: "Card Type", value: "Fire" },
      { name: "HP", displayName: "HP", value: "120" },
      { name: "Stage", displayName: "Stage", value: "Stage 2" },
    ]);
    expect(out).toEqual({
      cardNumber: "4/102", rarity: "Holo Rare", cardType: "Fire", hp: "120", stage: "Stage 2",
    });
  });

  it("returns null for missing fields", () => {
    const out = extractPokemonFields([
      { name: "Number", displayName: "Number", value: "1" },
    ]);
    expect(out).toEqual({ cardNumber: "1", rarity: null, cardType: null, hp: null, stage: null });
  });

  it("handles alternate displayName spellings", () => {
    const out = extractPokemonFields([
      { name: "CardNumber", displayName: "Card Number", value: "12/108" },
      { name: "CardType", displayName: "Type", value: "Grass" },
    ]);
    expect(out.cardNumber).toBe("12/108");
    expect(out.cardType).toBe("Grass");
  });

  it("returns all nulls for empty input", () => {
    expect(extractPokemonFields([])).toEqual({
      cardNumber: null, rarity: null, cardType: null, hp: null, stage: null,
    });
  });
});
