import "dotenv/config";

export interface AppConfig {
  supabase: { url: string; serviceRoleKey: string };
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
      serviceRoleKey: required("SUPABASE_SERVICE_ROLE_KEY"),
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
