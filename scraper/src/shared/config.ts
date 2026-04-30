import { config as dotenvConfig } from "dotenv";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

// Load `.env.local` first, then `.env` as a fallback. dotenv won't
// override values that are already set in process.env, so the order
// here gives `.env.local` precedence over `.env`. Both files are
// optional — missing files are silently ignored.
//
// Both paths are anchored to the scraper package root (two levels
// up from this file), not `process.cwd()`, so the loader behaves
// the same whether the CLI is run via `pnpm cli`, `tsx src/cli.ts`,
// or from a parent monorepo directory.
const PACKAGE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
dotenvConfig({ path: resolve(PACKAGE_ROOT, ".env.local") });
dotenvConfig({ path: resolve(PACKAGE_ROOT, ".env") });

export interface AppConfig {
  supabase: { url: string; secretKey: string };
  grading: {
    psaApiKey?: string | undefined;
    psaPopSpecIds: number[];
    beckettOpgKey?: string | undefined;
    tagApiKey?: string | undefined;
  };
  ebay: { appId?: string | undefined; certId?: string | undefined; devId?: string | undefined; marketplaceInsightsApproved: boolean };
  runtime: { logLevel: "debug" | "info" | "warn" | "error"; userAgent: string };
}

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

export function loadConfig(): AppConfig {
  const rawSpecIds = process.env.PSA_POP_SPEC_IDS || "";
  const psaPopSpecIds = rawSpecIds
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .map(Number)
    .filter((n) => Number.isInteger(n) && n > 0);

  return {
    supabase: {
      url: required("SUPABASE_URL"),
      secretKey: required("SUPABASE_SECRET_KEY"),
    },
    grading: {
      psaApiKey: process.env.PSA_API_KEY || undefined,
      psaPopSpecIds,
      beckettOpgKey: process.env.BECKETT_OPG_KEY || undefined,
      tagApiKey: process.env.TAG_API_KEY || undefined,
    },
    ebay: {
      appId: process.env.EBAY_APP_ID || undefined,
      certId: process.env.EBAY_CERT_ID || undefined,
      devId: process.env.EBAY_DEV_ID || undefined,
      marketplaceInsightsApproved: process.env.EBAY_MARKETPLACE_INSIGHTS_APPROVED === "true",
    },
    runtime: {
      logLevel: (process.env.LOG_LEVEL as AppConfig["runtime"]["logLevel"]) || "info",
      userAgent: process.env.HTTP_USER_AGENT || "slabbist-tcgcsv/0.1",
    },
  };
}
