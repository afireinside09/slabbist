import { describe, it, expect, beforeEach } from "vitest";
import { loadConfig } from "@/shared/config.js";

describe("loadConfig", () => {
  beforeEach(() => {
    for (const k of Object.keys(process.env)) {
      if (k.startsWith("SUPABASE_") || k.startsWith("PSA_") || k.startsWith("EBAY_")) delete process.env[k];
    }
  });

  it("loads required Supabase vars and marks missing optionals as undefined", () => {
    process.env.SUPABASE_URL = "https://x.supabase.co";
    process.env.SUPABASE_SERVICE_ROLE_KEY = "svc";
    const cfg = loadConfig();
    expect(cfg.supabase.url).toBe("https://x.supabase.co");
    expect(cfg.supabase.serviceRoleKey).toBe("svc");
    expect(cfg.grading.psaApiKey).toBeUndefined();
    expect(cfg.grading.psaPopSpecIds).toEqual([]);
    expect(cfg.ebay.marketplaceInsightsApproved).toBe(false);
  });

  it("throws when SUPABASE_URL is missing", () => {
    process.env.SUPABASE_SERVICE_ROLE_KEY = "svc";
    expect(() => loadConfig()).toThrow(/SUPABASE_URL/);
  });

  it("parses PSA_POP_SPEC_IDS into an array of integers", () => {
    process.env.SUPABASE_URL = "https://x.supabase.co";
    process.env.SUPABASE_SERVICE_ROLE_KEY = "svc";
    process.env.PSA_POP_SPEC_IDS = "123456, 789012 , 999";
    const cfg = loadConfig();
    expect(cfg.grading.psaPopSpecIds).toEqual([123456, 789012, 999]);
  });

  it("returns empty psaPopSpecIds when env var is absent", () => {
    process.env.SUPABASE_URL = "https://x.supabase.co";
    process.env.SUPABASE_SERVICE_ROLE_KEY = "svc";
    delete process.env.PSA_POP_SPEC_IDS;
    const cfg = loadConfig();
    expect(cfg.grading.psaPopSpecIds).toEqual([]);
  });
});
