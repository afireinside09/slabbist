import { describe, it, expect } from "vitest";
import { acceptListing, cardNumberPatterns } from "@/graded/match/listing-matcher.js";

describe("acceptListing — graded gate", () => {
  it("rejects an ungraded listing", () => {
    const result = acceptListing("Charizard 4/102 Base Set Holo NM/M", {
      productName: "Charizard - 4/102",
      cardNumber: "4/102",
      subTypeName: "Holofoil",
    });
    expect(result.ok).toBe(false);
  });

  it("accepts a PSA 10 with the right card number and Holo cue", () => {
    const result = acceptListing("PSA 10 Charizard 4/102 Base Set Holo Unlimited", {
      productName: "Charizard - 4/102",
      cardNumber: "4/102",
      subTypeName: "Holofoil",
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.gradingService).toBe("PSA");
      expect(result.grade).toBe("10");
    }
  });

  it("accepts BGS 9.5 with normalized half-grade", () => {
    const result = acceptListing("Pokemon Base Set Charizard #4/102 BGS 9.5 Gem Mint Holo", {
      productName: "Charizard - 4/102",
      cardNumber: "4/102",
      subTypeName: "Holofoil",
    });
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.grade).toBe("9.5");
  });
});

describe("acceptListing — blocklist", () => {
  it("rejects lots", () => {
    const result = acceptListing("Lot of 10 PSA 10 Pokemon Base Set 4/102", {
      productName: "Charizard - 4/102",
      cardNumber: "4/102",
      subTypeName: "Holofoil",
    });
    expect(result.ok).toBe(false);
  });

  it("rejects proxies / customs / replicas", () => {
    const result = acceptListing("Custom Proxy Charizard 4/102 PSA 10 (Replica)", {
      productName: "Charizard - 4/102",
      cardNumber: "4/102",
      subTypeName: "Holofoil",
    });
    expect(result.ok).toBe(false);
  });

  it("rejects multi-pack quantity advertising (x10, 10x)", () => {
    const result = acceptListing("PSA 10 Charizard 4/102 x10 Holo Bulk", {
      productName: "Charizard - 4/102",
      cardNumber: "4/102",
      subTypeName: "Holofoil",
    });
    expect(result.ok).toBe(false);
  });
});

describe("acceptListing — card number identity", () => {
  it("rejects when the card number doesn't appear in the title", () => {
    const result = acceptListing("PSA 10 Pokemon Charizard Base Set Holo Unlimited", {
      productName: "Charizard - 4/102",
      cardNumber: "4/102",
      subTypeName: "Holofoil",
    });
    expect(result.ok).toBe(false);
  });

  it("accepts zero-padded card numbers in the title", () => {
    const result = acceptListing("PSA 10 Charizard 008/102 Holo Base Set", {
      productName: "Charizard - 8/102",
      cardNumber: "8/102",
      subTypeName: "Holofoil",
    });
    expect(result.ok).toBe(true);
  });

  it("accepts card numbers with spaces around slash", () => {
    const result = acceptListing("PSA 10 Charizard 4 / 102 Holo", {
      productName: "Charizard - 4/102",
      cardNumber: "4/102",
      subTypeName: "Holofoil",
    });
    expect(result.ok).toBe(true);
  });

  it("rejects bare numerator that could collide across sets", () => {
    // The card number is 4/102 but the title only says "#4" with no
    // denominator — could be ANY set's #4 card. Reject.
    const result = acceptListing("PSA 10 Charizard #4 Holo Card", {
      productName: "Charizard - 4/102",
      cardNumber: "4/102",
      subTypeName: "Holofoil",
    });
    expect(result.ok).toBe(false);
  });
});

describe("acceptListing — variant compatibility", () => {
  it("rejects a Holofoil-advertised title for a Normal card", () => {
    const result = acceptListing("PSA 10 Charizard 4/102 HOLO Base Set", {
      productName: "Charizard - 4/102",
      cardNumber: "4/102",
      subTypeName: "Normal",
    });
    expect(result.ok).toBe(false);
  });

  it("rejects a Reverse Holofoil title for a Holofoil card", () => {
    const result = acceptListing(
      "PSA 10 Pikachu 58/102 Reverse Holo Base Set",
      {
        productName: "Pikachu - 58/102",
        cardNumber: "58/102",
        subTypeName: "Holofoil",
      },
    );
    expect(result.ok).toBe(false);
  });

  it("accepts a 1st Edition Holofoil match", () => {
    const result = acceptListing(
      "PSA 10 Charizard 4/102 1st Edition Holo Base Set",
      {
        productName: "Charizard - 4/102",
        cardNumber: "4/102",
        subTypeName: "1st Edition Holofoil",
      },
    );
    expect(result.ok).toBe(true);
  });

  it("rejects a 1st Edition title for a non-1st Edition Holofoil card", () => {
    const result = acceptListing(
      "PSA 10 Charizard 4/102 1st Edition Holo Base Set",
      {
        productName: "Charizard - 4/102",
        cardNumber: "4/102",
        subTypeName: "Holofoil",
      },
    );
    expect(result.ok).toBe(false);
  });
});

describe("cardNumberPatterns", () => {
  it("matches both stripped and zero-padded forms for slash numbers", () => {
    const pats = cardNumberPatterns("008/102");
    expect(pats.some((p) => p.test("PSA 10 Charizard 008/102"))).toBe(true);
    expect(pats.some((p) => p.test("PSA 10 Charizard 8/102"))).toBe(true);
    expect(pats.some((p) => p.test("PSA 10 Charizard 8 / 102"))).toBe(true);
  });

  it("requires exact match for non-slash card numbers", () => {
    const pats = cardNumberPatterns("TG14");
    expect(pats.some((p) => p.test("PSA 10 Foo TG14 Lost Origin"))).toBe(true);
    expect(pats.some((p) => p.test("PSA 10 Foo TG"))).toBe(false);
  });
});
