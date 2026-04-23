import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { psaCertLookup, psaPopReport } from "@/graded/sources/psa.js";

const F = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/psa");
const load = (n: string) => JSON.parse(readFileSync(join(F, n), "utf8"));
const mockOk = (body: unknown) => vi.fn().mockResolvedValue(
  new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } }),
);

describe("psa source", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("psaCertLookup normalizes to GradedCertRecord", async () => {
    vi.stubGlobal("fetch", mockOk(load("cert-lookup-sample.json")));
    const rec = await psaCertLookup("54829123", { apiKey: "k", userAgent: "t" });
    expect(rec.gradingService).toBe("PSA");
    expect(rec.certNumber).toBe("54829123");
    expect(rec.grade).toBe("10");
    expect(rec.identity.cardName).toBe("CHARIZARD-HOLO");
    expect(rec.identity.cardNumber).toBe("4");
    expect(rec.identity.variant).toBe("SHADOWLESS");
  });

  it("psaPopReport expands per-grade rows", async () => {
    vi.stubGlobal("fetch", mockOk(load("pop-report-sample.json")));
    const rows = await psaPopReport(123456, { apiKey: "k", userAgent: "t" });
    expect(rows).toHaveLength(3);
    expect(rows.find((r) => r.grade === "10")?.population).toBe(142);
  });
});
