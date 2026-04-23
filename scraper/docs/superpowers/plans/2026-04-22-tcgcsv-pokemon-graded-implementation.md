# tcgcsv Pokémon + Graded Data Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an ingestion-only TypeScript repo that populates a monorepo-shared Supabase DB with (a) raw Pokémon catalog/pricing from tcgcsv.com and (b) graded card data from PSA/CGC/BGS/SGC/TAG + eBay sold listings, with strict decoupling between raw and graded domains.

**Architecture:** GitHub-Actions-cron-scheduled Node CLI with one workflow per job (daily tcgcsv, hourly eBay, weekly pop). Source-fetchers are pure functions that validate responses via zod; persistence happens in domain-level ingest orchestrators. Schema lives monorepo-shared at `/Users/dixoncider/slabbist/supabase/migrations/`, not in this repo.

**Tech Stack:** TypeScript (ESM, strict), Node 20+, Bun for package management, Vitest + pg-mem for testing, Commander CLI, zod payload validation, @supabase/supabase-js, p-limit concurrency.

**Spec:** `/Users/dixoncider/slabbist/tcgcsv/docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md`

---

## Phase 1 — Repo scaffolding

### Task 1: Initialize repo with Bun + TypeScript + strict config

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/package.json`
- Create: `/Users/dixoncider/slabbist/tcgcsv/tsconfig.json`
- Create: `/Users/dixoncider/slabbist/tcgcsv/.gitignore`
- Create: `/Users/dixoncider/slabbist/tcgcsv/.env.example`
- Create: `/Users/dixoncider/slabbist/tcgcsv/README.md`

- [ ] **Step 1: Create package.json**

```json
{
  "name": "@slabbist/tcgcsv",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "engines": { "node": ">=20" },
  "scripts": {
    "cli": "tsx src/cli.ts",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest",
    "smoke": "tsx src/cli.ts smoke"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.45.0",
    "commander": "^12.1.0",
    "dotenv": "^16.4.5",
    "p-limit": "^5.0.0",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@types/node": "^20.12.12",
    "pg-mem": "^3.0.4",
    "tsx": "^4.11.0",
    "typescript": "^5.5.0",
    "vitest": "^1.6.0"
  }
}
```

- [ ] **Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "lib": ["ES2022"],
    "strict": true,
    "noImplicitAny": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "exactOptionalPropertyTypes": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "skipLibCheck": true,
    "noEmit": true,
    "types": ["node", "vitest/globals"],
    "baseUrl": ".",
    "paths": { "@/*": ["src/*"] }
  },
  "include": ["src/**/*", "tests/**/*"]
}
```

- [ ] **Step 3: Create .gitignore**

```gitignore
node_modules/
dist/
.env
.env.local
*.log
.DS_Store
coverage/
.vitest-cache/
```

- [ ] **Step 4: Create .env.example**

```bash
# Supabase (service role - write access)
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=

# Grading APIs (fill in as credentials are obtained)
PSA_API_KEY=
BECKETT_OPG_KEY=
TAG_API_KEY=

# eBay (Browse + Marketplace Insights)
EBAY_APP_ID=
EBAY_CERT_ID=
EBAY_DEV_ID=
EBAY_MARKETPLACE_INSIGHTS_APPROVED=false

# Runtime knobs
LOG_LEVEL=info
HTTP_USER_AGENT=slabbist-tcgcsv/0.1 (+https://slabbist.com)
```

- [ ] **Step 5: Create README.md stub**

```markdown
# @slabbist/tcgcsv

Ingestion-only pipeline that populates the Slabbist monorepo's Supabase DB with raw Pokémon catalog/pricing (tcgcsv.com) and graded card data (PSA/CGC/BGS/SGC/TAG + eBay).

See `docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md` for design.

## Quick start

    bun install
    cp .env.example .env   # fill in credentials
    bun run typecheck
    bun run test

## CLI

    bun run cli run raw tcgcsv          # daily: refresh tcgcsv Pokémon (cat 3, 85)
    bun run cli run graded ebay         # hourly: eBay sold listings -> graded market
    bun run cli run graded pop          # weekly: grading-service pop reports

Each command is also wired to a GitHub Actions cron workflow in `.github/workflows/`.
```

- [ ] **Step 6: Install dependencies and verify**

```bash
cd /Users/dixoncider/slabbist/tcgcsv
bun install
bun run typecheck
```

Expected: `bun install` produces `bun.lock` and `node_modules/`. `typecheck` produces no errors (no source files yet; tsc exits 0).

- [ ] **Step 7: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/package.json tcgcsv/tsconfig.json \
  tcgcsv/.gitignore tcgcsv/.env.example tcgcsv/README.md tcgcsv/bun.lock
git -C /Users/dixoncider/slabbist commit -m "Initialize tcgcsv repo with Bun + TypeScript strict config"
```

---

### Task 2: Add Vitest configuration

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/vitest.config.ts`

- [ ] **Step 1: Create vitest.config.ts**

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    include: ["tests/**/*.test.ts"],
    coverage: {
      provider: "v8",
      reporter: ["text", "html"],
      include: ["src/**/*.ts"],
      exclude: ["src/cli.ts", "src/**/*.d.ts"],
    },
  },
  resolve: {
    alias: { "@": new URL("./src", import.meta.url).pathname },
  },
});
```

- [ ] **Step 2: Verify vitest runs clean with no tests**

```bash
bun run test
```

Expected: `No test files found` exit 0 (or `1 passed (0 skipped)` — either is acceptable).

- [ ] **Step 3: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/vitest.config.ts
git -C /Users/dixoncider/slabbist commit -m "Add Vitest configuration"
```

---

## Phase 2 — Shared utilities

### Task 3: `shared/config.ts` — typed env loader

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/shared/config.ts`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/shared/config.test.ts`

- [ ] **Step 1: Write failing test**

```ts
// tests/shared/config.test.ts
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
    expect(cfg.ebay.marketplaceInsightsApproved).toBe(false);
  });

  it("throws when SUPABASE_URL is missing", () => {
    process.env.SUPABASE_SERVICE_ROLE_KEY = "svc";
    expect(() => loadConfig()).toThrow(/SUPABASE_URL/);
  });
});
```

- [ ] **Step 2: Run and confirm failure**

```bash
bun run test tests/shared/config.test.ts
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement config loader**

```ts
// src/shared/config.ts
import "dotenv/config";

export interface AppConfig {
  supabase: { url: string; serviceRoleKey: string };
  grading: { psaApiKey?: string; beckettOpgKey?: string; tagApiKey?: string };
  ebay: { appId?: string; certId?: string; devId?: string; marketplaceInsightsApproved: boolean };
  runtime: { logLevel: "debug" | "info" | "warn" | "error"; userAgent: string };
}

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

export function loadConfig(): AppConfig {
  return {
    supabase: {
      url: required("SUPABASE_URL"),
      serviceRoleKey: required("SUPABASE_SERVICE_ROLE_KEY"),
    },
    grading: {
      psaApiKey: process.env.PSA_API_KEY || undefined,
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
```

- [ ] **Step 4: Run and confirm passing**

```bash
bun run test tests/shared/config.test.ts
```

Expected: PASS both cases.

- [ ] **Step 5: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/shared/config.ts tcgcsv/tests/shared/config.test.ts
git -C /Users/dixoncider/slabbist commit -m "Add typed env config loader"
```

---

### Task 4: `shared/logger.ts` — structured JSON logger

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/shared/logger.ts`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/shared/logger.test.ts`

- [ ] **Step 1: Write failing test**

```ts
// tests/shared/logger.test.ts
import { describe, it, expect, vi } from "vitest";
import { createLogger } from "@/shared/logger.js";

describe("createLogger", () => {
  it("emits structured JSON with level, msg, and fields", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const log = createLogger({ level: "info" });
    log.info("hello", { productId: 42 });
    expect(spy).toHaveBeenCalledOnce();
    const line = JSON.parse(spy.mock.calls[0]![0] as string);
    expect(line.level).toBe("info");
    expect(line.msg).toBe("hello");
    expect(line.productId).toBe(42);
    expect(typeof line.ts).toBe("string");
    spy.mockRestore();
  });

  it("suppresses debug when level is info", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const log = createLogger({ level: "info" });
    log.debug("skip");
    expect(spy).not.toHaveBeenCalled();
    spy.mockRestore();
  });
});
```

- [ ] **Step 2: Run and confirm failure**

```bash
bun run test tests/shared/logger.test.ts
```

- [ ] **Step 3: Implement logger**

```ts
// src/shared/logger.ts
export type LogLevel = "debug" | "info" | "warn" | "error";

const LEVEL_WEIGHT: Record<LogLevel, number> = { debug: 10, info: 20, warn: 30, error: 40 };

export interface Logger {
  debug: (msg: string, fields?: Record<string, unknown>) => void;
  info: (msg: string, fields?: Record<string, unknown>) => void;
  warn: (msg: string, fields?: Record<string, unknown>) => void;
  error: (msg: string, fields?: Record<string, unknown>) => void;
  child: (fields: Record<string, unknown>) => Logger;
}

export function createLogger(opts: { level: LogLevel; base?: Record<string, unknown> }): Logger {
  const threshold = LEVEL_WEIGHT[opts.level];
  const base = opts.base ?? {};
  const emit = (level: LogLevel, msg: string, fields?: Record<string, unknown>) => {
    if (LEVEL_WEIGHT[level] < threshold) return;
    const line = { ts: new Date().toISOString(), level, msg, ...base, ...fields };
    console.log(JSON.stringify(line));
  };
  return {
    debug: (m, f) => emit("debug", m, f),
    info: (m, f) => emit("info", m, f),
    warn: (m, f) => emit("warn", m, f),
    error: (m, f) => emit("error", m, f),
    child: (fields) => createLogger({ level: opts.level, base: { ...base, ...fields } }),
  };
}
```

- [ ] **Step 4: Run and confirm passing**

```bash
bun run test tests/shared/logger.test.ts
```

- [ ] **Step 5: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/shared/logger.ts tcgcsv/tests/shared/logger.test.ts
git -C /Users/dixoncider/slabbist commit -m "Add structured JSON logger"
```

---

### Task 5: `shared/retry.ts` — exponential backoff with Retry-After

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/shared/retry.ts`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/shared/retry.test.ts`

- [ ] **Step 1: Write failing tests**

```ts
// tests/shared/retry.test.ts
import { describe, it, expect, vi } from "vitest";
import { withRetry } from "@/shared/retry.js";

describe("withRetry", () => {
  it("returns on first success", async () => {
    const fn = vi.fn().mockResolvedValue("ok");
    const out = await withRetry(fn, { maxAttempts: 3, initialMs: 1, multiplier: 2 });
    expect(out).toBe("ok");
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("retries on retryable errors and eventually succeeds", async () => {
    const fn = vi.fn()
      .mockRejectedValueOnce(Object.assign(new Error("rate-limited"), { retryable: true }))
      .mockResolvedValue("ok");
    const out = await withRetry(fn, { maxAttempts: 3, initialMs: 1, multiplier: 2 });
    expect(out).toBe("ok");
    expect(fn).toHaveBeenCalledTimes(2);
  });

  it("throws after maxAttempts", async () => {
    const err = Object.assign(new Error("persistent"), { retryable: true });
    const fn = vi.fn().mockRejectedValue(err);
    await expect(
      withRetry(fn, { maxAttempts: 3, initialMs: 1, multiplier: 2 })
    ).rejects.toThrow("persistent");
    expect(fn).toHaveBeenCalledTimes(3);
  });

  it("does not retry non-retryable errors", async () => {
    const err = new Error("client error");
    const fn = vi.fn().mockRejectedValue(err);
    await expect(
      withRetry(fn, { maxAttempts: 3, initialMs: 1, multiplier: 2 })
    ).rejects.toThrow("client error");
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("honors retryAfterMs hint from the thrown error", async () => {
    const fn = vi.fn()
      .mockRejectedValueOnce(Object.assign(new Error("429"), { retryable: true, retryAfterMs: 5 }))
      .mockResolvedValue("ok");
    const t0 = Date.now();
    await withRetry(fn, { maxAttempts: 3, initialMs: 1, multiplier: 2 });
    expect(Date.now() - t0).toBeGreaterThanOrEqual(5);
  });
});
```

- [ ] **Step 2: Run and confirm failure**

```bash
bun run test tests/shared/retry.test.ts
```

- [ ] **Step 3: Implement retry**

```ts
// src/shared/retry.ts
export interface RetryOptions {
  maxAttempts: number;
  initialMs: number;
  multiplier: number;
}

export interface RetryableError extends Error {
  retryable?: boolean;
  retryAfterMs?: number;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function withRetry<T>(fn: () => Promise<T>, opts: RetryOptions): Promise<T> {
  let attempt = 0;
  let delay = opts.initialMs;
  let lastErr: unknown;
  while (attempt < opts.maxAttempts) {
    try {
      return await fn();
    } catch (e) {
      lastErr = e;
      const err = e as RetryableError;
      if (!err.retryable) throw e;
      attempt += 1;
      if (attempt >= opts.maxAttempts) break;
      const wait = err.retryAfterMs ?? delay;
      await sleep(wait);
      delay *= opts.multiplier;
    }
  }
  throw lastErr;
}
```

- [ ] **Step 4: Run and confirm passing**

```bash
bun run test tests/shared/retry.test.ts
```

- [ ] **Step 5: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/shared/retry.ts tcgcsv/tests/shared/retry.test.ts
git -C /Users/dixoncider/slabbist commit -m "Add exponential-backoff retry utility"
```

---

### Task 6: `shared/http/fetch.ts` — HTTP wrapper (UA, retry, status classification)

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/shared/http/fetch.ts`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/shared/http/fetch.test.ts`

- [ ] **Step 1: Write failing tests**

```ts
// tests/shared/http/fetch.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { httpJson } from "@/shared/http/fetch.js";

describe("httpJson", () => {
  beforeEach(() => { vi.restoreAllMocks(); });

  it("returns parsed JSON on 200", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ a: 1 }), { status: 200, headers: { "content-type": "application/json" } })
    ));
    const out = await httpJson("https://example.com/x", { userAgent: "ua/1" });
    expect(out).toEqual({ a: 1 });
  });

  it("throws retryable error on 429", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
      new Response("", { status: 429, headers: { "retry-after": "2" } })
    ));
    await expect(httpJson("https://example.com", { userAgent: "ua/1", maxAttempts: 1, initialMs: 1, multiplier: 2 }))
      .rejects.toMatchObject({ retryable: true, retryAfterMs: 2000 });
  });

  it("throws non-retryable error on 404", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("nope", { status: 404 })));
    await expect(httpJson("https://example.com", { userAgent: "ua/1", maxAttempts: 1, initialMs: 1, multiplier: 2 }))
      .rejects.toMatchObject({ retryable: false });
  });

  it("sends User-Agent header", async () => {
    const spy = vi.fn().mockResolvedValue(new Response("{}", { status: 200, headers: { "content-type": "application/json" } }));
    vi.stubGlobal("fetch", spy);
    await httpJson("https://example.com", { userAgent: "my-ua/9" });
    const req = spy.mock.calls[0]![1] as RequestInit;
    expect((req.headers as Record<string, string>)["User-Agent"]).toBe("my-ua/9");
  });
});
```

- [ ] **Step 2: Run and confirm failure**

```bash
bun run test tests/shared/http/fetch.test.ts
```

- [ ] **Step 3: Implement HTTP wrapper**

```ts
// src/shared/http/fetch.ts
import { withRetry, type RetryableError, type RetryOptions } from "@/shared/retry.js";

export interface HttpJsonOptions extends Partial<RetryOptions> {
  userAgent: string;
  headers?: Record<string, string>;
  method?: string;
  body?: string;
}

const RETRYABLE_STATUS = new Set([408, 425, 429, 500, 502, 503, 504]);

function classify(status: number, retryAfter: string | null): RetryableError {
  const err = new Error(`HTTP ${status}`) as RetryableError;
  err.retryable = RETRYABLE_STATUS.has(status);
  if (retryAfter) {
    const n = Number(retryAfter);
    if (Number.isFinite(n)) err.retryAfterMs = n * 1000;
  }
  return err;
}

export async function httpJson<T = unknown>(url: string, opts: HttpJsonOptions): Promise<T> {
  const retry: RetryOptions = {
    maxAttempts: opts.maxAttempts ?? 3,
    initialMs: opts.initialMs ?? 2000,
    multiplier: opts.multiplier ?? 2,
  };
  return withRetry<T>(async () => {
    let res: Response;
    try {
      res = await fetch(url, {
        method: opts.method ?? "GET",
        headers: { "User-Agent": opts.userAgent, Accept: "application/json", ...(opts.headers ?? {}) },
        body: opts.body,
      });
    } catch (e) {
      const err = e as RetryableError;
      err.retryable = true;
      throw err;
    }
    if (!res.ok) throw classify(res.status, res.headers.get("retry-after"));
    return (await res.json()) as T;
  }, retry);
}

export async function httpText(url: string, opts: HttpJsonOptions): Promise<string> {
  const retry: RetryOptions = {
    maxAttempts: opts.maxAttempts ?? 3,
    initialMs: opts.initialMs ?? 2000,
    multiplier: opts.multiplier ?? 2,
  };
  return withRetry<string>(async () => {
    let res: Response;
    try {
      res = await fetch(url, {
        method: opts.method ?? "GET",
        headers: { "User-Agent": opts.userAgent, ...(opts.headers ?? {}) },
        body: opts.body,
      });
    } catch (e) {
      const err = e as RetryableError;
      err.retryable = true;
      throw err;
    }
    if (!res.ok) throw classify(res.status, res.headers.get("retry-after"));
    return await res.text();
  }, retry);
}
```

- [ ] **Step 4: Run and confirm passing**

```bash
bun run test tests/shared/http/fetch.test.ts
```

- [ ] **Step 5: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/shared/http/fetch.ts tcgcsv/tests/shared/http/fetch.test.ts
git -C /Users/dixoncider/slabbist commit -m "Add HTTP JSON/text wrapper with retry and UA"
```

---

### Task 7: `shared/concurrency.ts` — concurrency helper around p-limit

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/shared/concurrency.ts`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/shared/concurrency.test.ts`

- [ ] **Step 1: Write failing test**

```ts
// tests/shared/concurrency.test.ts
import { describe, it, expect } from "vitest";
import { mapConcurrent } from "@/shared/concurrency.js";

describe("mapConcurrent", () => {
  it("preserves order and runs with bounded concurrency", async () => {
    let active = 0;
    let maxActive = 0;
    const out = await mapConcurrent([1, 2, 3, 4, 5], 2, async (n) => {
      active += 1; maxActive = Math.max(maxActive, active);
      await new Promise((r) => setTimeout(r, 5));
      active -= 1;
      return n * 2;
    });
    expect(out).toEqual([2, 4, 6, 8, 10]);
    expect(maxActive).toBeLessThanOrEqual(2);
  });

  it("applies delay between task starts when delayMs provided", async () => {
    const starts: number[] = [];
    await mapConcurrent([1, 2, 3], 1, async (_n) => { starts.push(Date.now()); }, { delayMs: 10 });
    expect(starts[1]! - starts[0]!).toBeGreaterThanOrEqual(10);
    expect(starts[2]! - starts[1]!).toBeGreaterThanOrEqual(10);
  });
});
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement**

```ts
// src/shared/concurrency.ts
import pLimit from "p-limit";

export interface MapConcurrentOptions {
  delayMs?: number;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function mapConcurrent<T, R>(
  items: readonly T[],
  concurrency: number,
  fn: (item: T, index: number) => Promise<R>,
  opts: MapConcurrentOptions = {},
): Promise<R[]> {
  const limit = pLimit(concurrency);
  const delay = opts.delayMs ?? 0;
  let nextStart = Date.now();
  return Promise.all(items.map((item, i) => limit(async () => {
    if (delay > 0) {
      const wait = nextStart - Date.now();
      if (wait > 0) await sleep(wait);
      nextStart = Math.max(Date.now(), nextStart) + delay;
    }
    return fn(item, i);
  })));
}
```

- [ ] **Step 4: Run and confirm passing**

- [ ] **Step 5: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/shared/concurrency.ts tcgcsv/tests/shared/concurrency.test.ts
git -C /Users/dixoncider/slabbist commit -m "Add mapConcurrent helper with optional per-start delay"
```

---

### Task 8: `shared/db/supabase.ts` — service-role client singleton

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/shared/db/supabase.ts`

(No unit test — this is a thin factory. Exercised by integration tests later.)

- [ ] **Step 1: Implement**

```ts
// src/shared/db/supabase.ts
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { loadConfig } from "@/shared/config.js";

let cached: SupabaseClient | null = null;

export function getSupabase(): SupabaseClient {
  if (cached) return cached;
  const cfg = loadConfig();
  cached = createClient(cfg.supabase.url, cfg.supabase.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { "x-slabbist-service": "tcgcsv-ingest" } },
  });
  return cached;
}

export function resetSupabaseForTesting(): void { cached = null; }
```

- [ ] **Step 2: Confirm typecheck passes**

```bash
bun run typecheck
```

- [ ] **Step 3: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/shared/db/supabase.ts
git -C /Users/dixoncider/slabbist commit -m "Add Supabase service-role client singleton"
```

---

## Phase 3 — Database migration (monorepo-shared)

### Task 9: Write the monorepo-shared migration

**Files:**
- Create: `/Users/dixoncider/slabbist/supabase/migrations/20260422120000_tcgcsv_pokemon_and_graded.sql`

**Note:** This file lives *outside* the tcgcsv repo, at the monorepo-shared migrations directory. It's the first migration written to that directory, so it also establishes the naming convention (`YYYYMMDDHHMMSS_<description>.sql`).

- [ ] **Step 1: Create migration SQL**

```sql
-- 20260422120000_tcgcsv_pokemon_and_graded.sql
-- Slabbist sub-project 2: raw Pokémon catalog (tcgcsv.com) + graded card data.
-- Raw and graded domains are intentionally decoupled (no FKs between them).

-- =============================================================================
-- Raw domain (tcg_*)
-- =============================================================================

create table if not exists public.tcg_categories (
  category_id     int primary key,
  name            text not null,
  modified_on     timestamptz
);

create table if not exists public.tcg_groups (
  group_id          int primary key,
  category_id       int not null references public.tcg_categories(category_id) on delete cascade,
  name              text not null,
  abbreviation      text,
  is_supplemental   boolean not null default false,
  published_on      date,
  modified_on       timestamptz
);
create index if not exists tcg_groups_category_id_idx on public.tcg_groups(category_id);

create table if not exists public.tcg_products (
  product_id          int primary key,
  group_id            int not null references public.tcg_groups(group_id) on delete cascade,
  category_id         int not null,
  name                text not null,
  clean_name          text,
  image_url           text,
  url                 text,
  modified_on         timestamptz,
  image_count         int,
  is_presale          boolean not null default false,
  presale_release_on  date,
  presale_note        text,
  card_number         text,
  rarity              text,
  card_type           text,
  hp                  text,
  stage               text,
  extended_data       jsonb
);
create index if not exists tcg_products_group_id_idx on public.tcg_products(group_id);
create index if not exists tcg_products_card_number_idx on public.tcg_products(card_number);

create table if not exists public.tcg_scrape_runs (
  id               uuid primary key default gen_random_uuid(),
  category_id      int not null,
  started_at       timestamptz not null default now(),
  finished_at      timestamptz,
  status           text not null default 'running' check (status in ('running','completed','failed','stale')),
  groups_total     int not null default 0,
  groups_done      int not null default 0,
  products_upserted int not null default 0,
  prices_upserted  int not null default 0,
  error_message    text
);

create table if not exists public.tcg_prices (
  product_id         int not null references public.tcg_products(product_id) on delete cascade,
  sub_type_name      text not null,
  low_price          numeric(12,2),
  mid_price          numeric(12,2),
  high_price         numeric(12,2),
  market_price       numeric(12,2),
  direct_low_price   numeric(12,2),
  updated_at         timestamptz not null default now(),
  primary key (product_id, sub_type_name)
);
create index if not exists tcg_prices_product_id_idx on public.tcg_prices(product_id);

create table if not exists public.tcg_price_history (
  id                 bigserial primary key,
  scrape_run_id      uuid not null references public.tcg_scrape_runs(id) on delete cascade,
  product_id         int not null references public.tcg_products(product_id) on delete cascade,
  sub_type_name      text not null,
  low_price          numeric(12,2),
  mid_price          numeric(12,2),
  high_price         numeric(12,2),
  market_price       numeric(12,2),
  direct_low_price   numeric(12,2),
  captured_at        timestamptz not null default now()
);
create index if not exists tcg_price_history_product_captured_idx
  on public.tcg_price_history(product_id, captured_at desc);

-- =============================================================================
-- Graded domain (graded_*)
-- =============================================================================

create table if not exists public.graded_card_identities (
  id              uuid primary key default gen_random_uuid(),
  game            text not null default 'pokemon',
  language        text not null check (language in ('en','jp')),
  set_name        text not null,
  set_code        text,
  year            int,
  card_number     text,
  card_name       text not null,
  variant         text,
  created_at      timestamptz not null default now()
);
create index if not exists graded_card_identities_lookup_idx
  on public.graded_card_identities(set_code, card_number);
create unique index if not exists graded_card_identities_unique_idx
  on public.graded_card_identities(game, language, set_name, card_number, coalesce(variant,''));

create table if not exists public.graded_cards (
  id               uuid primary key default gen_random_uuid(),
  identity_id      uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service  text not null check (grading_service in ('PSA','CGC','BGS','SGC','TAG')),
  cert_number      text not null,
  grade            text not null,
  graded_at        date,
  source_payload   jsonb,
  created_at       timestamptz not null default now(),
  unique (grading_service, cert_number)
);
create index if not exists graded_cards_identity_idx on public.graded_cards(identity_id);

create table if not exists public.graded_card_pops (
  id                bigserial primary key,
  identity_id       uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service   text not null,
  grade             text not null,
  population        int not null,
  captured_at       timestamptz not null default now()
);
create index if not exists graded_card_pops_identity_captured_idx
  on public.graded_card_pops(identity_id, captured_at desc);

create table if not exists public.graded_market (
  identity_id       uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service   text not null,
  grade             text not null,
  low_price         numeric(12,2),
  median_price      numeric(12,2),
  high_price        numeric(12,2),
  last_sale_price   numeric(12,2),
  last_sale_at      timestamptz,
  sample_count_30d  int not null default 0,
  sample_count_90d  int not null default 0,
  updated_at        timestamptz not null default now(),
  primary key (identity_id, grading_service, grade)
);
create index if not exists graded_market_identity_idx on public.graded_market(identity_id);

create table if not exists public.graded_market_sales (
  id                 bigserial primary key,
  identity_id        uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service    text not null,
  grade              text not null,
  source             text not null,
  source_listing_id  text not null,
  sold_price         numeric(12,2) not null,
  sold_at            timestamptz not null,
  title              text,
  url                text,
  captured_at        timestamptz not null default now(),
  unique (source, source_listing_id)
);
create index if not exists graded_market_sales_sold_at_idx on public.graded_market_sales(sold_at desc);
create index if not exists graded_market_sales_lookup_idx
  on public.graded_market_sales(identity_id, grading_service, grade);

create table if not exists public.graded_cert_sales (
  id                 bigserial primary key,
  graded_card_id     uuid not null references public.graded_cards(id) on delete cascade,
  source             text not null,
  source_listing_id  text not null,
  sold_price         numeric(12,2) not null,
  sold_at            timestamptz not null,
  title              text,
  url                text,
  captured_at        timestamptz not null default now(),
  unique (source, source_listing_id)
);
create index if not exists graded_cert_sales_card_idx on public.graded_cert_sales(graded_card_id);

create table if not exists public.graded_ingest_runs (
  id              uuid primary key default gen_random_uuid(),
  source          text not null,
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,
  status          text not null default 'running' check (status in ('running','completed','failed','stale')),
  stats           jsonb not null default '{}'::jsonb,
  error_message   text
);

-- =============================================================================
-- RLS: public read, service-role write.
-- =============================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'tcg_categories','tcg_groups','tcg_products','tcg_prices','tcg_price_history','tcg_scrape_runs',
    'graded_card_identities','graded_cards','graded_card_pops','graded_market',
    'graded_market_sales','graded_cert_sales','graded_ingest_runs'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_public_read', t);
    execute format('create policy %I on public.%I for select using (true)', t || '_public_read', t);
  end loop;
end $$;
```

- [ ] **Step 2: Apply migration against local Supabase**

This plan assumes the monorepo has `supabase` CLI configured or will have it via a sibling setup task. If local Supabase is running:

```bash
cd /Users/dixoncider/slabbist
supabase db push
```

If the monorepo's Supabase CLI config isn't in place yet, the engineer should coordinate with the user to apply the migration once it is — the SQL itself is self-contained and idempotent (all `create ... if not exists`).

- [ ] **Step 3: Commit**

```bash
git -C /Users/dixoncider/slabbist add supabase/migrations/20260422120000_tcgcsv_pokemon_and_graded.sql
git -C /Users/dixoncider/slabbist commit -m "Migration: tcg_* and graded_* tables for Pokémon ingest"
```

---

## Phase 4 — Raw domain

### Task 10: `raw/models.ts` — TS types for raw domain

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/raw/models.ts`

(No unit test — pure types.)

- [ ] **Step 1: Implement types**

```ts
// src/raw/models.ts
export interface TcgCategory {
  categoryId: number;
  name: string;
  modifiedOn?: string;
}

export interface TcgGroup {
  groupId: number;
  categoryId: number;
  name: string;
  abbreviation: string | null;
  isSupplemental: boolean;
  publishedOn: string | null;
  modifiedOn: string | null;
}

export interface TcgExtendedField { name: string; displayName: string; value: string; }

export interface TcgProductRaw {
  productId: number;
  groupId: number;
  categoryId: number;
  name: string;
  cleanName: string | null;
  imageUrl: string | null;
  url: string | null;
  modifiedOn: string | null;
  imageCount: number | null;
  presaleInfo: { isPresale: boolean; releasedOn: string | null; note: string | null } | null;
  extendedData: TcgExtendedField[];
}

export interface PokemonExtract {
  cardNumber: string | null;
  rarity: string | null;
  cardType: string | null;
  hp: string | null;
  stage: string | null;
}

export interface TcgPriceRow {
  productId: number;
  subTypeName: string;
  lowPrice: number | null;
  midPrice: number | null;
  highPrice: number | null;
  marketPrice: number | null;
  directLowPrice: number | null;
}

export const POKEMON_CATEGORIES = [
  { id: 3, language: "en" as const, label: "Pokémon (English)" },
  { id: 85, language: "jp" as const, label: "Pokémon (Japanese)" },
];
```

- [ ] **Step 2: Typecheck**

```bash
bun run typecheck
```

- [ ] **Step 3: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/raw/models.ts
git -C /Users/dixoncider/slabbist commit -m "Add raw-domain TS types"
```

---

### Task 11: `raw/extractors.ts` — Pokémon field extraction from extendedData

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/raw/extractors.ts`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/raw/extractors.test.ts`

- [ ] **Step 1: Write failing tests**

```ts
// tests/raw/extractors.test.ts
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
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement**

```ts
// src/raw/extractors.ts
import type { PokemonExtract, TcgExtendedField } from "@/raw/models.js";

const NUMBER_KEYS = new Set(["number", "cardnumber"]);
const RARITY_KEYS = new Set(["rarity"]);
const CARDTYPE_KEYS = new Set(["cardtype", "type"]);
const HP_KEYS = new Set(["hp"]);
const STAGE_KEYS = new Set(["stage"]);

const norm = (s: string) => s.toLowerCase().replace(/\s+/g, "");

function find(fields: readonly TcgExtendedField[], keys: Set<string>): string | null {
  for (const f of fields) {
    if (keys.has(norm(f.name)) || keys.has(norm(f.displayName))) return f.value;
  }
  return null;
}

export function extractPokemonFields(fields: readonly TcgExtendedField[]): PokemonExtract {
  return {
    cardNumber: find(fields, NUMBER_KEYS),
    rarity: find(fields, RARITY_KEYS),
    cardType: find(fields, CARDTYPE_KEYS),
    hp: find(fields, HP_KEYS),
    stage: find(fields, STAGE_KEYS),
  };
}
```

- [ ] **Step 4: Run and confirm passing**

- [ ] **Step 5: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/raw/extractors.ts tcgcsv/tests/raw/extractors.test.ts
git -C /Users/dixoncider/slabbist commit -m "Extract Pokémon fields from extendedData"
```

---

### Task 12: `raw/sources/tcgcsv.ts` — tcgcsv.com API client with zod

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/raw/sources/tcgcsv.ts`
- Create: `/Users/dixoncider/slabbist/tcgcsv/tests/fixtures/tcgcsv/groups-cat3.json`
- Create: `/Users/dixoncider/slabbist/tcgcsv/tests/fixtures/tcgcsv/products-group3-sv4.json`
- Create: `/Users/dixoncider/slabbist/tcgcsv/tests/fixtures/tcgcsv/prices-group3-sv4.json`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/raw/sources/tcgcsv.test.ts`

- [ ] **Step 1: Create realistic fixtures** (representative samples of tcgcsv response shape; one group, 2 products, 3 price rows)

`tests/fixtures/tcgcsv/groups-cat3.json`:

```json
{
  "success": true, "errors": [],
  "results": [
    { "groupId": 3188, "name": "SV04: Paradox Rift", "abbreviation": "SV04", "isSupplemental": false, "publishedOn": "2023-11-03T00:00:00", "modifiedOn": "2024-01-01T00:00:00", "categoryId": 3 }
  ]
}
```

`tests/fixtures/tcgcsv/products-group3-sv4.json`:

```json
{
  "success": true, "errors": [],
  "results": [
    {
      "productId": 500001, "name": "Charizard ex (125)", "cleanName": "Charizard ex 125",
      "imageUrl": "https://tcgplayer-cdn.tcgplayer.com/product/500001_200w.jpg",
      "categoryId": 3, "groupId": 3188,
      "url": "https://www.tcgplayer.com/product/500001",
      "modifiedOn": "2024-05-01T00:00:00", "imageCount": 1,
      "extendedData": [
        { "name": "Number", "displayName": "Number", "value": "125/182" },
        { "name": "Rarity", "displayName": "Rarity", "value": "Double Rare" },
        { "name": "HP", "displayName": "HP", "value": "330" },
        { "name": "Stage", "displayName": "Stage", "value": "Stage 2" },
        { "name": "CardType", "displayName": "Card Type", "value": "Darkness" }
      ]
    },
    {
      "productId": 500002, "name": "Pikachu (80)", "cleanName": "Pikachu 80",
      "imageUrl": null, "categoryId": 3, "groupId": 3188, "url": null,
      "modifiedOn": "2024-05-01T00:00:00", "imageCount": 0,
      "extendedData": []
    }
  ]
}
```

`tests/fixtures/tcgcsv/prices-group3-sv4.json`:

```json
{
  "success": true, "errors": [],
  "results": [
    { "productId": 500001, "subTypeName": "Normal", "lowPrice": 10.0, "midPrice": 12.5, "highPrice": 20.0, "marketPrice": 12.3, "directLowPrice": 11.5 },
    { "productId": 500001, "subTypeName": "Holofoil", "lowPrice": 15.0, "midPrice": 18.0, "highPrice": 25.0, "marketPrice": 17.8, "directLowPrice": 16.0 },
    { "productId": 500002, "subTypeName": "Normal", "lowPrice": 0.1, "midPrice": 0.2, "highPrice": 0.5, "marketPrice": 0.18, "directLowPrice": 0.15 }
  ]
}
```

- [ ] **Step 2: Write failing tests**

```ts
// tests/raw/sources/tcgcsv.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { fetchGroups, fetchProducts, fetchPrices } from "@/raw/sources/tcgcsv.js";

const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/tcgcsv");
const load = (name: string) => JSON.parse(readFileSync(join(FIXTURES, name), "utf8"));

function mockOk(body: unknown) {
  return vi.fn().mockResolvedValue(new Response(JSON.stringify(body), {
    status: 200, headers: { "content-type": "application/json" },
  }));
}

describe("tcgcsv source", () => {
  beforeEach(() => vi.restoreAllMocks());

  it("fetchGroups parses the category 3 groups payload", async () => {
    vi.stubGlobal("fetch", mockOk(load("groups-cat3.json")));
    const groups = await fetchGroups(3, { userAgent: "t" });
    expect(groups).toHaveLength(1);
    expect(groups[0]!.groupId).toBe(3188);
    expect(groups[0]!.categoryId).toBe(3);
  });

  it("fetchProducts parses the products payload", async () => {
    vi.stubGlobal("fetch", mockOk(load("products-group3-sv4.json")));
    const prods = await fetchProducts(3, 3188, { userAgent: "t" });
    expect(prods).toHaveLength(2);
    expect(prods[0]!.productId).toBe(500001);
    expect(prods[0]!.extendedData.length).toBeGreaterThan(0);
  });

  it("fetchPrices parses the prices payload", async () => {
    vi.stubGlobal("fetch", mockOk(load("prices-group3-sv4.json")));
    const prices = await fetchPrices(3, 3188, { userAgent: "t" });
    expect(prices).toHaveLength(3);
    expect(prices.find((p) => p.subTypeName === "Holofoil")?.marketPrice).toBe(17.8);
  });

  it("rejects malformed payload via zod", async () => {
    vi.stubGlobal("fetch", mockOk({ success: true, errors: [], results: [{ wrong: "shape" }] }));
    await expect(fetchGroups(3, { userAgent: "t" })).rejects.toThrow();
  });
});
```

- [ ] **Step 3: Run and confirm failure**

- [ ] **Step 4: Implement source module**

```ts
// src/raw/sources/tcgcsv.ts
import { z } from "zod";
import { httpJson } from "@/shared/http/fetch.js";
import type { TcgGroup, TcgProductRaw, TcgPriceRow } from "@/raw/models.js";

const BASE = "https://tcgcsv.com/tcgplayer";

const GroupsResponse = z.object({
  success: z.boolean(),
  errors: z.array(z.string()),
  results: z.array(z.object({
    groupId: z.number(),
    name: z.string(),
    abbreviation: z.string().nullable().optional(),
    isSupplemental: z.boolean().optional(),
    publishedOn: z.string().nullable().optional(),
    modifiedOn: z.string().nullable().optional(),
    categoryId: z.number(),
  })),
});

const ExtendedField = z.object({
  name: z.string(), displayName: z.string(), value: z.string(),
});

const ProductsResponse = z.object({
  success: z.boolean(),
  errors: z.array(z.string()),
  results: z.array(z.object({
    productId: z.number(),
    name: z.string(),
    cleanName: z.string().nullable().optional(),
    imageUrl: z.string().nullable().optional(),
    categoryId: z.number(),
    groupId: z.number(),
    url: z.string().nullable().optional(),
    modifiedOn: z.string().nullable().optional(),
    imageCount: z.number().nullable().optional(),
    presaleInfo: z.object({
      isPresale: z.boolean(),
      releasedOn: z.string().nullable(),
      note: z.string().nullable(),
    }).nullable().optional(),
    extendedData: z.array(ExtendedField).default([]),
  })),
});

const PricesResponse = z.object({
  success: z.boolean(),
  errors: z.array(z.string()),
  results: z.array(z.object({
    productId: z.number(),
    subTypeName: z.string(),
    lowPrice: z.number().nullable(),
    midPrice: z.number().nullable(),
    highPrice: z.number().nullable(),
    marketPrice: z.number().nullable(),
    directLowPrice: z.number().nullable(),
  })),
});

export interface SourceOpts { userAgent: string; }

export async function fetchGroups(categoryId: number, opts: SourceOpts): Promise<TcgGroup[]> {
  const raw = await httpJson(`${BASE}/${categoryId}/groups`, { userAgent: opts.userAgent });
  const parsed = GroupsResponse.parse(raw);
  return parsed.results.map((g) => ({
    groupId: g.groupId,
    categoryId: g.categoryId,
    name: g.name,
    abbreviation: g.abbreviation ?? null,
    isSupplemental: g.isSupplemental ?? false,
    publishedOn: g.publishedOn ?? null,
    modifiedOn: g.modifiedOn ?? null,
  }));
}

export async function fetchProducts(
  categoryId: number, groupId: number, opts: SourceOpts,
): Promise<TcgProductRaw[]> {
  const raw = await httpJson(`${BASE}/${categoryId}/${groupId}/products`, { userAgent: opts.userAgent });
  const parsed = ProductsResponse.parse(raw);
  return parsed.results.map((p) => ({
    productId: p.productId,
    groupId: p.groupId,
    categoryId: p.categoryId,
    name: p.name,
    cleanName: p.cleanName ?? null,
    imageUrl: p.imageUrl ?? null,
    url: p.url ?? null,
    modifiedOn: p.modifiedOn ?? null,
    imageCount: p.imageCount ?? null,
    presaleInfo: p.presaleInfo ?? null,
    extendedData: p.extendedData,
  }));
}

export async function fetchPrices(
  categoryId: number, groupId: number, opts: SourceOpts,
): Promise<TcgPriceRow[]> {
  const raw = await httpJson(`${BASE}/${categoryId}/${groupId}/prices`, { userAgent: opts.userAgent });
  const parsed = PricesResponse.parse(raw);
  return parsed.results.map((p) => ({ ...p }));
}
```

- [ ] **Step 5: Run and confirm passing**

```bash
bun run test tests/raw/sources/tcgcsv.test.ts
```

- [ ] **Step 6: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/raw/sources/tcgcsv.ts tcgcsv/tests/raw/sources/tcgcsv.test.ts tcgcsv/tests/fixtures/tcgcsv/
git -C /Users/dixoncider/slabbist commit -m "Add tcgcsv source fetcher with zod validation and fixtures"
```

---

### Task 13: `raw/ingest.ts` — orchestrator (fetch → upsert → history)

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/raw/ingest.ts`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/raw/ingest.test.ts`

- [ ] **Step 1: Write failing integration-style test**

This test exercises the orchestrator against an in-memory Postgres (pg-mem) and stubbed `fetch`, verifying that one full run: opens a `tcg_scrape_runs` row, upserts groups/products/prices, appends to price history, and closes the run row.

```ts
// tests/raw/ingest.test.ts
import { describe, it, expect, beforeEach, vi } from "vitest";
import { newDb } from "pg-mem";
import { ingestTcgcsvForCategory } from "@/raw/ingest.js";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const F = join(dirname(fileURLToPath(import.meta.url)), "../fixtures/tcgcsv");

/** Minimal Supabase-like adapter over pg-mem for ingest tests. */
function makeFakeSupabase() {
  const db = newDb({ autoCreateForeignKeyIndices: true });
  db.public.registerFunction({ name: "gen_random_uuid", returns: 2950 as any, implementation: () => crypto.randomUUID() });
  // load migration SQL
  const mig = readFileSync(
    join(dirname(fileURLToPath(import.meta.url)), "../../..", "supabase/migrations/20260422120000_tcgcsv_pokemon_and_graded.sql"),
    "utf8",
  );
  // strip DO $$ block (pg-mem lacks procedural support) — RLS doesn't affect tests
  const sqlNoRls = mig.replace(/do \$\$[\s\S]*?\$\$;?/gmi, "");
  db.public.none(sqlNoRls);

  const pg = db.adapters.createPg();
  const pool = new pg.Pool();

  return {
    from: (table: string) => ({
      upsert: async (rows: Record<string, unknown>[], { onConflict }: { onConflict: string }) => {
        const client = await pool.connect();
        try {
          for (const row of rows) {
            const cols = Object.keys(row);
            const vals = cols.map((_, i) => `$${i + 1}`);
            const params = cols.map((c) => row[c]);
            const conflictCols = onConflict.split(",").map((c) => c.trim());
            const updateSet = cols.filter((c) => !conflictCols.includes(c)).map((c) => `${c}=excluded.${c}`).join(",");
            const sql = `insert into public.${table} (${cols.join(",")}) values (${vals.join(",")}) on conflict (${conflictCols.join(",")}) do update set ${updateSet || "created_at=public.${table}.created_at"}`;
            await client.query(sql, params);
          }
          return { error: null };
        } finally { client.release(); }
      },
      insert: async (rows: Record<string, unknown> | Record<string, unknown>[]) => {
        const arr = Array.isArray(rows) ? rows : [rows];
        const client = await pool.connect();
        try {
          for (const row of arr) {
            const cols = Object.keys(row);
            const vals = cols.map((_, i) => `$${i + 1}`);
            await client.query(`insert into public.${table} (${cols.join(",")}) values (${vals.join(",")})`, cols.map((c) => row[c]));
          }
          return { error: null };
        } finally { client.release(); }
      },
      update: (patch: Record<string, unknown>) => ({
        eq: async (col: string, val: unknown) => {
          const client = await pool.connect();
          try {
            const setCols = Object.keys(patch);
            const setClause = setCols.map((c, i) => `${c}=$${i + 1}`).join(",");
            await client.query(`update public.${table} set ${setClause} where ${col} = $${setCols.length + 1}`, [...setCols.map((c) => patch[c]), val]);
            return { error: null };
          } finally { client.release(); }
        },
      }),
      select: () => ({
        eq: async (col: string, val: unknown) => {
          const client = await pool.connect();
          try {
            const res = await client.query(`select * from public.${table} where ${col} = $1`, [val]);
            return { data: res.rows, error: null };
          } finally { client.release(); }
        },
      }),
    }),
    _debug: { pool, db },
  };
}

function mockOk(body: unknown) {
  return vi.fn().mockResolvedValue(new Response(JSON.stringify(body), {
    status: 200, headers: { "content-type": "application/json" },
  }));
}

describe("ingestTcgcsvForCategory", () => {
  beforeEach(() => vi.restoreAllMocks());

  it("ingests one category end-to-end and records a completed run", async () => {
    const groups = JSON.parse(readFileSync(join(F, "groups-cat3.json"), "utf8"));
    const products = JSON.parse(readFileSync(join(F, "products-group3-sv4.json"), "utf8"));
    const prices = JSON.parse(readFileSync(join(F, "prices-group3-sv4.json"), "utf8"));
    const seq = [groups, products, prices];
    const fetchMock = vi.fn().mockImplementation(async () =>
      new Response(JSON.stringify(seq.shift()), { status: 200, headers: { "content-type": "application/json" } }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const supa = makeFakeSupabase() as any;
    const result = await ingestTcgcsvForCategory({
      categoryId: 3,
      supabase: supa,
      userAgent: "test",
      concurrency: 1,
      delayMs: 0,
    });

    expect(result.status).toBe("completed");
    expect(result.groupsDone).toBe(1);
    expect(result.productsUpserted).toBe(2);
    expect(result.pricesUpserted).toBe(3);

    const products2 = await supa._debug.pool.query("select * from public.tcg_products");
    expect(products2.rows).toHaveLength(2);
    const history = await supa._debug.pool.query("select * from public.tcg_price_history");
    expect(history.rows).toHaveLength(3);
  });
});
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement orchestrator**

```ts
// src/raw/ingest.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import { extractPokemonFields } from "@/raw/extractors.js";
import { fetchGroups, fetchProducts, fetchPrices } from "@/raw/sources/tcgcsv.js";
import { mapConcurrent } from "@/shared/concurrency.js";

export interface IngestOptions {
  categoryId: number;
  supabase: SupabaseClient;
  userAgent: string;
  concurrency?: number;
  delayMs?: number;
}

export interface IngestResult {
  scrapeRunId: string;
  status: "completed" | "failed";
  groupsDone: number;
  productsUpserted: number;
  pricesUpserted: number;
  errorMessage?: string;
}

const BATCH = 500;

function chunk<T>(arr: readonly T[], n: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
}

export async function ingestTcgcsvForCategory(opts: IngestOptions): Promise<IngestResult> {
  const { supabase, categoryId } = opts;
  const { userAgent } = opts;
  const concurrency = opts.concurrency ?? 3;
  const delayMs = opts.delayMs ?? 200;

  // Ensure the tcg_categories row exists (idempotent upsert of the category).
  await supabase.from("tcg_categories").upsert(
    [{ category_id: categoryId, name: categoryId === 3 ? "Pokemon" : categoryId === 85 ? "Pokemon Japan" : `cat-${categoryId}`, modified_on: new Date().toISOString() }],
    { onConflict: "category_id" },
  );

  // Open a run row.
  const runId = crypto.randomUUID();
  await supabase.from("tcg_scrape_runs").insert({
    id: runId, category_id: categoryId, status: "running",
    started_at: new Date().toISOString(),
  });

  let groupsDone = 0;
  let productsUpserted = 0;
  let pricesUpserted = 0;

  try {
    const groups = await fetchGroups(categoryId, { userAgent });
    await supabase.from("tcg_scrape_runs").update({ groups_total: groups.length }).eq("id", runId);

    await supabase.from("tcg_groups").upsert(
      groups.map((g) => ({
        group_id: g.groupId, category_id: g.categoryId, name: g.name,
        abbreviation: g.abbreviation, is_supplemental: g.isSupplemental,
        published_on: g.publishedOn, modified_on: g.modifiedOn,
      })),
      { onConflict: "group_id" },
    );

    await mapConcurrent(groups, concurrency, async (group) => {
      try {
        const products = await fetchProducts(categoryId, group.groupId, { userAgent });
        const rows = products.map((p) => {
          const ex = extractPokemonFields(p.extendedData);
          return {
            product_id: p.productId, group_id: p.groupId, category_id: p.categoryId,
            name: p.name, clean_name: p.cleanName, image_url: p.imageUrl, url: p.url,
            modified_on: p.modifiedOn, image_count: p.imageCount,
            is_presale: p.presaleInfo?.isPresale ?? false,
            presale_release_on: p.presaleInfo?.releasedOn ?? null,
            presale_note: p.presaleInfo?.note ?? null,
            card_number: ex.cardNumber, rarity: ex.rarity, card_type: ex.cardType, hp: ex.hp, stage: ex.stage,
            extended_data: p.extendedData,
          };
        });
        for (const batch of chunk(rows, BATCH)) {
          await supabase.from("tcg_products").upsert(batch, { onConflict: "product_id" });
          productsUpserted += batch.length;
        }

        const prices = await fetchPrices(categoryId, group.groupId, { userAgent });
        const priceRows = prices.map((p) => ({
          product_id: p.productId, sub_type_name: p.subTypeName,
          low_price: p.lowPrice, mid_price: p.midPrice, high_price: p.highPrice,
          market_price: p.marketPrice, direct_low_price: p.directLowPrice,
          updated_at: new Date().toISOString(),
        }));
        const historyRows = prices.map((p) => ({
          scrape_run_id: runId, product_id: p.productId, sub_type_name: p.subTypeName,
          low_price: p.lowPrice, mid_price: p.midPrice, high_price: p.highPrice,
          market_price: p.marketPrice, direct_low_price: p.directLowPrice,
          captured_at: new Date().toISOString(),
        }));
        for (const b of chunk(priceRows, BATCH)) {
          await supabase.from("tcg_prices").upsert(b, { onConflict: "product_id,sub_type_name" });
          pricesUpserted += b.length;
        }
        for (const b of chunk(historyRows, BATCH)) {
          await supabase.from("tcg_price_history").insert(b);
        }

        groupsDone += 1;
        await supabase.from("tcg_scrape_runs").update({
          groups_done: groupsDone, products_upserted: productsUpserted, prices_upserted: pricesUpserted,
        }).eq("id", runId);
      } catch (e) {
        // Per-group failure: log via run row but continue.
        await supabase.from("tcg_scrape_runs").update({
          error_message: `group ${group.groupId}: ${String((e as Error).message ?? e)}`,
        }).eq("id", runId);
      }
    }, { delayMs });

    await supabase.from("tcg_scrape_runs").update({
      status: "completed", finished_at: new Date().toISOString(),
      groups_done: groupsDone, products_upserted: productsUpserted, prices_upserted: pricesUpserted,
    }).eq("id", runId);

    return { scrapeRunId: runId, status: "completed", groupsDone, productsUpserted, pricesUpserted };
  } catch (e) {
    const msg = String((e as Error).message ?? e);
    await supabase.from("tcg_scrape_runs").update({
      status: "failed", finished_at: new Date().toISOString(), error_message: msg,
    }).eq("id", runId);
    return { scrapeRunId: runId, status: "failed", groupsDone, productsUpserted, pricesUpserted, errorMessage: msg };
  }
}

export async function ingestPokemonAllCategories(opts: Omit<IngestOptions, "categoryId">): Promise<IngestResult[]> {
  const out: IngestResult[] = [];
  for (const id of [3, 85]) out.push(await ingestTcgcsvForCategory({ ...opts, categoryId: id }));
  return out;
}
```

- [ ] **Step 4: Run and confirm passing**

```bash
bun run test tests/raw/ingest.test.ts
```

- [ ] **Step 5: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/raw/ingest.ts tcgcsv/tests/raw/ingest.test.ts
git -C /Users/dixoncider/slabbist commit -m "Add raw-domain ingest orchestrator with pg-mem integration test"
```

---

## Phase 5 — Graded domain skeleton

### Task 14: `graded/models.ts` — TS types

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/graded/models.ts`

- [ ] **Step 1: Implement types**

```ts
// src/graded/models.ts
export type GradingService = "PSA" | "CGC" | "BGS" | "SGC" | "TAG";
export type Language = "en" | "jp";

export interface GradedCardIdentityInput {
  game: "pokemon";
  language: Language;
  setName: string;
  setCode?: string | null;
  year?: number | null;
  cardNumber?: string | null;
  cardName: string;
  variant?: string | null;
}

export interface GradedCardIdentity extends GradedCardIdentityInput { id: string; }

export interface GradedCertRecord {
  gradingService: GradingService;
  certNumber: string;
  grade: string;
  gradedAt?: string | null;
  identity: GradedCardIdentityInput;
  sourcePayload: unknown;
}

export interface GradedSale {
  identity: GradedCardIdentityInput;
  gradingService: GradingService;
  grade: string;
  source: string;           // e.g. "ebay"
  sourceListingId: string;
  soldPrice: number;
  soldAt: string;           // ISO timestamp
  title: string;
  url: string;
  certNumber?: string | null;  // parsed from title when present
}

export interface PopRow {
  identity: GradedCardIdentityInput;
  gradingService: GradingService;
  grade: string;
  population: number;
}
```

- [ ] **Step 2: Typecheck and commit**

```bash
bun run typecheck
git -C /Users/dixoncider/slabbist add tcgcsv/src/graded/models.ts
git -C /Users/dixoncider/slabbist commit -m "Add graded-domain TS types"
```

---

### Task 15: `graded/identity.ts` — normalizer + find-or-create

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/graded/identity.ts`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/graded/identity.test.ts`

- [ ] **Step 1: Write failing tests (pure normalization only — DB lookup tested in ingest integration tests)**

```ts
// tests/graded/identity.test.ts
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
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement**

```ts
// src/graded/identity.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradedCardIdentityInput } from "@/graded/models.js";

export interface NormalizedIdentityKey {
  game: "pokemon";
  language: "en" | "jp";
  setName: string;
  cardName: string;
  cardNumber: string;
  variant: string;
}

function normText(s: string | null | undefined): string {
  return (s ?? "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\/\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function normalizeIdentityKey(input: GradedCardIdentityInput): NormalizedIdentityKey {
  return {
    game: input.game,
    language: input.language,
    setName: normText(input.setName),
    cardName: normText(input.cardName),
    cardNumber: (input.cardNumber ?? "").trim(),
    variant: normText(input.variant ?? ""),
  };
}

export async function findOrCreateIdentity(
  supabase: SupabaseClient,
  input: GradedCardIdentityInput,
): Promise<string> {
  const key = normalizeIdentityKey(input);
  const { data } = await supabase
    .from("graded_card_identities")
    .select("id, set_name, card_name, card_number, variant, language")
    .eq("game", key.game);
  const list = (data ?? []) as Array<Record<string, unknown>>;
  for (const row of list) {
    const candidate = normalizeIdentityKey({
      game: "pokemon",
      language: row.language as "en" | "jp",
      setName: String(row.set_name ?? ""),
      cardName: String(row.card_name ?? ""),
      cardNumber: String(row.card_number ?? ""),
      variant: String(row.variant ?? ""),
    });
    if (
      candidate.language === key.language &&
      candidate.setName === key.setName &&
      candidate.cardName === key.cardName &&
      candidate.cardNumber === key.cardNumber &&
      candidate.variant === key.variant
    ) {
      return String(row.id);
    }
  }
  const id = crypto.randomUUID();
  await supabase.from("graded_card_identities").insert({
    id, game: input.game, language: input.language,
    set_name: input.setName, set_code: input.setCode ?? null, year: input.year ?? null,
    card_number: input.cardNumber ?? null, card_name: input.cardName,
    variant: input.variant ?? null,
  });
  return id;
}
```

- [ ] **Step 4: Run and confirm passing**

- [ ] **Step 5: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/graded/identity.ts tcgcsv/tests/graded/identity.test.ts
git -C /Users/dixoncider/slabbist commit -m "Add graded identity normalizer and find-or-create"
```

---

### Task 16: `graded/cert-parser.ts` — extract cert#/grade/service from eBay titles

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/graded/cert-parser.ts`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/graded/cert-parser.test.ts`

- [ ] **Step 1: Write failing tests**

```ts
// tests/graded/cert-parser.test.ts
import { describe, it, expect } from "vitest";
import { parseGradedTitle } from "@/graded/cert-parser.js";

describe("parseGradedTitle", () => {
  it("parses a PSA 10 title", () => {
    const out = parseGradedTitle("1999 Pokemon Base Set Charizard Holo #4 PSA 10 GEM MINT");
    expect(out?.gradingService).toBe("PSA");
    expect(out?.grade).toBe("10");
    expect(out?.certNumber).toBeNull();
  });

  it("parses a BGS 9.5 title with half-grade", () => {
    const out = parseGradedTitle("Charizard Base Set BGS 9.5 Gem Mint");
    expect(out?.gradingService).toBe("BGS");
    expect(out?.grade).toBe("9.5");
  });

  it("parses CGC 10 Pristine", () => {
    const out = parseGradedTitle("CGC 10 PRISTINE Pikachu Illustrator Promo");
    expect(out?.gradingService).toBe("CGC");
    expect(out?.grade).toBe("10");
  });

  it("extracts cert number when present", () => {
    const out = parseGradedTitle("PSA 9 Blastoise Base #2 Cert 54829123 Unlimited");
    expect(out?.certNumber).toBe("54829123");
  });

  it("returns null for non-graded title", () => {
    expect(parseGradedTitle("Charizard Base Set Unlimited Ungraded")).toBeNull();
  });

  it("parses SGC 9 and TAG 10", () => {
    expect(parseGradedTitle("SGC 9 Mew Promo")?.gradingService).toBe("SGC");
    expect(parseGradedTitle("TAG 10 Charizard VMAX")?.gradingService).toBe("TAG");
  });
});
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement**

```ts
// src/graded/cert-parser.ts
import type { GradingService } from "@/graded/models.js";

const SERVICE_PATTERN = /\b(PSA|CGC|BGS|SGC|TAG)\s*([0-9]+(?:\.5)?)/i;
const CERT_PATTERN = /\b(?:cert|cert\s*#|certificate)\s*#?\s*([0-9]{5,})\b/i;

export interface ParsedTitle {
  gradingService: GradingService;
  grade: string;
  certNumber: string | null;
}

export function parseGradedTitle(title: string): ParsedTitle | null {
  const m = title.match(SERVICE_PATTERN);
  if (!m) return null;
  const gradingService = m[1]!.toUpperCase() as GradingService;
  const grade = m[2]!;
  const certMatch = title.match(CERT_PATTERN);
  const certNumber = certMatch ? certMatch[1]! : null;
  return { gradingService, grade, certNumber };
}
```

- [ ] **Step 4: Run and confirm passing**

- [ ] **Step 5: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/graded/cert-parser.ts tcgcsv/tests/graded/cert-parser.test.ts
git -C /Users/dixoncider/slabbist commit -m "Parse grading service/grade/cert from eBay titles"
```

---

### Task 17: `graded/aggregates.ts` — rolling-window stats

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/graded/aggregates.ts`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/graded/aggregates.test.ts`

- [ ] **Step 1: Write failing tests**

```ts
// tests/graded/aggregates.test.ts
import { describe, it, expect } from "vitest";
import { computeMarketAggregate } from "@/graded/aggregates.js";

const sale = (price: number, daysAgo: number) => ({
  sold_price: price,
  sold_at: new Date(Date.now() - daysAgo * 86_400_000).toISOString(),
});

describe("computeMarketAggregate", () => {
  it("returns nulls for empty input", () => {
    const out = computeMarketAggregate([]);
    expect(out.sampleCount30d).toBe(0);
    expect(out.medianPrice).toBeNull();
    expect(out.lastSalePrice).toBeNull();
  });

  it("computes 30d median/high/low and 90d sample count", () => {
    const sales = [sale(100, 5), sale(120, 10), sale(140, 20), sale(200, 60), sale(50, 100)];
    const out = computeMarketAggregate(sales);
    expect(out.sampleCount30d).toBe(3);   // 5, 10, 20 days
    expect(out.sampleCount90d).toBe(4);   // 5, 10, 20, 60 days
    expect(out.lowPrice).toBe(100);
    expect(out.highPrice).toBe(140);
    expect(out.medianPrice).toBe(120);
  });

  it("tracks latest sale across any window", () => {
    const sales = [sale(100, 5), sale(300, 1)];
    const out = computeMarketAggregate(sales);
    expect(out.lastSalePrice).toBe(300);
  });
});
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement**

```ts
// src/graded/aggregates.ts
export interface SaleRow { sold_price: number; sold_at: string; }

export interface MarketAggregate {
  lowPrice: number | null;
  medianPrice: number | null;
  highPrice: number | null;
  lastSalePrice: number | null;
  lastSaleAt: string | null;
  sampleCount30d: number;
  sampleCount90d: number;
}

function median(xs: readonly number[]): number | null {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b);
  const mid = s.length >> 1;
  return s.length % 2 ? s[mid]! : (s[mid - 1]! + s[mid]!) / 2;
}

export function computeMarketAggregate(sales: readonly SaleRow[]): MarketAggregate {
  const now = Date.now();
  const d30 = now - 30 * 86_400_000;
  const d90 = now - 90 * 86_400_000;

  let last: SaleRow | null = null;
  const in30: number[] = [];
  let sample90 = 0;

  for (const s of sales) {
    const t = Date.parse(s.sold_at);
    if (t >= d30) in30.push(s.sold_price);
    if (t >= d90) sample90 += 1;
    if (!last || t > Date.parse(last.sold_at)) last = s;
  }

  return {
    lowPrice: in30.length ? Math.min(...in30) : null,
    medianPrice: median(in30),
    highPrice: in30.length ? Math.max(...in30) : null,
    lastSalePrice: last?.sold_price ?? null,
    lastSaleAt: last?.sold_at ?? null,
    sampleCount30d: in30.length,
    sampleCount90d: sample90,
  };
}
```

- [ ] **Step 4: Run and confirm passing**

- [ ] **Step 5: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/graded/aggregates.ts tcgcsv/tests/graded/aggregates.test.ts
git -C /Users/dixoncider/slabbist commit -m "Add graded_market rolling-window aggregate"
```

---

## Phase 6 — Graded sources

**Note for Phase 6 sources (PSA/CGC/BGS/SGC/TAG/eBay):** Except for PSA (which has a documented public API) and eBay Browse API (documented), source modules start as **skeletons with fixture-driven tests that mirror the source-fetcher contract**. The engineer records a real API or HTML response once credentials/access is obtained, saves it under `tests/fixtures/<source>/`, and updates the zod schema to match. Each task delivers: the zod schema, the fetch function, normalization to `GradedCertRecord` / `GradedSale` / `PopRow`, and a unit test against at least one fixture.

### Task 18: `graded/sources/psa.ts` — PSA Public API

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/graded/sources/psa.ts`
- Create: `/Users/dixoncider/slabbist/tcgcsv/tests/fixtures/psa/cert-lookup-sample.json`
- Create: `/Users/dixoncider/slabbist/tcgcsv/tests/fixtures/psa/pop-report-sample.json`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/graded/sources/psa.test.ts`

- [ ] **Step 1: Create realistic fixtures modeled on PSA Public API**

`tests/fixtures/psa/cert-lookup-sample.json`:

```json
{
  "PSACert": {
    "CertNumber": "54829123",
    "Grade": "10",
    "Brand": "POKEMON",
    "Subject": "CHARIZARD-HOLO",
    "Variety": "SHADOWLESS",
    "CardNumber": "4",
    "Year": "1999",
    "GradedDate": "2020-04-15"
  }
}
```

`tests/fixtures/psa/pop-report-sample.json`:

```json
{
  "SpecID": 123456,
  "Subject": "CHARIZARD-HOLO",
  "CardNumber": "4",
  "Brand": "POKEMON",
  "Year": "1999",
  "Variety": "SHADOWLESS",
  "Pops": [
    { "Grade": "10", "Population": 142 },
    { "Grade": "9", "Population": 2201 },
    { "Grade": "8", "Population": 4185 }
  ]
}
```

- [ ] **Step 2: Write failing tests**

```ts
// tests/graded/sources/psa.test.ts
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
  beforeEach(() => vi.restoreAllMocks());

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
```

- [ ] **Step 3: Run and confirm failure**

- [ ] **Step 4: Implement**

```ts
// src/graded/sources/psa.ts
import { z } from "zod";
import { httpJson } from "@/shared/http/fetch.js";
import type { GradedCertRecord, PopRow } from "@/graded/models.js";

const PSA_BASE = "https://api.psacard.com/publicapi";

const CertLookupResponse = z.object({
  PSACert: z.object({
    CertNumber: z.string(),
    Grade: z.string(),
    Brand: z.string(),
    Subject: z.string(),
    Variety: z.string().nullable().optional(),
    CardNumber: z.string().nullable().optional(),
    Year: z.string().nullable().optional(),
    GradedDate: z.string().nullable().optional(),
  }),
});

const PopReportResponse = z.object({
  SpecID: z.number(),
  Subject: z.string(),
  CardNumber: z.string().nullable().optional(),
  Brand: z.string(),
  Year: z.string().nullable().optional(),
  Variety: z.string().nullable().optional(),
  Pops: z.array(z.object({ Grade: z.string(), Population: z.number() })),
});

export interface PsaOpts { apiKey: string; userAgent: string; }

function headers(opts: PsaOpts): Record<string, string> {
  return { Authorization: `Bearer ${opts.apiKey}` };
}

export async function psaCertLookup(certNumber: string, opts: PsaOpts): Promise<GradedCertRecord> {
  const body = await httpJson(`${PSA_BASE}/cert/GetByCertNumber/${certNumber}`, {
    userAgent: opts.userAgent, headers: headers(opts),
  });
  const p = CertLookupResponse.parse(body).PSACert;
  return {
    gradingService: "PSA",
    certNumber: p.CertNumber,
    grade: p.Grade,
    gradedAt: p.GradedDate ?? null,
    identity: {
      game: "pokemon",
      language: "en",   // PSA API doesn't distinguish; JP detection done elsewhere
      setName: p.Brand,
      cardName: p.Subject,
      cardNumber: p.CardNumber ?? null,
      variant: p.Variety ?? null,
      year: p.Year ? Number(p.Year) : null,
    },
    sourcePayload: body,
  };
}

export async function psaPopReport(specId: number, opts: PsaOpts): Promise<PopRow[]> {
  const body = await httpJson(`${PSA_BASE}/pop/GetPSASpecPopulation/${specId}`, {
    userAgent: opts.userAgent, headers: headers(opts),
  });
  const p = PopReportResponse.parse(body);
  return p.Pops.map((pop) => ({
    gradingService: "PSA",
    grade: pop.Grade,
    population: pop.Population,
    identity: {
      game: "pokemon",
      language: "en",
      setName: p.Brand,
      cardName: p.Subject,
      cardNumber: p.CardNumber ?? null,
      variant: p.Variety ?? null,
      year: p.Year ? Number(p.Year) : null,
    },
  }));
}
```

- [ ] **Step 5: Run and confirm passing**

- [ ] **Step 6: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/graded/sources/psa.ts tcgcsv/tests/graded/sources/psa.test.ts tcgcsv/tests/fixtures/psa/
git -C /Users/dixoncider/slabbist commit -m "Add PSA source: cert lookup + pop report"
```

---

### Task 19: `graded/sources/cgc.ts` — CGC HTML scraper

**Context:** CGC has no public API. We scrape the public cert lookup page at `cgccards.com/certlookup/<cert>/`. Fixture is HTML. When the page HTML changes, update the selectors and re-record the fixture.

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/graded/sources/cgc.ts`
- Create: `/Users/dixoncider/slabbist/tcgcsv/tests/fixtures/cgc/cert-lookup.html`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/graded/sources/cgc.test.ts`

- [ ] **Step 1: Create fixture (minimal representative HTML)**

`tests/fixtures/cgc/cert-lookup.html`:

```html
<html><body>
<div class="cert-details">
  <div data-label="Cert #">1234567890</div>
  <div data-label="Grade">9.5</div>
  <div data-label="Game">Pokemon</div>
  <div data-label="Set">Base Set Shadowless</div>
  <div data-label="Card">Charizard-Holo</div>
  <div data-label="Card Number">4</div>
  <div data-label="Year">1999</div>
  <div data-label="Variant">1st Edition</div>
  <div data-label="Language">English</div>
  <div data-label="Date Graded">2023-07-14</div>
</div>
</body></html>
```

- [ ] **Step 2: Write failing test**

```ts
// tests/graded/sources/cgc.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { cgcCertLookup } from "@/graded/sources/cgc.js";

const F = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/cgc");
const html = readFileSync(join(F, "cert-lookup.html"), "utf8");
const mockOkHtml = (body: string) => vi.fn().mockResolvedValue(new Response(body, { status: 200 }));

describe("cgc source", () => {
  beforeEach(() => vi.restoreAllMocks());

  it("cgcCertLookup scrapes fields into GradedCertRecord", async () => {
    vi.stubGlobal("fetch", mockOkHtml(html));
    const rec = await cgcCertLookup("1234567890", { userAgent: "t" });
    expect(rec.gradingService).toBe("CGC");
    expect(rec.certNumber).toBe("1234567890");
    expect(rec.grade).toBe("9.5");
    expect(rec.identity.setName).toBe("Base Set Shadowless");
    expect(rec.identity.cardName).toBe("Charizard-Holo");
    expect(rec.identity.cardNumber).toBe("4");
    expect(rec.identity.variant).toBe("1st Edition");
    expect(rec.identity.language).toBe("en");
  });

  it("throws when the cert-details block is missing", async () => {
    vi.stubGlobal("fetch", mockOkHtml("<html><body>not found</body></html>"));
    await expect(cgcCertLookup("0000000000", { userAgent: "t" })).rejects.toThrow(/CGC cert/i);
  });
});
```

- [ ] **Step 3: Run and confirm failure**

```bash
bun run test tests/graded/sources/cgc.test.ts
```

- [ ] **Step 4: Implement**

```ts
// src/graded/sources/cgc.ts
import { httpText } from "@/shared/http/fetch.js";
import type { GradedCertRecord } from "@/graded/models.js";

const CGC_BASE = "https://www.cgccards.com/certlookup";

function fieldByLabel(html: string, label: string): string | null {
  const re = new RegExp(
    `<div[^>]*data-label="${label.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&")}"[^>]*>([^<]*)</div>`,
    "i",
  );
  const m = html.match(re);
  return m ? m[1]!.trim() : null;
}

export interface CgcOpts { userAgent: string; }

export async function cgcCertLookup(certNumber: string, opts: CgcOpts): Promise<GradedCertRecord> {
  const html = await httpText(`${CGC_BASE}/${certNumber}/`, { userAgent: opts.userAgent });
  if (!/cert-details/.test(html)) throw new Error(`CGC cert not found: ${certNumber}`);

  const grade = fieldByLabel(html, "Grade") ?? "";
  const setName = fieldByLabel(html, "Set") ?? "";
  const cardName = fieldByLabel(html, "Card") ?? "";
  const cardNumber = fieldByLabel(html, "Card Number");
  const year = fieldByLabel(html, "Year");
  const variant = fieldByLabel(html, "Variant");
  const languageRaw = (fieldByLabel(html, "Language") ?? "English").toLowerCase();
  const gradedAt = fieldByLabel(html, "Date Graded");

  return {
    gradingService: "CGC",
    certNumber,
    grade,
    gradedAt: gradedAt ?? null,
    identity: {
      game: "pokemon",
      language: languageRaw.startsWith("jap") ? "jp" : "en",
      setName,
      cardName,
      cardNumber: cardNumber ?? null,
      variant: variant ?? null,
      year: year ? Number(year) : null,
    },
    sourcePayload: { html: html.slice(0, 10_000) },
  };
}
```

- [ ] **Step 5: Run and confirm passing**

- [ ] **Step 6: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/graded/sources/cgc.ts tcgcsv/tests/graded/sources/cgc.test.ts tcgcsv/tests/fixtures/cgc/
git -C /Users/dixoncider/slabbist commit -m "Add CGC source: HTML cert-lookup scraper"
```

---

### Task 20: `graded/sources/bgs.ts` — BGS with OPG API + HTML fallback

**Context:** Beckett OPG data lives behind a paid subscription. When `BECKETT_OPG_KEY` is set, use their API; otherwise fall back to scraping the public cert lookup at `beckett-grading.com`. This task implements the fallback path as a minimum-viable skeleton since API access is not assumed.

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/graded/sources/bgs.ts`
- Create: `/Users/dixoncider/slabbist/tcgcsv/tests/fixtures/bgs/cert-lookup.html`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/graded/sources/bgs.test.ts`

- [ ] **Step 1: Create fixture**

`tests/fixtures/bgs/cert-lookup.html`:

```html
<html><body>
<table class="cert-info">
  <tr><th>Certification #</th><td>0009876543</td></tr>
  <tr><th>Grade</th><td>9.5</td></tr>
  <tr><th>Sub-Grades</th><td>Centering 10 / Corners 9.5 / Edges 9.5 / Surface 9</td></tr>
  <tr><th>Brand</th><td>Pokémon</td></tr>
  <tr><th>Set</th><td>Base Set</td></tr>
  <tr><th>Player</th><td>Charizard</td></tr>
  <tr><th>Card Number</th><td>4</td></tr>
  <tr><th>Year</th><td>1999</td></tr>
  <tr><th>Attributes</th><td>Holo, Unlimited</td></tr>
</table>
</body></html>
```

- [ ] **Step 2: Write failing test**

```ts
// tests/graded/sources/bgs.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { bgsCertLookup } from "@/graded/sources/bgs.js";

const F = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/bgs");
const html = readFileSync(join(F, "cert-lookup.html"), "utf8");
const mockOk = (body: string) => vi.fn().mockResolvedValue(new Response(body, { status: 200 }));

describe("bgs source", () => {
  beforeEach(() => vi.restoreAllMocks());

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
```

- [ ] **Step 3: Run and confirm failure**

- [ ] **Step 4: Implement**

```ts
// src/graded/sources/bgs.ts
import { httpText } from "@/shared/http/fetch.js";
import type { GradedCertRecord } from "@/graded/models.js";

const BGS_BASE = "https://www.beckett-grading.com/population-report/cert-lookup";

function cellByHeader(html: string, header: string): string | null {
  const re = new RegExp(
    `<tr>\\s*<th[^>]*>\\s*${header.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&")}\\s*</th>\\s*<td[^>]*>([\\s\\S]*?)</td>`,
    "i",
  );
  const m = html.match(re);
  return m ? m[1]!.replace(/<[^>]+>/g, "").trim() : null;
}

export interface BgsOpts { userAgent: string; }

export async function bgsCertLookup(certNumber: string, opts: BgsOpts): Promise<GradedCertRecord> {
  const html = await httpText(`${BGS_BASE}?cert=${encodeURIComponent(certNumber)}`, { userAgent: opts.userAgent });
  if (!/cert-info/.test(html)) throw new Error(`BGS cert not found: ${certNumber}`);
  const grade = cellByHeader(html, "Grade") ?? "";
  return {
    gradingService: "BGS",
    certNumber,
    grade,
    gradedAt: null,
    identity: {
      game: "pokemon",
      language: "en",
      setName: cellByHeader(html, "Set") ?? "",
      cardName: cellByHeader(html, "Player") ?? "",
      cardNumber: cellByHeader(html, "Card Number"),
      variant: cellByHeader(html, "Attributes"),
      year: (() => { const y = cellByHeader(html, "Year"); return y ? Number(y) : null; })(),
    },
    sourcePayload: { html: html.slice(0, 10_000) },
  };
}
```

- [ ] **Step 5: Run and confirm passing**

- [ ] **Step 6: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/graded/sources/bgs.ts tcgcsv/tests/graded/sources/bgs.test.ts tcgcsv/tests/fixtures/bgs/
git -C /Users/dixoncider/slabbist commit -m "Add BGS source: HTML cert-lookup scraper (OPG API path to be added when key obtained)"
```

---

### Task 21: `graded/sources/sgc.ts` — SGC HTML scraper

**Context:** SGC (`gosgc.com`) exposes a public cert lookup. HTML fixture represents a cert-detail section.

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/graded/sources/sgc.ts`
- Create: `/Users/dixoncider/slabbist/tcgcsv/tests/fixtures/sgc/cert-lookup.html`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/graded/sources/sgc.test.ts`

- [ ] **Step 1: Create fixture**

`tests/fixtures/sgc/cert-lookup.html`:

```html
<html><body>
<section class="cert-result">
  <dl>
    <dt>Cert</dt><dd>12345678</dd>
    <dt>Grade</dt><dd>9</dd>
    <dt>Set</dt><dd>Pokemon Jungle</dd>
    <dt>Year</dt><dd>1999</dd>
    <dt>Card Number</dt><dd>11</dd>
    <dt>Player</dt><dd>Snorlax</dd>
    <dt>Variety</dt><dd>Holo</dd>
  </dl>
</section>
</body></html>
```

- [ ] **Step 2: Write failing test**

```ts
// tests/graded/sources/sgc.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { sgcCertLookup } from "@/graded/sources/sgc.js";

const F = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/sgc");
const html = readFileSync(join(F, "cert-lookup.html"), "utf8");
const mockOk = (body: string) => vi.fn().mockResolvedValue(new Response(body, { status: 200 }));

describe("sgc source", () => {
  beforeEach(() => vi.restoreAllMocks());

  it("sgcCertLookup parses dl-structured cert detail", async () => {
    vi.stubGlobal("fetch", mockOk(html));
    const rec = await sgcCertLookup("12345678", { userAgent: "t" });
    expect(rec.gradingService).toBe("SGC");
    expect(rec.grade).toBe("9");
    expect(rec.identity.cardName).toBe("Snorlax");
    expect(rec.identity.setName).toBe("Pokemon Jungle");
    expect(rec.identity.cardNumber).toBe("11");
    expect(rec.identity.variant).toBe("Holo");
  });

  it("throws when cert-result section is missing", async () => {
    vi.stubGlobal("fetch", mockOk("<html></html>"));
    await expect(sgcCertLookup("0", { userAgent: "t" })).rejects.toThrow(/SGC cert/i);
  });
});
```

- [ ] **Step 3: Run and confirm failure**

- [ ] **Step 4: Implement**

```ts
// src/graded/sources/sgc.ts
import { httpText } from "@/shared/http/fetch.js";
import type { GradedCertRecord } from "@/graded/models.js";

const SGC_BASE = "https://gosgc.com/certlookup";

function dtValue(html: string, key: string): string | null {
  const re = new RegExp(
    `<dt>\\s*${key.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&")}\\s*</dt>\\s*<dd>([\\s\\S]*?)</dd>`,
    "i",
  );
  const m = html.match(re);
  return m ? m[1]!.replace(/<[^>]+>/g, "").trim() : null;
}

export interface SgcOpts { userAgent: string; }

export async function sgcCertLookup(certNumber: string, opts: SgcOpts): Promise<GradedCertRecord> {
  const html = await httpText(`${SGC_BASE}/${certNumber}`, { userAgent: opts.userAgent });
  if (!/cert-result/.test(html)) throw new Error(`SGC cert not found: ${certNumber}`);
  return {
    gradingService: "SGC",
    certNumber,
    grade: dtValue(html, "Grade") ?? "",
    gradedAt: null,
    identity: {
      game: "pokemon",
      language: "en",
      setName: dtValue(html, "Set") ?? "",
      cardName: dtValue(html, "Player") ?? "",
      cardNumber: dtValue(html, "Card Number"),
      variant: dtValue(html, "Variety"),
      year: (() => { const y = dtValue(html, "Year"); return y ? Number(y) : null; })(),
    },
    sourcePayload: { html: html.slice(0, 10_000) },
  };
}
```

- [ ] **Step 5: Run and confirm passing**

- [ ] **Step 6: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/graded/sources/sgc.ts tcgcsv/tests/graded/sources/sgc.test.ts tcgcsv/tests/fixtures/sgc/
git -C /Users/dixoncider/slabbist commit -m "Add SGC source: HTML cert-lookup scraper"
```

---

### Task 22: `graded/sources/tag.ts` — TAG Grading API (with scrape fallback stub)

**Context:** TAG Grading (`taggrading.com`) publishes cert data via a JSON endpoint consumed by their frontend. If their `TAG_API_KEY` is present, use the authenticated API; otherwise use the unauthenticated lookup JSON that the public cert page consumes. This task uses the JSON path.

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/graded/sources/tag.ts`
- Create: `/Users/dixoncider/slabbist/tcgcsv/tests/fixtures/tag/cert-lookup.json`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/graded/sources/tag.test.ts`

- [ ] **Step 1: Create fixture**

`tests/fixtures/tag/cert-lookup.json`:

```json
{
  "cert": {
    "certId": "TAG123456",
    "grade": "10",
    "game": "Pokémon",
    "setName": "Sword & Shield Brilliant Stars",
    "year": 2022,
    "cardName": "Charizard VSTAR",
    "cardNumber": "174",
    "variant": "Rainbow Rare",
    "language": "English",
    "gradedOn": "2025-12-02"
  }
}
```

- [ ] **Step 2: Write failing test**

```ts
// tests/graded/sources/tag.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { tagCertLookup } from "@/graded/sources/tag.js";

const F = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/tag");
const mockOkJson = (body: unknown) => vi.fn().mockResolvedValue(
  new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } }),
);

describe("tag source", () => {
  beforeEach(() => vi.restoreAllMocks());

  it("tagCertLookup normalizes the cert JSON", async () => {
    const fixture = JSON.parse(readFileSync(join(F, "cert-lookup.json"), "utf8"));
    vi.stubGlobal("fetch", mockOkJson(fixture));
    const rec = await tagCertLookup("TAG123456", { userAgent: "t" });
    expect(rec.gradingService).toBe("TAG");
    expect(rec.grade).toBe("10");
    expect(rec.identity.cardName).toBe("Charizard VSTAR");
    expect(rec.identity.setName).toBe("Sword & Shield Brilliant Stars");
    expect(rec.identity.cardNumber).toBe("174");
    expect(rec.identity.variant).toBe("Rainbow Rare");
    expect(rec.identity.year).toBe(2022);
    expect(rec.identity.language).toBe("en");
  });
});
```

- [ ] **Step 3: Run and confirm failure**

- [ ] **Step 4: Implement**

```ts
// src/graded/sources/tag.ts
import { z } from "zod";
import { httpJson } from "@/shared/http/fetch.js";
import type { GradedCertRecord } from "@/graded/models.js";

const TAG_BASE = "https://api.taggrading.com/v1/cert";

const CertResponse = z.object({
  cert: z.object({
    certId: z.string(),
    grade: z.string(),
    game: z.string(),
    setName: z.string(),
    year: z.number().nullable().optional(),
    cardName: z.string(),
    cardNumber: z.string().nullable().optional(),
    variant: z.string().nullable().optional(),
    language: z.string().nullable().optional(),
    gradedOn: z.string().nullable().optional(),
  }),
});

export interface TagOpts { userAgent: string; apiKey?: string; }

export async function tagCertLookup(certNumber: string, opts: TagOpts): Promise<GradedCertRecord> {
  const body = await httpJson(`${TAG_BASE}/${encodeURIComponent(certNumber)}`, {
    userAgent: opts.userAgent,
    headers: opts.apiKey ? { Authorization: `Bearer ${opts.apiKey}` } : {},
  });
  const parsed = CertResponse.parse(body).cert;
  return {
    gradingService: "TAG",
    certNumber: parsed.certId,
    grade: parsed.grade,
    gradedAt: parsed.gradedOn ?? null,
    identity: {
      game: "pokemon",
      language: (parsed.language ?? "").toLowerCase().startsWith("jap") ? "jp" : "en",
      setName: parsed.setName,
      cardName: parsed.cardName,
      cardNumber: parsed.cardNumber ?? null,
      variant: parsed.variant ?? null,
      year: parsed.year ?? null,
    },
    sourcePayload: body,
  };
}
```

- [ ] **Step 5: Run and confirm passing**

- [ ] **Step 6: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/graded/sources/tag.ts tcgcsv/tests/graded/sources/tag.test.ts tcgcsv/tests/fixtures/tag/
git -C /Users/dixoncider/slabbist commit -m "Add TAG Grading source: JSON cert lookup"
```

---

### Task 23: `graded/sources/ebay.ts` — Browse API + sold-items fallback

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/graded/sources/ebay.ts`
- Create: `/Users/dixoncider/slabbist/tcgcsv/tests/fixtures/ebay/browse-sold-sample.json`
- Create: `/Users/dixoncider/slabbist/tcgcsv/tests/fixtures/ebay/sold-items-page.html`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/graded/sources/ebay.test.ts`

- [ ] **Step 1: Create fixtures**

`tests/fixtures/ebay/browse-sold-sample.json` (shape modeled on Marketplace Insights `item_sales` response):

```json
{
  "itemSales": [
    {
      "itemId": "v1|115512345678|0",
      "title": "1999 Pokemon Base Set Charizard Holo #4 PSA 10 GEM MINT",
      "lastSoldDate": "2026-04-20T17:23:00Z",
      "lastSoldPrice": { "value": "5800.00", "currency": "USD" },
      "itemWebUrl": "https://www.ebay.com/itm/115512345678"
    },
    {
      "itemId": "v1|115500000001|0",
      "title": "Pikachu Promo BGS 9.5 Gem Mint",
      "lastSoldDate": "2026-04-19T11:00:00Z",
      "lastSoldPrice": { "value": "120.00", "currency": "USD" },
      "itemWebUrl": "https://www.ebay.com/itm/115500000001"
    }
  ]
}
```

`tests/fixtures/ebay/sold-items-page.html` — minimal snippet mimicking eBay sold-items search result structure (engineer should replace with a real saved page):

```html
<ul class="srp-results">
  <li class="s-item"><div class="s-item__title">1999 Pokemon Base Set Charizard Holo #4 PSA 10</div><span class="s-item__price">$5,800.00</span><a class="s-item__link" href="https://www.ebay.com/itm/115512345678"></a><span class="s-item__ended-date">Apr 20, 2026</span></li>
  <li class="s-item"><div class="s-item__title">Pikachu Promo BGS 9.5</div><span class="s-item__price">$120.00</span><a class="s-item__link" href="https://www.ebay.com/itm/115500000001"></a><span class="s-item__ended-date">Apr 19, 2026</span></li>
</ul>
```

- [ ] **Step 2: Write failing tests**

```ts
// tests/graded/sources/ebay.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { ebayFetchRecentSoldViaApi, ebayFetchRecentSoldViaScrape } from "@/graded/sources/ebay.js";

const F = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/ebay");
const mockOk = (body: string, headers: Record<string, string> = {}) =>
  vi.fn().mockResolvedValue(new Response(body, { status: 200, headers }));

describe("ebay source", () => {
  beforeEach(() => vi.restoreAllMocks());

  it("api path: normalizes Marketplace Insights sold items", async () => {
    vi.stubGlobal("fetch", mockOk(readFileSync(join(F, "browse-sold-sample.json"), "utf8"), { "content-type": "application/json" }));
    const sales = await ebayFetchRecentSoldViaApi(`PSA 10 pokemon`, { token: "t", userAgent: "t" });
    expect(sales).toHaveLength(2);
    expect(sales[0]!.soldPrice).toBe(5800);
    expect(sales[0]!.title).toContain("Charizard");
    expect(sales[0]!.source).toBe("ebay");
    expect(sales[0]!.sourceListingId).toBe("115512345678");
  });

  it("scrape path: parses sold-items HTML", async () => {
    vi.stubGlobal("fetch", mockOk(readFileSync(join(F, "sold-items-page.html"), "utf8")));
    const sales = await ebayFetchRecentSoldViaScrape(`"PSA 10" pokemon`, { userAgent: "t" });
    expect(sales.length).toBeGreaterThanOrEqual(2);
    expect(sales.find((s) => s.title.includes("Charizard"))?.soldPrice).toBe(5800);
  });
});
```

- [ ] **Step 3: Run and confirm failure**

- [ ] **Step 4: Implement**

```ts
// src/graded/sources/ebay.ts
import { z } from "zod";
import { httpJson, httpText } from "@/shared/http/fetch.js";
import type { GradedSale } from "@/graded/models.js";
import { parseGradedTitle } from "@/graded/cert-parser.js";

const MARKETPLACE_INSIGHTS = "https://api.ebay.com/buy/marketplace_insights/v1_beta/item_sales/search";
const SOLD_SEARCH_BASE = "https://www.ebay.com/sch/i.html";

const ApiResponse = z.object({
  itemSales: z.array(z.object({
    itemId: z.string(),
    title: z.string(),
    lastSoldDate: z.string(),
    lastSoldPrice: z.object({ value: z.string(), currency: z.string() }),
    itemWebUrl: z.string(),
  })).optional().default([]),
});

export interface EbayApiOpts { token: string; userAgent: string; }
export interface EbayScrapeOpts { userAgent: string; }

function listingIdFromItemId(itemId: string): string {
  // itemId e.g. "v1|115512345678|0" -> "115512345678"
  const parts = itemId.split("|");
  return parts[1] ?? itemId;
}

function toGradedSale(title: string, price: number, soldAt: string, url: string, listingId: string): GradedSale | null {
  const parsed = parseGradedTitle(title);
  if (!parsed) return null;
  return {
    gradingService: parsed.gradingService,
    grade: parsed.grade,
    certNumber: parsed.certNumber,
    source: "ebay",
    sourceListingId: listingId,
    soldPrice: price,
    soldAt,
    title,
    url,
    identity: {
      // Identity fields from eBay titles are best-effort; normalization happens in the ingest worker.
      // Leave as title-derived hints; downstream normalizeIdentityKey handles them.
      game: "pokemon",
      language: /日本|ポケモン|JP\b|Japanese/i.test(title) ? "jp" : "en",
      setName: title,              // placeholder — ingest worker refines
      cardName: title,
      cardNumber: null,
      variant: null,
    },
  };
}

export async function ebayFetchRecentSoldViaApi(query: string, opts: EbayApiOpts): Promise<GradedSale[]> {
  const url = `${MARKETPLACE_INSIGHTS}?q=${encodeURIComponent(query)}&limit=200`;
  const body = await httpJson(url, {
    userAgent: opts.userAgent,
    headers: { Authorization: `Bearer ${opts.token}`, "X-EBAY-C-MARKETPLACE-ID": "EBAY_US" },
  });
  const parsed = ApiResponse.parse(body);
  const sales: GradedSale[] = [];
  for (const it of parsed.itemSales) {
    const price = Number(it.lastSoldPrice.value);
    if (!Number.isFinite(price)) continue;
    const sale = toGradedSale(it.title, price, it.lastSoldDate, it.itemWebUrl, listingIdFromItemId(it.itemId));
    if (sale) sales.push(sale);
  }
  return sales;
}

// Minimal regex-based parse of sold-items search HTML. Good enough for fixture tests and
// best-effort production scraping. Will need maintenance when eBay markup changes.
export async function ebayFetchRecentSoldViaScrape(query: string, opts: EbayScrapeOpts): Promise<GradedSale[]> {
  const url = `${SOLD_SEARCH_BASE}?_nkw=${encodeURIComponent(query)}&LH_Sold=1&LH_Complete=1&_sop=13`;
  const html = await httpText(url, { userAgent: opts.userAgent });
  const itemRe = /<li class="s-item">([\s\S]*?)<\/li>/g;
  const titleRe = /class="s-item__title">([^<]+)</;
  const priceRe = /class="s-item__price">\$?([0-9,]+(?:\.[0-9]+)?)/;
  const linkRe = /class="s-item__link" href="([^"]+)"/;
  const dateRe = /class="s-item__ended-date">([^<]+)</;

  const sales: GradedSale[] = [];
  let m: RegExpExecArray | null;
  while ((m = itemRe.exec(html))) {
    const chunk = m[1]!;
    const title = chunk.match(titleRe)?.[1] ?? null;
    const priceStr = chunk.match(priceRe)?.[1] ?? null;
    const link = chunk.match(linkRe)?.[1] ?? null;
    const dateStr = chunk.match(dateRe)?.[1] ?? null;
    if (!title || !priceStr || !link) continue;
    const price = Number(priceStr.replace(/,/g, ""));
    if (!Number.isFinite(price)) continue;
    const soldAt = dateStr ? new Date(dateStr).toISOString() : new Date().toISOString();
    const listingId = link.match(/\/itm\/(?:[^/]+\/)?(\d+)/)?.[1] ?? link;
    const sale = toGradedSale(title, price, soldAt, link, listingId);
    if (sale) sales.push(sale);
  }
  return sales;
}
```

- [ ] **Step 5: Run and confirm passing**

- [ ] **Step 6: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/graded/sources/ebay.ts tcgcsv/tests/graded/sources/ebay.test.ts tcgcsv/tests/fixtures/ebay/
git -C /Users/dixoncider/slabbist commit -m "Add eBay source: Marketplace Insights API + sold-search scrape fallback"
```

---

## Phase 7 — Graded ingest workers

### Task 24: `graded/ingest/pop-reports.ts` — weekly fan-out across services

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/graded/ingest/pop-reports.ts`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/graded/ingest/pop-reports.test.ts`

- [ ] **Step 1: Write failing integration-style test**

```ts
// tests/graded/ingest/pop-reports.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { runPopReportIngest } from "@/graded/ingest/pop-reports.js";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const F = (...p: string[]) => join(dirname(fileURLToPath(import.meta.url)), "../../fixtures", ...p);

// Reuse the fake-supabase helper from raw/ingest.test.ts (copy-paste it into a shared test-utils file in a real implementation).
// For plan brevity, imagine `makeFakeSupabase()` imported from `tests/_helpers/fake-supabase.ts`.
import { makeFakeSupabase } from "../../_helpers/fake-supabase.js";

describe("runPopReportIngest", () => {
  beforeEach(() => vi.restoreAllMocks());

  it("writes pop rows from PSA fixture and records a completed run", async () => {
    const psaPop = JSON.parse(readFileSync(F("psa/pop-report-sample.json"), "utf8"));
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
      new Response(JSON.stringify(psaPop), { status: 200, headers: { "content-type": "application/json" } }),
    ));

    const supa = makeFakeSupabase() as any;
    const result = await runPopReportIngest({
      supabase: supa,
      userAgent: "t",
      services: ["psa"],
      psa: { apiKey: "k", specIds: [123456] },
    });

    expect(result.status).toBe("completed");
    const pops = await supa._debug.pool.query("select * from public.graded_card_pops");
    expect(pops.rows.length).toBe(3);
  });
});
```

- [ ] **Step 2: Write the `tests/_helpers/fake-supabase.ts` helper** (extract the fake used in the raw ingest test into its own module for reuse)

```ts
// tests/_helpers/fake-supabase.ts
// Copy the makeFakeSupabase implementation from the inline version in tests/raw/ingest.test.ts
// and move it here; update tests/raw/ingest.test.ts to import from this module.
// (See Task 13 for the body of makeFakeSupabase.)
```

- [ ] **Step 3: Run and confirm failure**

- [ ] **Step 4: Implement worker**

```ts
// src/graded/ingest/pop-reports.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, PopRow } from "@/graded/models.js";
import { findOrCreateIdentity } from "@/graded/identity.js";
import { psaPopReport } from "@/graded/sources/psa.js";
// import { cgcPopReport } from "@/graded/sources/cgc.js"; etc — implemented in Tasks 19-22.

export interface PopIngestOptions {
  supabase: SupabaseClient;
  userAgent: string;
  services: GradingService[] | Array<"psa" | "cgc" | "bgs" | "sgc" | "tag">;
  psa?: { apiKey: string; specIds: number[] };
  // Similar opts hooks for other services; omitted here for brevity.
}

export interface PopIngestResult {
  runId: string;
  status: "completed" | "failed";
  stats: Record<string, number>;
  errorMessage?: string;
}

export async function runPopReportIngest(opts: PopIngestOptions): Promise<PopIngestResult> {
  const runId = crypto.randomUUID();
  await opts.supabase.from("graded_ingest_runs").insert({
    id: runId, source: "pop", status: "running", started_at: new Date().toISOString(), stats: {},
  });
  const stats: Record<string, number> = {};
  try {
    const all: PopRow[] = [];
    for (const s of opts.services) {
      const svc = String(s).toLowerCase();
      if (svc === "psa" && opts.psa) {
        for (const specId of opts.psa.specIds) {
          const rows = await psaPopReport(specId, { apiKey: opts.psa.apiKey, userAgent: opts.userAgent });
          all.push(...rows);
          stats["psa"] = (stats["psa"] ?? 0) + rows.length;
        }
      }
      // Other services: same pattern, gated on opts.<svc> being configured.
    }

    for (const row of all) {
      const identityId = await findOrCreateIdentity(opts.supabase, row.identity);
      await opts.supabase.from("graded_card_pops").insert({
        identity_id: identityId, grading_service: row.gradingService, grade: row.grade,
        population: row.population, captured_at: new Date().toISOString(),
      });
    }

    await opts.supabase.from("graded_ingest_runs").update({
      status: "completed", finished_at: new Date().toISOString(), stats,
    }).eq("id", runId);
    return { runId, status: "completed", stats };
  } catch (e) {
    const msg = String((e as Error).message ?? e);
    await opts.supabase.from("graded_ingest_runs").update({
      status: "failed", finished_at: new Date().toISOString(), error_message: msg, stats,
    }).eq("id", runId);
    return { runId, status: "failed", stats, errorMessage: msg };
  }
}
```

- [ ] **Step 5: Run and confirm passing**

- [ ] **Step 6: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/graded/ingest/pop-reports.ts tcgcsv/tests/graded/ingest/pop-reports.test.ts tcgcsv/tests/_helpers/fake-supabase.ts
git -C /Users/dixoncider/slabbist commit -m "Add weekly pop-report ingest worker"
```

---

### Task 25: `graded/ingest/ebay-sold.ts` — hourly eBay sold ingest

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/graded/ingest/ebay-sold.ts`
- Test: `/Users/dixoncider/slabbist/tcgcsv/tests/graded/ingest/ebay-sold.test.ts`

- [ ] **Step 1: Write failing test**

```ts
// tests/graded/ingest/ebay-sold.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { runEbaySoldIngest } from "@/graded/ingest/ebay-sold.js";
import { makeFakeSupabase } from "../../_helpers/fake-supabase.js";

const F = (...p: string[]) => join(dirname(fileURLToPath(import.meta.url)), "../../fixtures", ...p);

describe("runEbaySoldIngest", () => {
  beforeEach(() => vi.restoreAllMocks());

  it("ingests sold listings from scrape fixture, creates identities, upserts sales + aggregates", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
      new Response(readFileSync(F("ebay/sold-items-page.html"), "utf8"), { status: 200 }),
    ));

    const supa = makeFakeSupabase() as any;
    const res = await runEbaySoldIngest({
      supabase: supa, userAgent: "t",
      queries: [`"PSA 10" pokemon`, `"BGS 9.5" pokemon`],
      marketplaceInsightsToken: undefined,  // scrape path
    });

    expect(res.status).toBe("completed");

    const sales = await supa._debug.pool.query("select * from public.graded_market_sales");
    expect(sales.rows.length).toBeGreaterThanOrEqual(2);

    const market = await supa._debug.pool.query("select * from public.graded_market");
    expect(market.rows.length).toBeGreaterThanOrEqual(1);
  });
});
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement worker**

```ts
// src/graded/ingest/ebay-sold.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradedSale } from "@/graded/models.js";
import { findOrCreateIdentity } from "@/graded/identity.js";
import { computeMarketAggregate } from "@/graded/aggregates.js";
import { ebayFetchRecentSoldViaApi, ebayFetchRecentSoldViaScrape } from "@/graded/sources/ebay.js";

export interface EbayIngestOptions {
  supabase: SupabaseClient;
  userAgent: string;
  queries: string[];
  marketplaceInsightsToken?: string;
}

export interface EbayIngestResult {
  runId: string;
  status: "completed" | "failed";
  stats: { salesInserted: number; aggregatesTouched: number };
  errorMessage?: string;
}

function simpleIdentityFromTitle(title: string, language: "en" | "jp") {
  // Placeholder: title-as-identity. A future iteration can map to a cleaner set/card
  // identity using a dictionary + fuzzy matching; for MVP we bucket by the raw title.
  return {
    game: "pokemon" as const,
    language,
    setName: title,
    cardName: title,
    cardNumber: null,
    variant: null,
  };
}

export async function runEbaySoldIngest(opts: EbayIngestOptions): Promise<EbayIngestResult> {
  const runId = crypto.randomUUID();
  await opts.supabase.from("graded_ingest_runs").insert({
    id: runId, source: "ebay", status: "running", started_at: new Date().toISOString(), stats: {},
  });

  let salesInserted = 0;
  const touchedKeys = new Set<string>();

  try {
    const allSales: GradedSale[] = [];
    for (const q of opts.queries) {
      const batch = opts.marketplaceInsightsToken
        ? await ebayFetchRecentSoldViaApi(q, { token: opts.marketplaceInsightsToken, userAgent: opts.userAgent })
        : await ebayFetchRecentSoldViaScrape(q, { userAgent: opts.userAgent });
      allSales.push(...batch);
    }

    // Persist raw sales.
    for (const s of allSales) {
      const identity = simpleIdentityFromTitle(s.title, s.identity.language);
      const identityId = await findOrCreateIdentity(opts.supabase, identity);
      const { error } = await opts.supabase.from("graded_market_sales").upsert(
        [{
          identity_id: identityId,
          grading_service: s.gradingService, grade: s.grade,
          source: s.source, source_listing_id: s.sourceListingId,
          sold_price: s.soldPrice, sold_at: s.soldAt,
          title: s.title, url: s.url, captured_at: new Date().toISOString(),
        }],
        { onConflict: "source,source_listing_id" },
      );
      if (!error) {
        salesInserted += 1;
        touchedKeys.add(`${identityId}|${s.gradingService}|${s.grade}`);

        // Opportunistic: if the title had a cert number, create a graded_cards row.
        if (s.certNumber) {
          await opts.supabase.from("graded_cards").upsert(
            [{
              identity_id: identityId, grading_service: s.gradingService,
              cert_number: s.certNumber, grade: s.grade,
            }],
            { onConflict: "grading_service,cert_number" },
          );
        }
      }
    }

    // Recompute aggregates for touched keys.
    for (const key of touchedKeys) {
      const [identityId, service, grade] = key.split("|");
      const { data } = await opts.supabase
        .from("graded_market_sales")
        .select("sold_price, sold_at, identity_id, grading_service, grade")
        .eq("identity_id", identityId!);
      const sales = ((data ?? []) as Array<Record<string, unknown>>).filter(
        (r) => r.grading_service === service && r.grade === grade,
      );
      const agg = computeMarketAggregate(sales.map((r) => ({
        sold_price: Number(r.sold_price), sold_at: String(r.sold_at),
      })));
      await opts.supabase.from("graded_market").upsert(
        [{
          identity_id: identityId, grading_service: service, grade,
          low_price: agg.lowPrice, median_price: agg.medianPrice, high_price: agg.highPrice,
          last_sale_price: agg.lastSalePrice, last_sale_at: agg.lastSaleAt,
          sample_count_30d: agg.sampleCount30d, sample_count_90d: agg.sampleCount90d,
          updated_at: new Date().toISOString(),
        }],
        { onConflict: "identity_id,grading_service,grade" },
      );
    }

    await opts.supabase.from("graded_ingest_runs").update({
      status: "completed", finished_at: new Date().toISOString(),
      stats: { salesInserted, aggregatesTouched: touchedKeys.size },
    }).eq("id", runId);

    return { runId, status: "completed", stats: { salesInserted, aggregatesTouched: touchedKeys.size } };
  } catch (e) {
    const msg = String((e as Error).message ?? e);
    await opts.supabase.from("graded_ingest_runs").update({
      status: "failed", finished_at: new Date().toISOString(), error_message: msg,
      stats: { salesInserted, aggregatesTouched: touchedKeys.size },
    }).eq("id", runId);
    return { runId, status: "failed", stats: { salesInserted, aggregatesTouched: touchedKeys.size }, errorMessage: msg };
  }
}
```

- [ ] **Step 4: Run and confirm passing**

- [ ] **Step 5: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/graded/ingest/ebay-sold.ts tcgcsv/tests/graded/ingest/ebay-sold.test.ts
git -C /Users/dixoncider/slabbist commit -m "Add hourly eBay sold-listings ingest worker"
```

---

## Phase 8 — CLI

### Task 26: `src/cli.ts` — Commander-based CLI wiring

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/src/cli.ts`

(No unit test — CLI is a thin shim over already-tested workers.)

- [ ] **Step 1: Implement**

```ts
// src/cli.ts
import { Command } from "commander";
import { loadConfig } from "@/shared/config.js";
import { createLogger } from "@/shared/logger.js";
import { getSupabase } from "@/shared/db/supabase.js";
import { ingestPokemonAllCategories } from "@/raw/ingest.js";
import { runPopReportIngest } from "@/graded/ingest/pop-reports.js";
import { runEbaySoldIngest } from "@/graded/ingest/ebay-sold.js";

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
    });
    for (const r of results) log.info("run complete", { ...r });
    if (results.some((r) => r.status === "failed")) process.exit(1);
  });

run.command("graded")
  .argument("<job>", "job: ebay | pop")
  .option("-s, --service <svc>", "pop: which services (comma-separated or 'all')", "all")
  .option("-q, --queries <list>", "ebay: comma-separated search queries",
    `"PSA 10" pokemon,"PSA 9" pokemon,"BGS 9.5" pokemon,"BGS 9" pokemon,"CGC 10" pokemon,"CGC 9.5" pokemon,"SGC 10" pokemon,"TAG 10" pokemon`)
  .action(async (job, o) => {
    const cfg = loadConfig();
    const log = createLogger({ level: cfg.runtime.logLevel });
    if (job === "ebay") {
      const res = await runEbaySoldIngest({
        supabase: getSupabase(),
        userAgent: cfg.runtime.userAgent,
        queries: String(o.queries).split(",").map((s) => s.trim()).filter(Boolean),
        marketplaceInsightsToken: cfg.ebay.marketplaceInsightsApproved
          ? process.env.EBAY_OAUTH_TOKEN ?? undefined
          : undefined,
      });
      log.info("ebay ingest complete", { ...res });
      if (res.status === "failed") process.exit(1);
      return;
    }
    if (job === "pop") {
      const services = o.service === "all"
        ? ["psa", "cgc", "bgs", "sgc", "tag"]
        : String(o.service).split(",").map((s) => s.trim().toLowerCase());
      const res = await runPopReportIngest({
        supabase: getSupabase(),
        userAgent: cfg.runtime.userAgent,
        services: services as Array<"psa" | "cgc" | "bgs" | "sgc" | "tag">,
        psa: cfg.grading.psaApiKey ? { apiKey: cfg.grading.psaApiKey, specIds: [] } : undefined,
      });
      log.info("pop ingest complete", { ...res });
      if (res.status === "failed") process.exit(1);
      return;
    }
    log.error("unknown graded job", { job });
    process.exit(2);
  });

program.parseAsync(process.argv);
```

- [ ] **Step 2: Verify CLI loads without crashing**

```bash
bun run cli --help
```

Expected: commander prints the help message with `run raw` and `run graded` subcommands; exit 0.

- [ ] **Step 3: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/src/cli.ts
git -C /Users/dixoncider/slabbist commit -m "Add Commander CLI wiring"
```

---

## Phase 9 — GitHub Actions + README polish

### Task 27: GitHub Actions workflows

**Files:**
- Create: `/Users/dixoncider/slabbist/tcgcsv/.github/workflows/ci.yml`
- Create: `/Users/dixoncider/slabbist/tcgcsv/.github/workflows/ingest-raw-tcgcsv.yml`
- Create: `/Users/dixoncider/slabbist/tcgcsv/.github/workflows/ingest-graded-ebay.yml`
- Create: `/Users/dixoncider/slabbist/tcgcsv/.github/workflows/ingest-graded-pop.yml`

- [ ] **Step 1: Create `ci.yml`**

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
permissions: { contents: read }
jobs:
  checks:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: tcgcsv } }
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
        with: { bun-version: latest }
      - run: bun install --frozen-lockfile
      - run: bun run typecheck
      - run: bun run test
```

- [ ] **Step 2: Create `ingest-raw-tcgcsv.yml` — daily at 06:00 UTC**

```yaml
name: Ingest raw (tcgcsv)
on:
  schedule: [{ cron: "0 6 * * *" }]
  workflow_dispatch:
permissions: { contents: read }
jobs:
  ingest:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: tcgcsv } }
    env:
      SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
      SUPABASE_SERVICE_ROLE_KEY: ${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
        with: { bun-version: latest }
      - run: bun install --frozen-lockfile
      - run: bun run cli run raw tcgcsv
```

- [ ] **Step 3: Create `ingest-graded-ebay.yml` — hourly**

```yaml
name: Ingest graded (eBay sold)
on:
  schedule: [{ cron: "0 * * * *" }]
  workflow_dispatch:
permissions: { contents: read }
jobs:
  ingest:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: tcgcsv } }
    env:
      SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
      SUPABASE_SERVICE_ROLE_KEY: ${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}
      EBAY_APP_ID: ${{ secrets.EBAY_APP_ID }}
      EBAY_CERT_ID: ${{ secrets.EBAY_CERT_ID }}
      EBAY_DEV_ID: ${{ secrets.EBAY_DEV_ID }}
      EBAY_MARKETPLACE_INSIGHTS_APPROVED: ${{ vars.EBAY_MARKETPLACE_INSIGHTS_APPROVED }}
      EBAY_OAUTH_TOKEN: ${{ secrets.EBAY_OAUTH_TOKEN }}
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
        with: { bun-version: latest }
      - run: bun install --frozen-lockfile
      - run: bun run cli run graded ebay
```

- [ ] **Step 4: Create `ingest-graded-pop.yml` — weekly Sunday 12:00 UTC**

```yaml
name: Ingest graded (pop reports)
on:
  schedule: [{ cron: "0 12 * * 0" }]
  workflow_dispatch:
permissions: { contents: read }
jobs:
  ingest:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: tcgcsv } }
    env:
      SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
      SUPABASE_SERVICE_ROLE_KEY: ${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}
      PSA_API_KEY: ${{ secrets.PSA_API_KEY }}
      BECKETT_OPG_KEY: ${{ secrets.BECKETT_OPG_KEY }}
      TAG_API_KEY: ${{ secrets.TAG_API_KEY }}
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
        with: { bun-version: latest }
      - run: bun install --frozen-lockfile
      - run: bun run cli run graded pop
```

- [ ] **Step 5: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/.github/workflows/
git -C /Users/dixoncider/slabbist commit -m "Add CI + 3 scheduled ingest workflows"
```

---

### Task 28: Expand README with runbook details

**Files:**
- Modify: `/Users/dixoncider/slabbist/tcgcsv/README.md`

- [ ] **Step 1: Expand README**

```markdown
# @slabbist/tcgcsv

Ingestion-only pipeline that populates the Slabbist monorepo's Supabase DB with:
- **Raw** Pokémon catalog & pricing from tcgcsv.com (categories 3 English, 85 Japanese)
- **Graded** card data from PSA / CGC / BGS / SGC / TAG + eBay sold listings

Raw and graded domains are architecturally decoupled. Consumers (iOS, website) read Supabase directly.

See the design spec: `docs/superpowers/specs/2026-04-22-tcgcsv-pokemon-graded-design.md`.

## Quick start

```bash
bun install
cp .env.example .env    # fill in credentials
bun run typecheck
bun run test
```

## CLI

```bash
bun run cli run raw tcgcsv                    # daily tcgcsv refresh (cat 3 + 85)
bun run cli run graded ebay                   # hourly eBay sold listings
bun run cli run graded pop -s psa             # weekly pop report (one service)
bun run cli run graded pop -s all             # weekly pop report (all services)
```

Flags:
- `-c, --concurrency <n>`  — concurrent group requests (default 3; raw only)
- `-d, --delay-ms <ms>`    — per-start delay between groups (default 200; raw only)
- `-q, --queries <list>`   — comma-separated eBay queries (graded ebay only)

## Scheduled jobs (GitHub Actions)

| Workflow                           | Cron             | What it runs                 |
|------------------------------------|------------------|------------------------------|
| `ingest-raw-tcgcsv.yml`            | `0 6 * * *`      | `run raw tcgcsv`             |
| `ingest-graded-ebay.yml`           | `0 * * * *`      | `run graded ebay`            |
| `ingest-graded-pop.yml`            | `0 12 * * 0`     | `run graded pop -s all`      |
| `ci.yml`                           | push/PR          | `typecheck` + `test`         |

Each cron workflow pulls secrets from GitHub repo secrets. See `.env.example` for the full list.

## Schema

Tables are defined in the monorepo-shared migration at:
`/Users/dixoncider/slabbist/supabase/migrations/20260422120000_tcgcsv_pokemon_and_graded.sql`

This repo never defines schema locally.

## Observability

- Every ingest writes a row to `tcg_scrape_runs` (raw) or `graded_ingest_runs` (graded) with start/end times, counters, and error messages.
- Failures surface via GH Actions workflow failure emails.
- Structured JSON logs go to stdout for the workflow run page.

## Developing a new source

1. Add a module under `src/<domain>/sources/<name>.ts` that exports pure fetchers returning normalized models. Validate responses with zod.
2. Add a fixture under `tests/fixtures/<name>/` that reflects a real response shape.
3. Add a unit test that stubs `fetch` against the fixture and asserts normalization output.
4. Wire the source into the appropriate domain ingest (`src/raw/ingest.ts` or `src/graded/ingest/*.ts`).
5. If the source contributes to a new scheduled cadence, add a `.github/workflows/ingest-<source>.yml` cron workflow.

## Known open items

- Grading-service credentials: PSA/BGS/TAG may be API-gated — sources without keys fall back to HTML scraping via `httpText()`.
- eBay Marketplace Insights API requires approval — scraping `ebay.com/sch` sold-items pages is used until approved.
- Migration-naming convention established by this migration (`YYYYMMDDHHMMSS_<description>.sql`); re-align if the monorepo's Supabase CLI config dictates otherwise.
```

- [ ] **Step 2: Commit**

```bash
git -C /Users/dixoncider/slabbist add tcgcsv/README.md
git -C /Users/dixoncider/slabbist commit -m "Expand README with runbook and source-authoring guide"
```

---

## Self-review checklist (for the implementer)

Before calling this plan complete, verify:

- [ ] `bun run typecheck` passes with no errors
- [ ] `bun run test` passes with all tests green
- [ ] A manual `bun run cli run raw tcgcsv` against a local/dev Supabase populates `tcg_products` and `tcg_prices` for a small sample (use `--concurrency 1` to go light) — record outcome in the run row
- [ ] `graded/sources/*.ts` modules for CGC/BGS/SGC/TAG have fixture-backed tests even if the fixture is stubbed against best-guess shapes — revisit when real access is obtained
- [ ] `.github/workflows/ci.yml` runs typecheck + test on PRs
- [ ] Migration applies cleanly against a fresh Supabase local instance
