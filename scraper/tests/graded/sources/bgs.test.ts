import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { bgsCertLookup } from "@/graded/sources/bgs.js";

const F = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/bgs");
const html = readFileSync(join(F, "cert-lookup.html"), "utf8");
const mockOk = (body: string) => vi.fn().mockResolvedValue(new Response(body, { status: 200 }));

describe("bgs source", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("bgsCertLookup scrapes the cert table", async () => {
    vi.stubGlobal("fetch", mockOk(html));
    const rec = await bgsCertLookup("0009876543", { userAgent: "t" });
    expect(rec.gradingService).toBe("BGS");
    expect(rec.grade).toBe("9.5");
    expect(rec.identity.cardName).toBe("Charizard");
    expect(rec.identity.setName).toBe("Base Set");
    expect(rec.identity.cardNumber).toBe("4");
    expect(rec.identity.variant).toBe("Holo, Unlimited");
  });

  it("throws when the cert table is absent", async () => {
    vi.stubGlobal("fetch", mockOk("<html><body>no match</body></html>"));
    await expect(bgsCertLookup("0", { userAgent: "t" })).rejects.toThrow(/BGS cert/i);
  });
});
