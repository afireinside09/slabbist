import { Command } from "commander";
import { loadConfig } from "@/shared/config.js";
import { createLogger } from "@/shared/logger.js";
import { getSupabase } from "@/shared/db/supabase.js";
import { ingestPokemonAllCategories } from "@/raw/ingest.js";
import { runPopReportIngest } from "@/graded/ingest/pop-reports.js";
import { runEbaySoldIngest } from "@/graded/ingest/ebay-sold.js";
import { runMoverListingsIngest } from "@/graded/ingest/mover-listings.js";
import { mintEbayBrowseToken } from "@/graded/sources/ebay-oauth.js";
import { runPopularSlabsSeed } from "@/graded/seeds/popular-slabs.js";

const program = new Command();
program.name("tcgcsv").description("Slabbist ingestion CLI");

const run = program.command("run");

run.command("raw")
  .argument("<source>", "raw source: tcgcsv")
  .option("-c, --concurrency <n>", "concurrent requests", "3")
  .option("-d, --delay-ms <ms>", "delay between group requests", "200")
  .action(async (source, o) => {
    const cfg = loadConfig();
    const log = createLogger({ level: cfg.runtime.logLevel });
    if (source !== "tcgcsv") { log.error("unknown raw source", { source }); process.exit(2); }
    const results = await ingestPokemonAllCategories({
      supabase: getSupabase(),
      userAgent: cfg.runtime.userAgent,
      concurrency: Number(o.concurrency),
      delayMs: Number(o.delayMs),
      log,
    });
    for (const r of results) log.info("run complete", { ...r });
    if (results.some((r) => r.status === "failed")) process.exit(1);
  });

run.command("graded")
  .argument("<job>", "job: ebay | pop")
  .option("-s, --service <svc>", "pop: which services (comma-separated or 'all')", "all")
  .option(
    "-q, --queries <list>",
    "ebay: comma-separated search queries (if omitted, queries are sourced from graded_watchlist)",
  )
  .action(async (job, o) => {
    const cfg = loadConfig();
    const log = createLogger({ level: cfg.runtime.logLevel });
    if (job === "ebay") {
      const queries = o.queries
        ? String(o.queries).split(",").map((s: string) => s.trim()).filter(Boolean)
        : [];
      const ebaySoldOpts: Parameters<typeof runEbaySoldIngest>[0] = {
        supabase: getSupabase(),
        userAgent: cfg.runtime.userAgent,
        queries,
        log,
      };
      if (cfg.ebay.marketplaceInsightsApproved && process.env.EBAY_OAUTH_TOKEN) {
        ebaySoldOpts.marketplaceInsightsToken = process.env.EBAY_OAUTH_TOKEN;
      }
      const res = await runEbaySoldIngest(ebaySoldOpts);
      log.info("ebay ingest complete", { ...res });
      if (res.status === "failed") process.exit(1);
      return;
    }
    if (job === "pop") {
      const requestedServices = o.service === "all"
        ? ["psa", "cgc", "bgs", "sgc", "tag"]
        : String(o.service).split(",").map((s) => s.trim().toLowerCase());

      const psaReady = cfg.grading.psaApiKey && cfg.grading.psaPopSpecIds.length > 0;
      if (requestedServices.includes("psa") && !psaReady) {
        log.warn(
          "PSA pop skipped: set PSA_API_KEY and PSA_POP_SPEC_IDS (comma-separated ints) to enable",
        );
      }
      // Only include PSA in the run if both the API key and at least one SpecID are configured.
      const services = requestedServices.filter(
        (s) => s !== "psa" || psaReady,
      ) as Array<"psa" | "cgc" | "bgs" | "sgc" | "tag">;

      const popOpts: Parameters<typeof runPopReportIngest>[0] = {
        supabase: getSupabase(),
        userAgent: cfg.runtime.userAgent,
        services,
      };
      if (psaReady) {
        popOpts.psa = { apiKey: cfg.grading.psaApiKey!, specIds: cfg.grading.psaPopSpecIds };
      }
      const res = await runPopReportIngest(popOpts);
      log.info("pop ingest complete", { ...res });
      if (res.status === "failed") process.exit(1);
      return;
    }
    log.error("unknown graded job", { job });
    process.exit(2);
  });

run.command("mover-listings")
  .description(
    "Refresh public.mover_ebay_listings with the most recent active eBay listings " +
    "for every distinct (product, sub-type) in public.movers. Replaces the table " +
    "wholesale; no listing history is retained.",
  )
  .option("-l, --card-limit <n>", "process at most N cards (smoke-test friendly)", "0")
  .option("-p, --per-card <n>", "keep at most N matching listings per card", "24")
  .option("-c, --concurrency <n>", "card-level parallelism", "4")
  .action(async (o) => {
    const cfg = loadConfig();
    const log = createLogger({ level: cfg.runtime.logLevel });
    const ingestOpts: Parameters<typeof runMoverListingsIngest>[0] = {
      supabase: getSupabase(),
      userAgent: cfg.runtime.userAgent,
      cardLimit: Number(o.cardLimit),
      perCardLimit: Number(o.perCard),
      concurrency: Number(o.concurrency),
      log,
    };
    // Token resolution order:
    //   1. EBAY_OAUTH_TOKEN — pre-minted, passed through verbatim.
    //      Useful when running against tokens minted out-of-band
    //      (e.g. CI secrets) or against tokens with broader scopes.
    //   2. EBAY_APP_ID + EBAY_CERT_ID — mint a Browse-API token via
    //      the client-credentials grant. Lasts ~2h, plenty for a
    //      single run.
    //   3. Neither — fall back to HTML scrape inside the ingest.
    if (process.env.EBAY_OAUTH_TOKEN) {
      ingestOpts.ebayToken = process.env.EBAY_OAUTH_TOKEN;
      log.info("ebay token source", { source: "EBAY_OAUTH_TOKEN" });
    } else if (cfg.ebay.appId && cfg.ebay.certId) {
      try {
        const minted = await mintEbayBrowseToken({
          appId: cfg.ebay.appId,
          certId: cfg.ebay.certId,
          userAgent: cfg.runtime.userAgent,
        });
        ingestOpts.ebayToken = minted.accessToken;
        log.info("ebay token source", {
          source: "minted",
          expiresAt: minted.expiresAt.toISOString(),
        });
      } catch (e) {
        log.warn("ebay token mint failed; falling back to HTML scrape", {
          error: String((e as Error).message ?? e),
        });
      }
    } else {
      log.info("ebay token source", { source: "none (HTML scrape fallback)" });
    }
    const res = await runMoverListingsIngest(ingestOpts);
    log.info("mover-listings done", { ...res });
    if (res.status === "failed") process.exit(1);
  });

const seed = program.command("seed").description("Seed / bootstrap commands");

seed.command("popular-slabs")
  .description("Seed graded_card_identities + graded_watchlist from the bundled top-200 JSON")
  .action(async () => {
    const cfg = loadConfig();
    const log = createLogger({ level: cfg.runtime.logLevel });
    const res = await runPopularSlabsSeed(getSupabase(), undefined, log);
    log.info("popular-slabs seed complete", { ...res });
  });

program.parseAsync(process.argv);
