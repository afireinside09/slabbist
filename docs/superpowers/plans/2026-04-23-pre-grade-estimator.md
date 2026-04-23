# Pre-grade Estimator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a side-quest pre-grade estimator that takes a front + back photo of a raw card and returns a hyper-critical, sub-grade-by-sub-grade PSA-style report with composite grade, verdict, and explanations anchored to visible features.

**Architecture:** Hybrid CV + LLM. iOS measures centering on-device with `VNDetectRectanglesRequest` + a quality gate (blur, glare, resolution, card-detected). Photos are uploaded to a per-user Supabase Storage bucket. A new `/grade-estimate` Edge Function calls Claude Sonnet 4.6 vision with the images and the measured ratios as ground truth, validates a strict JSON schema, and persists to a new `grade_estimates` table. iOS renders the persisted row in a report screen and lists past reports in a history screen. Designed so sub-project 9 (raw card scanning) can later attach reports to scans inside a lot via a nullable `scan_id` FK.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / `Vision` / `AVFoundation`, Swift Testing (`@Suite`/`@Test`/`#expect`), Supabase Postgres + Storage + Edge Functions (Deno/TypeScript), Anthropic Messages API (Claude Sonnet 4.6 vision), pg_cron for scheduled purge.

**Spec:** [`docs/superpowers/specs/2026-04-23-pre-grade-estimator-design.md`](../specs/2026-04-23-pre-grade-estimator-design.md)

---

## File Structure

### Database (Supabase)
- Create: `supabase/migrations/<timestamp>_grade_estimates.sql` — table, indexes, RLS, bucket, purge function + cron schedule.

### Edge Function (first one in this repo)
- Create: `supabase/functions/_shared/cors.ts` — CORS preflight helper (also reused by future functions).
- Create: `supabase/functions/_shared/anthropic.ts` — minimal Anthropic Messages client (POST `https://api.anthropic.com/v1/messages`, vision-capable).
- Create: `supabase/functions/_shared/supabase.ts` — service-role client factory.
- Create: `supabase/functions/grade-estimate/index.ts` — handler (auth, rate-limit, signed URLs, Anthropic call, schema validation, persist).
- Create: `supabase/functions/grade-estimate/prompt.ts` — system prompt + user prompt builders + JSON schema.
- Create: `supabase/functions/grade-estimate/types.ts` — TS types for input/output.
- Create: `supabase/functions/grade-estimate/index.test.ts` — Deno tests with mocked Anthropic.

### iOS Vision primitives (Core/Vision)
- Create: `ios/slabbist/slabbist/Core/Vision/CardRectangleDetector.swift`
- Create: `ios/slabbist/slabbist/Core/Vision/CenteringMeasurement.swift`
- Create: `ios/slabbist/slabbist/Core/Vision/CaptureQualityGate.swift`
- Create: `ios/slabbist/slabbist/Core/Vision/StillImageCapture.swift` — wraps `AVCapturePhotoOutput` (the existing `CameraSession` is video-only).

### iOS data layer (Core/Data)
- Create: `ios/slabbist/slabbist/Core/Data/DTOs/GradeEstimateDTO.swift`
- Create: `ios/slabbist/slabbist/Core/Data/Repositories/GradeEstimateRepository.swift`
- Create: `ios/slabbist/slabbist/Core/Data/Repositories/GradePhotoUploader.swift` — handles two uploads + thumbnail generation.
- Modify: `ios/slabbist/slabbist/Core/Data/Repositories/RepositoryProtocols.swift` — add `GradeEstimateRepository` protocol + add to `AppRepositories`.

### iOS feature (Features/Grading)
- Create: `ios/slabbist/slabbist/Features/Grading/Capture/GradingCaptureView.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Capture/GradingCaptureViewModel.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Capture/CardOutlineOverlay.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Capture/QualityChip.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Capture/FirstRunConsentView.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Report/GradeReportView.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Report/SubGradeCard.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Report/VerdictPill.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Report/OtherGradersPanel.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/History/GradeHistoryView.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/History/GradeHistoryViewModel.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/History/GradeHistoryRow.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/GradingTabView.swift` — top-level container (history list + entry to capture).

### iOS shell wiring
- Modify: `ios/slabbist/slabbist/Features/Shell/RootTabView.swift` — add fourth tab "Grade".

### Tests (Swift Testing)
- Create: `ios/slabbist/slabbistTests/Core/Vision/CenteringMeasurementTests.swift`
- Create: `ios/slabbist/slabbistTests/Core/Vision/CaptureQualityGateTests.swift`
- Create: `ios/slabbist/slabbistTests/Core/Vision/CardRectangleDetectorTests.swift`
- Create: `ios/slabbist/slabbistTests/Core/Data/GradeEstimateDTOTests.swift`
- Create: `ios/slabbist/slabbistTests/Features/Grading/GradingCaptureViewModelTests.swift`
- Create: `ios/slabbist/slabbistTests/Features/Grading/GradeHistoryViewModelTests.swift`
- Create: `ios/slabbist/slabbistTests/Resources/GradingFixtures/` — fixture images used by Vision tests (well-centered, off-centered, blurry, glare).

---

## Task 1: Database migration — `grade_estimates` table, indexes, RLS

**Files:**
- Create: `supabase/migrations/20260423130000_grade_estimates.sql`

**Pattern reference:** `supabase/migrations/20260422000004_scan_surface.sql` (table style), `supabase/migrations/20260422000006_rls_policies.sql` (RLS style).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260423130000_grade_estimates.sql`:

```sql
-- Pre-grade estimator: persisted reports per user.
-- Designed so sub-project 9 (raw card scanning) can later attach
-- a report to a specific raw scan via the nullable scan_id FK.

create type grade_verdict as enum (
  'submit_economy',
  'submit_value',
  'submit_express',
  'do_not_submit',
  'borderline_reshoot'
);

create type grade_confidence as enum ('low', 'medium', 'high');

create table grade_estimates (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  scan_id             uuid references scans(id) on delete set null,

  front_image_path    text not null,
  back_image_path     text not null,
  front_thumb_path    text not null,
  back_thumb_path     text not null,
  images_purged_at    timestamptz,

  centering_front     jsonb not null,
  centering_back      jsonb not null,

  sub_grades          jsonb not null,
  sub_grade_notes     jsonb not null,

  composite_grade     numeric(3,1) not null check (composite_grade >= 1 and composite_grade <= 10),
  confidence          grade_confidence not null,
  verdict             grade_verdict not null,
  verdict_reasoning   text not null,

  other_graders       jsonb,
  model_version       text not null,
  is_starred          boolean not null default false,

  created_at          timestamptz not null default now()
);

create index grade_estimates_user_created
  on grade_estimates (user_id, created_at desc);

create index grade_estimates_user_starred
  on grade_estimates (user_id)
  where is_starred;

create index grade_estimates_purge_pending
  on grade_estimates (created_at)
  where images_purged_at is null;

alter table grade_estimates enable row level security;

create policy grade_estimates_select_own
  on grade_estimates for select
  using (user_id = auth.uid());

create policy grade_estimates_update_own
  on grade_estimates for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy grade_estimates_delete_own
  on grade_estimates for delete
  using (user_id = auth.uid());

-- Insert is service-role only (the Edge Function writes the row after
-- validating the LLM response). No user insert policy on purpose.
```

- [ ] **Step 2: Apply locally via Supabase MCP**

Run via Supabase MCP `mcp__supabase__apply_migration` with `name: "grade_estimates"` and the SQL body above. Confirm success. Then `mcp__supabase__list_tables` and verify `grade_estimates` is present with the expected columns.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260423130000_grade_estimates.sql
git commit -m "feat(db): add grade_estimates table for pre-grade estimator"
```

---

## Task 2: Database — Storage bucket + bucket policies

**Files:**
- Create: `supabase/migrations/20260423130100_grade_photos_bucket.sql`

- [ ] **Step 1: Write the bucket migration**

```sql
-- Private storage bucket for pre-grade photos. Per-user prefix:
--   grade-photos/<user_id>/<estimate_id>/{front,back,front_thumb,back_thumb}.jpg

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'grade-photos',
  'grade-photos',
  false,
  10 * 1024 * 1024,                -- 10MB per image
  array['image/jpeg', 'image/png']
);

-- A user can read/upload/delete only objects under their own user_id prefix.
-- Object name shape: <user_id>/<estimate_id>/<file>.jpg
-- (storage.foldername returns the path segments as text[]).
create policy grade_photos_select_own
  on storage.objects for select
  using (
    bucket_id = 'grade-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy grade_photos_insert_own
  on storage.objects for insert
  with check (
    bucket_id = 'grade-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy grade_photos_delete_own
  on storage.objects for delete
  using (
    bucket_id = 'grade-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
```

- [ ] **Step 2: Apply via Supabase MCP**

Apply with `mcp__supabase__apply_migration`, name `grade_photos_bucket`. Confirm success.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260423130100_grade_photos_bucket.sql
git commit -m "feat(db): add grade-photos storage bucket and per-user policies"
```

---

## Task 3: Edge Function — `purge-grade-photos` (scheduled daily)

**Files:**
- Create: `supabase/functions/purge-grade-photos/index.ts`
- Create: `supabase/functions/purge-grade-photos/deno.json`
- Create: `supabase/migrations/20260423130200_purge_grade_photos_schedule.sql`

**Why an Edge Function and not pure SQL:** Deleting from `storage.objects` in SQL only removes the row — the underlying S3 object stays. Full deletion requires the storage API. Supabase Cron schedules call HTTP endpoints (via `pg_net`), so a small function is the correct shape.

- [ ] **Step 1: Write the function**

Create `supabase/functions/purge-grade-photos/index.ts`:

```ts
import { serviceRoleClient } from '../_shared/supabase.ts';

const BATCH_SIZE = 500;
const PURGE_AFTER_DAYS = 30;
const PURGE_SECRET_HEADER = 'x-purge-secret';

Deno.serve(async (req) => {
  // Simple shared-secret guard so only the cron schedule can invoke this.
  const secret = req.headers.get(PURGE_SECRET_HEADER);
  if (secret !== Deno.env.get('PURGE_GRADE_PHOTOS_SECRET')) {
    return new Response('forbidden', { status: 403 });
  }

  const client = serviceRoleClient();
  const cutoff = new Date(Date.now() - PURGE_AFTER_DAYS * 24 * 60 * 60 * 1000).toISOString();

  const { data: rows, error } = await client
    .from('grade_estimates')
    .select('id, front_image_path, back_image_path')
    .is('images_purged_at', null)
    .lt('created_at', cutoff)
    .limit(BATCH_SIZE);

  if (error) {
    console.error('purge: list failed', error);
    return new Response(JSON.stringify({ error: 'list_failed' }), { status: 500 });
  }
  if (!rows || rows.length === 0) {
    return new Response(JSON.stringify({ purged: 0 }), { status: 200 });
  }

  const paths = rows.flatMap((r) => [r.front_image_path, r.back_image_path]);
  const { error: removeErr } = await client.storage.from('grade-photos').remove(paths);
  if (removeErr) {
    console.error('purge: remove failed', removeErr);
    return new Response(JSON.stringify({ error: 'remove_failed' }), { status: 500 });
  }

  const ids = rows.map((r) => r.id);
  const { error: updateErr } = await client
    .from('grade_estimates')
    .update({ images_purged_at: new Date().toISOString() })
    .in('id', ids);
  if (updateErr) {
    console.error('purge: mark failed', updateErr);
    return new Response(JSON.stringify({ error: 'mark_failed' }), { status: 500 });
  }

  return new Response(JSON.stringify({ purged: ids.length }), { status: 200 });
});
```

Create `supabase/functions/purge-grade-photos/deno.json`:

```json
{
  "imports": {
    "@supabase/supabase-js": "https://esm.sh/@supabase/supabase-js@2.45.0"
  }
}
```

- [ ] **Step 2: Set the shared secret**

Set `PURGE_GRADE_PHOTOS_SECRET` to a freshly generated random string in the Supabase function-secrets dashboard. Confirm with the user before pasting any secret value. The cron schedule (Step 3) needs the same value.

- [ ] **Step 3: Write the cron schedule migration**

Create `supabase/migrations/20260423130200_purge_grade_photos_schedule.sql`:

```sql
-- Daily Cron job that calls the purge-grade-photos Edge Function.
-- Uses pg_net to issue the HTTP request. The shared secret is stored
-- in Supabase Vault and referenced by name.

-- Ensure pg_net is enabled (no-op if already installed).
create extension if not exists pg_net;

-- Store the purge secret in Vault. Replace the placeholder via
--   select vault.create_secret('<actual-secret>', 'purge_grade_photos_secret');
-- before scheduling. The migration intentionally inserts a dummy so
-- a missing-secret state is loud, not silent.
select vault.create_secret(
  'REPLACE_ME_BEFORE_RUNNING_CRON',
  'purge_grade_photos_secret'
)
on conflict (name) do nothing;

select cron.schedule(
  'grade-photos-daily-purge',
  '15 3 * * *',
  $$
  select net.http_post(
    url := concat(current_setting('app.settings.supabase_url', true), '/functions/v1/purge-grade-photos'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-purge-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'purge_grade_photos_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
```

- [ ] **Step 4: Verify pg_cron + pg_net + vault are available**

Run via Supabase MCP `mcp__supabase__list_extensions` and confirm `pg_cron`, `pg_net`, and `supabase_vault` are installed. If any are missing, surface to the user before applying — these are project-level features and should not be enabled implicitly.

Then set `app.settings.supabase_url` so the cron can resolve it:

```sql
alter database postgres set app.settings.supabase_url = 'https://<project-ref>.supabase.co';
```

(You'll need to plug in the actual project ref. If you'd rather hardcode the URL into the migration, that works too.)

- [ ] **Step 5: Deploy the function and rotate the vault secret**

Deploy via Supabase MCP `mcp__supabase__deploy_edge_function` with name `purge-grade-photos`. Then update the vault secret with the real value generated in Step 2:

```sql
select vault.update_secret(
  (select id from vault.secrets where name = 'purge_grade_photos_secret'),
  '<real-secret>'
);
```

- [ ] **Step 6: Apply the migration**

`mcp__supabase__apply_migration`, name `purge_grade_photos_schedule`. Confirm.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/purge-grade-photos/ \
        supabase/migrations/20260423130200_purge_grade_photos_schedule.sql
git commit -m "feat(functions): scheduled purge of grade-photo originals after 30 days"
```

---

## Task 4: Edge Function shared — CORS + Supabase + Anthropic

**Files:**
- Create: `supabase/functions/_shared/cors.ts`
- Create: `supabase/functions/_shared/supabase.ts`
- Create: `supabase/functions/_shared/anthropic.ts`

**Why:** This is the first Edge Function in the repo. The shared modules will be reused by future functions (`/cert-lookup`, `/price-comp`, etc. mentioned in sub-projects 3–4).

- [ ] **Step 1: Write `_shared/cors.ts`**

```ts
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function handleOptions(): Response {
  return new Response('ok', { headers: corsHeaders });
}
```

- [ ] **Step 2: Write `_shared/supabase.ts`**

```ts
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

/** Service-role client. Use for writes that bypass RLS in trusted Edge code. */
export function serviceRoleClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set');
  return createClient(url, key, { auth: { persistSession: false } });
}

/** User-scoped client built from the request's bearer token. RLS applies. */
export function userClient(req: Request): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  if (!url || !anon) throw new Error('SUPABASE_URL / SUPABASE_ANON_KEY not set');
  const auth = req.headers.get('Authorization') ?? '';
  return createClient(url, anon, {
    auth: { persistSession: false },
    global: { headers: { Authorization: auth } },
  });
}
```

- [ ] **Step 3: Write `_shared/anthropic.ts`**

```ts
const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const API_VERSION = '2023-06-01';

export type ContentBlock =
  | { type: 'text'; text: string }
  | { type: 'image'; source: { type: 'base64'; media_type: 'image/jpeg' | 'image/png'; data: string } };

export interface MessagesRequest {
  model: string;
  max_tokens: number;
  system: string;
  messages: Array<{ role: 'user' | 'assistant'; content: ContentBlock[] }>;
}

export interface MessagesResponse {
  id: string;
  content: Array<{ type: 'text'; text: string }>;
  stop_reason: string;
  model: string;
}

export async function callMessages(
  body: MessagesRequest,
  opts: { timeoutMs?: number } = {},
): Promise<MessagesResponse> {
  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY not set');

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 18_000);

  try {
    const res = await fetch(ANTHROPIC_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': API_VERSION,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`anthropic ${res.status}: ${text}`);
    }
    return await res.json() as MessagesResponse;
  } finally {
    clearTimeout(timer);
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/_shared/
git commit -m "feat(functions): scaffold shared cors/supabase/anthropic modules"
```

---

## Task 5: Edge Function `/grade-estimate` — types + prompt

**Files:**
- Create: `supabase/functions/grade-estimate/types.ts`
- Create: `supabase/functions/grade-estimate/prompt.ts`

- [ ] **Step 1: Write `types.ts`**

```ts
export interface CenteringRatios {
  left: number;   // 0..1, distance from left photo edge to left card edge / total horizontal whitespace
  right: number;
  top: number;
  bottom: number;
}

export interface GradeEstimateRequest {
  front_image_path: string;
  back_image_path: string;
  centering_front: CenteringRatios;
  centering_back: CenteringRatios;
  include_other_graders: boolean;
}

export type SubGradeKey = 'centering' | 'corners' | 'edges' | 'surface';
export type Confidence = 'low' | 'medium' | 'high';
export type Verdict =
  | 'submit_economy'
  | 'submit_value'
  | 'submit_express'
  | 'do_not_submit'
  | 'borderline_reshoot';

export interface PerGraderReport {
  sub_grades: Record<SubGradeKey, number>;
  sub_grade_notes: Record<SubGradeKey, string>;
  composite_grade: number;
  confidence: Confidence;
  verdict: Verdict;
  verdict_reasoning: string;
}

export interface GradeEstimateLLMOutput extends PerGraderReport {
  other_graders: null | { bgs: PerGraderReport; cgc: PerGraderReport; sgc: PerGraderReport };
}
```

- [ ] **Step 2: Write `prompt.ts`**

```ts
import type { CenteringRatios, GradeEstimateLLMOutput } from './types.ts';

export const SYSTEM_PROMPT = `You are a hyper-critical card grader. Your job is to give the most pessimistic *defensible* PSA grade for the card in these photos. Real submissions cost real money; over-estimating is worse than under-estimating.

Hard rules — no exceptions:
1. Centering ratios are provided as ground truth measured by a calibrated computer-vision pipeline. Use them. Do not re-estimate centering.
2. For corners, edges, and surface: if you cannot clearly see the relevant area in the photo, score it as if it has wear. Do not score generously when the photo is ambiguous.
3. Each sub-grade explanation must reference a specific visible feature (e.g., "top-right corner of the front shows light whitening", "left edge of the back has a 2mm dent at the midpoint", "centering ratio L/R 60/40 is outside PSA 9 tolerance"). No generic prose.
4. The composite grade must be no higher than min(sub_grades) + 1. PSA composites do not average up past the weakest link.
5. If your confidence is "low", the composite must be at most median(sub_grades) - 1.
6. Output must validate against the JSON schema in the user message. Anything else is a failure.

PSA centering tolerances (front face is the binding face; back is informational):
- PSA 10: 55/45 or better
- PSA 9: 60/40 or better
- PSA 8: 65/35 or better
- PSA 7: 70/30 or better
- Worse than 70/30: capped at PSA 6 on centering

Verdict guidance:
- submit_express: composite ≥ 9.5 with high confidence
- submit_value:   composite 8.5-9 with medium-or-high confidence
- submit_economy: composite 7-8 with medium-or-high confidence
- do_not_submit:  composite < 7, OR confidence low and composite < 8.5
- borderline_reshoot: model believes a better photo could change the grade by ≥ 1 step`;

export function buildUserPrompt(args: {
  centering_front: CenteringRatios;
  centering_back: CenteringRatios;
  include_other_graders: boolean;
}): string {
  const { centering_front: f, centering_back: b, include_other_graders } = args;
  const otherGradersSchema = include_other_graders
    ? `,\n  "other_graders": { "bgs": <PerGraderReport>, "cgc": <PerGraderReport>, "sgc": <PerGraderReport> }`
    : `,\n  "other_graders": null`;

  return `Here is a raw (ungraded) trading card. The first image is the FRONT, the second is the BACK.

Measured centering ratios (ground truth — use as-is):
- Front: L/R ${pct(f.left, f.right)}, T/B ${pct(f.top, f.bottom)}
- Back:  L/R ${pct(b.left, b.right)}, T/B ${pct(b.top, b.bottom)}

Return ONLY a JSON object with this exact shape:
{
  "sub_grades":      { "centering": <1-10>, "corners": <1-10>, "edges": <1-10>, "surface": <1-10> },
  "sub_grade_notes": { "centering": "<string>", "corners": "<string>", "edges": "<string>", "surface": "<string>" },
  "composite_grade": <number, may include .5>,
  "confidence":      "low" | "medium" | "high",
  "verdict":         "submit_economy" | "submit_value" | "submit_express" | "do_not_submit" | "borderline_reshoot",
  "verdict_reasoning": "<string>"${otherGradersSchema}
}`;
}

function pct(a: number, b: number): string {
  const total = a + b || 1;
  return `${Math.round((a / total) * 100)}/${Math.round((b / total) * 100)}`;
}

const VALID_VERDICTS = new Set([
  'submit_economy', 'submit_value', 'submit_express', 'do_not_submit', 'borderline_reshoot',
]);
const VALID_CONFIDENCE = new Set(['low', 'medium', 'high']);
const SUB_KEYS = ['centering', 'corners', 'edges', 'surface'] as const;

export function validateOutput(raw: unknown): GradeEstimateLLMOutput {
  if (typeof raw !== 'object' || raw === null) throw new Error('output not an object');
  const o = raw as Record<string, unknown>;

  validateReport(o, 'top-level');

  if (o.other_graders !== null && o.other_graders !== undefined) {
    const og = o.other_graders as Record<string, unknown>;
    for (const k of ['bgs', 'cgc', 'sgc']) {
      const sub = og[k];
      if (typeof sub !== 'object' || sub === null) throw new Error(`other_graders.${k} missing`);
      validateReport(sub as Record<string, unknown>, `other_graders.${k}`);
    }
  }
  return raw as GradeEstimateLLMOutput;
}

function validateReport(o: Record<string, unknown>, label: string): void {
  const sg = o.sub_grades as Record<string, number> | undefined;
  const sn = o.sub_grade_notes as Record<string, string> | undefined;
  if (!sg || !sn) throw new Error(`${label}: missing sub_grades / sub_grade_notes`);
  for (const k of SUB_KEYS) {
    const v = sg[k];
    if (typeof v !== 'number' || v < 1 || v > 10) throw new Error(`${label}.sub_grades.${k}: out of range`);
    if (typeof sn[k] !== 'string' || !sn[k].trim()) throw new Error(`${label}.sub_grade_notes.${k}: empty`);
  }
  const c = o.composite_grade;
  if (typeof c !== 'number' || c < 1 || c > 10) throw new Error(`${label}.composite_grade: out of range`);

  // Enforce hard rule 4 (composite <= min(sub_grades) + 1) at validation time.
  const minSub = Math.min(...SUB_KEYS.map((k) => sg[k]));
  if (c > minSub + 1) throw new Error(`${label}.composite_grade ${c} exceeds min(sub) ${minSub} + 1`);

  if (typeof o.confidence !== 'string' || !VALID_CONFIDENCE.has(o.confidence as string)) {
    throw new Error(`${label}.confidence: invalid`);
  }
  if (typeof o.verdict !== 'string' || !VALID_VERDICTS.has(o.verdict as string)) {
    throw new Error(`${label}.verdict: invalid`);
  }
  if (typeof o.verdict_reasoning !== 'string' || !o.verdict_reasoning.trim()) {
    throw new Error(`${label}.verdict_reasoning: empty`);
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/grade-estimate/types.ts supabase/functions/grade-estimate/prompt.ts
git commit -m "feat(functions): add grade-estimate types and prompt builder"
```

---

## Task 6: Edge Function `/grade-estimate` — handler

**Files:**
- Create: `supabase/functions/grade-estimate/index.ts`

- [ ] **Step 1: Write the handler**

```ts
import { corsHeaders, handleOptions } from '../_shared/cors.ts';
import { serviceRoleClient, userClient } from '../_shared/supabase.ts';
import { callMessages, ContentBlock } from '../_shared/anthropic.ts';
import type { GradeEstimateRequest, GradeEstimateLLMOutput } from './types.ts';
import { SYSTEM_PROMPT, buildUserPrompt, validateOutput } from './prompt.ts';

const MODEL = 'claude-sonnet-4-6';
const MODEL_VERSION_TAG = 'claude-sonnet-4-6@2026-04-23-v1';
const DAILY_LIMIT = 20;

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions();
  if (req.method !== 'POST') return jsonResponse(405, { error: 'method_not_allowed' });

  // 1. Auth
  const userScoped = userClient(req);
  const { data: userData, error: userErr } = await userScoped.auth.getUser();
  if (userErr || !userData.user) return jsonResponse(401, { error: 'unauthorized' });
  const userId = userData.user.id;

  // 2. Parse + validate request
  let body: GradeEstimateRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: 'invalid_json' });
  }
  if (!body.front_image_path || !body.back_image_path) {
    return jsonResponse(400, { error: 'missing_image_paths' });
  }
  if (!body.centering_front || !body.centering_back) {
    return jsonResponse(400, { error: 'missing_centering' });
  }

  // 3. Rate limit (daily count for user)
  const service = serviceRoleClient();
  const { count: dailyCount } = await service
    .from('grade_estimates')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .gte('created_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString());
  if ((dailyCount ?? 0) >= DAILY_LIMIT) {
    return jsonResponse(429, { error: 'rate_limited', limit: DAILY_LIMIT });
  }

  // 4. Fetch images from storage as base64
  const [frontBytes, backBytes] = await Promise.all([
    downloadAsBase64(service, body.front_image_path),
    downloadAsBase64(service, body.back_image_path),
  ]);

  // 5. Build prompt + call Anthropic, with one retry on schema-validation failure
  const userPrompt = buildUserPrompt({
    centering_front: body.centering_front,
    centering_back: body.centering_back,
    include_other_graders: body.include_other_graders,
  });
  const content: ContentBlock[] = [
    { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: frontBytes } },
    { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: backBytes } },
    { type: 'text', text: userPrompt },
  ];

  let parsed: GradeEstimateLLMOutput | null = null;
  let lastError: unknown = null;
  for (let attempt = 0; attempt < 2 && parsed === null; attempt++) {
    try {
      const res = await callMessages({
        model: MODEL,
        max_tokens: 1500,
        system: SYSTEM_PROMPT,
        messages: [{ role: 'user', content }],
      });
      const text = res.content.map((b) => b.text).join('');
      const jsonStart = text.indexOf('{');
      const jsonEnd = text.lastIndexOf('}');
      if (jsonStart < 0 || jsonEnd < 0) throw new Error('no JSON object in output');
      const candidate = JSON.parse(text.slice(jsonStart, jsonEnd + 1));
      parsed = validateOutput(candidate);
    } catch (e) {
      lastError = e;
    }
  }
  if (parsed === null) {
    console.error('grade-estimate: validation failed', lastError);
    return jsonResponse(502, { error: 'model_output_invalid' });
  }

  // 6. Derive thumbnail paths from image paths by convention.
  const frontThumb = body.front_image_path.replace(/\/front\.jpg$/, '/front_thumb.jpg');
  const backThumb = body.back_image_path.replace(/\/back\.jpg$/, '/back_thumb.jpg');

  // 7. Persist
  const { data: row, error: insertErr } = await service
    .from('grade_estimates')
    .insert({
      user_id: userId,
      scan_id: null,
      front_image_path: body.front_image_path,
      back_image_path: body.back_image_path,
      front_thumb_path: frontThumb,
      back_thumb_path: backThumb,
      centering_front: body.centering_front,
      centering_back: body.centering_back,
      sub_grades: parsed.sub_grades,
      sub_grade_notes: parsed.sub_grade_notes,
      composite_grade: parsed.composite_grade,
      confidence: parsed.confidence,
      verdict: parsed.verdict,
      verdict_reasoning: parsed.verdict_reasoning,
      other_graders: parsed.other_graders,
      model_version: MODEL_VERSION_TAG,
    })
    .select()
    .single();
  if (insertErr) {
    console.error('grade-estimate: insert failed', insertErr);
    return jsonResponse(500, { error: 'persist_failed' });
  }

  return jsonResponse(200, row);
});

async function downloadAsBase64(client: ReturnType<typeof serviceRoleClient>, path: string): Promise<string> {
  const { data, error } = await client.storage.from('grade-photos').download(path);
  if (error || !data) throw new Error(`download failed: ${path}`);
  const buf = await data.arrayBuffer();
  return base64Encode(new Uint8Array(buf));
}

function base64Encode(bytes: Uint8Array): string {
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}
```

- [ ] **Step 2: Write the function-config (Supabase deploy metadata)**

Create `supabase/functions/grade-estimate/deno.json`:

```json
{
  "imports": {
    "@supabase/supabase-js": "https://esm.sh/@supabase/supabase-js@2.45.0"
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/grade-estimate/index.ts supabase/functions/grade-estimate/deno.json
git commit -m "feat(functions): grade-estimate handler with auth, rate-limit, and persistence"
```

---

## Task 7: Edge Function — schema validation tests

**Files:**
- Create: `supabase/functions/grade-estimate/prompt.test.ts`

**Why this layer:** The handler depends on Anthropic + Supabase, both painful to mock end-to-end in a Deno test. The schema-validator and prompt-builder are pure and have all the bug-prone logic (the composite-vs-min-sub rule, enum membership, missing-key handling). Test them directly.

- [ ] **Step 1: Write the failing tests**

```ts
import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { buildUserPrompt, validateOutput } from './prompt.ts';

const validReport = {
  sub_grades: { centering: 8, corners: 7, edges: 8, surface: 9 },
  sub_grade_notes: {
    centering: 'L/R 55/45 within PSA 8 tolerance',
    corners: 'TR corner front shows light whitening',
    edges: 'left edge front has tiny dent at midpoint',
    surface: 'no visible scratches at this resolution',
  },
  composite_grade: 8,
  confidence: 'high',
  verdict: 'submit_value',
  verdict_reasoning: 'Solid 8 with consistent measurements',
  other_graders: null,
};

Deno.test('validateOutput accepts a well-formed report', () => {
  validateOutput(validReport);
});

Deno.test('validateOutput rejects composite > min(sub) + 1', () => {
  const bad = { ...validReport, composite_grade: 9.5 };  // min=7, allowed up to 8
  assertThrows(() => validateOutput(bad), Error, 'exceeds min(sub)');
});

Deno.test('validateOutput rejects empty sub_grade_notes', () => {
  const bad = { ...validReport, sub_grade_notes: { ...validReport.sub_grade_notes, corners: '' } };
  assertThrows(() => validateOutput(bad), Error, 'empty');
});

Deno.test('validateOutput rejects out-of-range sub_grade', () => {
  const bad = { ...validReport, sub_grades: { ...validReport.sub_grades, edges: 11 } };
  assertThrows(() => validateOutput(bad), Error, 'out of range');
});

Deno.test('validateOutput rejects unknown verdict', () => {
  const bad = { ...validReport, verdict: 'send_it' };
  assertThrows(() => validateOutput(bad), Error, 'verdict');
});

Deno.test('validateOutput recurses into other_graders when present', () => {
  const badOther = {
    ...validReport,
    other_graders: {
      bgs: { ...validReport, composite_grade: 9.5 }, // violates rule 4 inside bgs
      cgc: validReport,
      sgc: validReport,
    },
  };
  assertThrows(() => validateOutput(badOther), Error, 'other_graders.bgs');
});

Deno.test('buildUserPrompt formats centering as integer percentages', () => {
  const out = buildUserPrompt({
    centering_front: { left: 0.6, right: 0.4, top: 0.5, bottom: 0.5 },
    centering_back: { left: 0.5, right: 0.5, top: 0.5, bottom: 0.5 },
    include_other_graders: false,
  });
  assertEquals(out.includes('Front: L/R 60/40'), true);
  assertEquals(out.includes('"other_graders": null'), true);
});
```

- [ ] **Step 2: Run the tests**

```bash
cd supabase/functions/grade-estimate
deno test --allow-env --allow-net prompt.test.ts
```

Expected: all 7 tests pass.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/grade-estimate/prompt.test.ts
git commit -m "test(functions): cover grade-estimate prompt builder and validator"
```

---

## Task 8: iOS — `GradeEstimateDTO`

**Files:**
- Create: `ios/slabbist/slabbist/Core/Data/DTOs/GradeEstimateDTO.swift`
- Create: `ios/slabbist/slabbistTests/Core/Data/GradeEstimateDTOTests.swift`

**Pattern reference:** `ios/slabbist/slabbist/Core/Data/DTOs/ScanDTO.swift` (snake_case CodingKeys + `nonisolated struct`).

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import slabbist

@Suite("GradeEstimateDTO")
struct GradeEstimateDTOTests {
    @Test("decodes a Postgrest row payload")
    func decodes() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "scan_id": null,
          "front_image_path": "u/e/front.jpg",
          "back_image_path":  "u/e/back.jpg",
          "front_thumb_path": "u/e/front_thumb.jpg",
          "back_thumb_path":  "u/e/back_thumb.jpg",
          "images_purged_at": null,
          "centering_front": {"left": 0.5, "right": 0.5, "top": 0.5, "bottom": 0.5},
          "centering_back":  {"left": 0.5, "right": 0.5, "top": 0.5, "bottom": 0.5},
          "sub_grades": {"centering": 8, "corners": 7, "edges": 8, "surface": 9},
          "sub_grade_notes": {"centering": "ok", "corners": "ok", "edges": "ok", "surface": "ok"},
          "composite_grade": 8,
          "confidence": "high",
          "verdict": "submit_value",
          "verdict_reasoning": "ok",
          "other_graders": null,
          "model_version": "claude-sonnet-4-6@2026-04-23-v1",
          "is_starred": false,
          "created_at": "2026-04-23T10:00:00Z"
        }
        """.data(using: .utf8)!

        let dto = try JSONCoders.decoder.decode(GradeEstimateDTO.self, from: json)
        #expect(dto.frontImagePath == "u/e/front.jpg")
        #expect(dto.subGrades.centering == 8)
        #expect(dto.compositeGrade == 8)
        #expect(dto.confidence == "high")
        #expect(dto.verdict == "submit_value")
        #expect(dto.scanId == nil)
        #expect(dto.imagesPurgedAt == nil)
    }
}
```

- [ ] **Step 2: Run the test, verify it fails**

`Build target slabbistTests, run GradeEstimateDTOTests`. Expected: FAIL — `GradeEstimateDTO` not found.

- [ ] **Step 3: Write the DTO**

```swift
import Foundation

nonisolated struct CenteringRatios: Codable, Sendable, Equatable {
    var left: Double
    var right: Double
    var top: Double
    var bottom: Double
}

nonisolated struct SubGrades: Codable, Sendable, Equatable {
    var centering: Double
    var corners: Double
    var edges: Double
    var surface: Double
}

nonisolated struct SubGradeNotes: Codable, Sendable, Equatable {
    var centering: String
    var corners: String
    var edges: String
    var surface: String
}

nonisolated struct PerGraderReport: Codable, Sendable, Equatable {
    var subGrades: SubGrades
    var subGradeNotes: SubGradeNotes
    var compositeGrade: Double
    var confidence: String
    var verdict: String
    var verdictReasoning: String

    enum CodingKeys: String, CodingKey {
        case subGrades = "sub_grades"
        case subGradeNotes = "sub_grade_notes"
        case compositeGrade = "composite_grade"
        case confidence
        case verdict
        case verdictReasoning = "verdict_reasoning"
    }
}

nonisolated struct OtherGradersBundle: Codable, Sendable, Equatable {
    var bgs: PerGraderReport
    var cgc: PerGraderReport
    var sgc: PerGraderReport
}

/// Wire shape for the `grade_estimates` Postgres table.
nonisolated struct GradeEstimateDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var userId: UUID
    var scanId: UUID?

    var frontImagePath: String
    var backImagePath: String
    var frontThumbPath: String
    var backThumbPath: String
    var imagesPurgedAt: Date?

    var centeringFront: CenteringRatios
    var centeringBack: CenteringRatios

    var subGrades: SubGrades
    var subGradeNotes: SubGradeNotes
    var compositeGrade: Double
    var confidence: String
    var verdict: String
    var verdictReasoning: String

    var otherGraders: OtherGradersBundle?
    var modelVersion: String
    var isStarred: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case scanId = "scan_id"
        case frontImagePath = "front_image_path"
        case backImagePath = "back_image_path"
        case frontThumbPath = "front_thumb_path"
        case backThumbPath = "back_thumb_path"
        case imagesPurgedAt = "images_purged_at"
        case centeringFront = "centering_front"
        case centeringBack = "centering_back"
        case subGrades = "sub_grades"
        case subGradeNotes = "sub_grade_notes"
        case compositeGrade = "composite_grade"
        case confidence
        case verdict
        case verdictReasoning = "verdict_reasoning"
        case otherGraders = "other_graders"
        case modelVersion = "model_version"
        case isStarred = "is_starred"
        case createdAt = "created_at"
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Data/DTOs/GradeEstimateDTO.swift \
        ios/slabbist/slabbistTests/Core/Data/GradeEstimateDTOTests.swift
git commit -m "feat(ios): add GradeEstimateDTO for grade_estimates table"
```

---

## Task 9: iOS — `CenteringMeasurement` (pure math, fully tested)

**Files:**
- Create: `ios/slabbist/slabbist/Core/Vision/CenteringMeasurement.swift`
- Create: `ios/slabbist/slabbistTests/Core/Vision/CenteringMeasurementTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
import CoreGraphics
@testable import slabbist

@Suite("CenteringMeasurement")
struct CenteringMeasurementTests {
    @Test("perfectly centered card → 50/50 ratios on both axes")
    func perfectlyCentered() {
        let image = CGRect(x: 0, y: 0, width: 1000, height: 1400)
        let card = CGRect(x: 100, y: 140, width: 800, height: 1120)
        let r = CenteringMeasurement.measure(cardRect: card, in: image)
        #expect(abs(r.left - 0.5) < 0.001)
        #expect(abs(r.right - 0.5) < 0.001)
        #expect(abs(r.top - 0.5) < 0.001)
        #expect(abs(r.bottom - 0.5) < 0.001)
    }

    @Test("60/40 horizontal off-center → left ratio 0.6")
    func horizontalSkew() {
        let image = CGRect(x: 0, y: 0, width: 1000, height: 1400)
        // Card shifted right: left whitespace = 120, right whitespace = 80
        let card = CGRect(x: 120, y: 140, width: 800, height: 1120)
        let r = CenteringMeasurement.measure(cardRect: card, in: image)
        #expect(abs(r.left - 0.6) < 0.001)
        #expect(abs(r.right - 0.4) < 0.001)
    }

    @Test("zero whitespace on one side returns 1.0/0.0")
    func cardTouchesEdge() {
        let image = CGRect(x: 0, y: 0, width: 1000, height: 1400)
        let card = CGRect(x: 0, y: 140, width: 900, height: 1120)
        let r = CenteringMeasurement.measure(cardRect: card, in: image)
        #expect(r.left == 0.0)
        #expect(r.right == 1.0)
    }
}
```

- [ ] **Step 2: Run tests, verify fail**

Expected: FAIL — `CenteringMeasurement` not defined.

- [ ] **Step 3: Implement**

```swift
import Foundation
import CoreGraphics

/// Computes PSA-style centering ratios from a detected card rectangle
/// and the underlying image bounds. Returned values are in 0...1 where
/// `left = leftWhitespace / (leftWhitespace + rightWhitespace)`. A perfectly
/// centered card returns 0.5 on every axis.
enum CenteringMeasurement {
    struct Ratios: Equatable {
        var left: Double
        var right: Double
        var top: Double
        var bottom: Double
    }

    static func measure(cardRect: CGRect, in imageRect: CGRect) -> Ratios {
        let leftWS = max(0, cardRect.minX - imageRect.minX)
        let rightWS = max(0, imageRect.maxX - cardRect.maxX)
        let topWS = max(0, cardRect.minY - imageRect.minY)
        let bottomWS = max(0, imageRect.maxY - cardRect.maxY)

        let h = leftWS + rightWS
        let v = topWS + bottomWS

        let left = h == 0 ? 0.5 : Double(leftWS / h)
        let top = v == 0 ? 0.5 : Double(topWS / v)
        return Ratios(left: left, right: 1 - left, top: top, bottom: 1 - top)
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Vision/CenteringMeasurement.swift \
        ios/slabbist/slabbistTests/Core/Vision/CenteringMeasurementTests.swift
git commit -m "feat(ios): add CenteringMeasurement primitive with full test coverage"
```

---

## Task 10: iOS — `CardRectangleDetector` (Vision wrapper)

**Files:**
- Create: `ios/slabbist/slabbist/Core/Vision/CardRectangleDetector.swift`
- Create: `ios/slabbist/slabbistTests/Core/Vision/CardRectangleDetectorTests.swift`
- Create: `ios/slabbist/slabbistTests/Resources/GradingFixtures/centered_card.jpg` — capture a quick image of a real card on a contrasting background and add to the test target. (See step 1 note.)

**Note:** Vision tests benefit from a real fixture image. If you cannot generate one, mark the integration test `.disabled` and rely on the unit tests of the post-processing logic. Do NOT skip the post-processing tests.

- [ ] **Step 1: Add fixture image**

Add a single JPEG of a Pokémon card photographed on a contrasting background to the test target at `ios/slabbist/slabbistTests/Resources/GradingFixtures/centered_card.jpg`. If you don't have one, generate a synthetic fixture: a 1000×1400 white image with an 800×1120 dark rectangle inset 100px on the sides (ASCII-equivalent will work for VNDetectRectanglesRequest).

- [ ] **Step 2: Write the failing test**

```swift
import Foundation
import Testing
import CoreGraphics
import UIKit
@testable import slabbist

@Suite("CardRectangleDetector")
struct CardRectangleDetectorTests {
    @Test("detects a card on a contrasting background")
    func detectsCard() async throws {
        let url = Bundle(for: BundleAnchor.self).url(
            forResource: "centered_card",
            withExtension: "jpg",
            subdirectory: "GradingFixtures"
        )!
        let image = UIImage(contentsOfFile: url.path)!
        let result = try await CardRectangleDetector().detect(in: image)
        #expect(result != nil)
        #expect(result!.confidence >= 0.85)
        // Aspect ratio close to standard card (~0.71)
        let ar = result!.boundingBox.width / result!.boundingBox.height
        #expect(ar > 0.6 && ar < 0.85)
    }
}

private final class BundleAnchor {}
```

- [ ] **Step 3: Run, expect FAIL**

Expected: FAIL (compile error — `CardRectangleDetector` undefined).

- [ ] **Step 4: Implement**

```swift
import Foundation
import UIKit
import Vision

/// Wraps `VNDetectRectanglesRequest` with thresholds tuned for trading cards.
/// Returns the highest-confidence rectangle whose aspect ratio falls in the
/// trading-card range (0.6–0.85). Coordinates are in the image's pixel space,
/// origin top-left.
struct CardRectangleDetector {
    struct Result: Equatable {
        var boundingBox: CGRect    // pixel-space, origin top-left
        var confidence: Float
    }

    func detect(in image: UIImage) async throws -> Result? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.6
        request.maximumAspectRatio = 0.85
        request.minimumConfidence = 0.85
        request.minimumSize = 0.4   // at least 40% of the frame
        request.maximumObservations = 4

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])

        guard let best = (request.results ?? []).max(by: { $0.confidence < $1.confidence }) else {
            return nil
        }

        // Vision returns normalized coords with origin bottom-left; flip to top-left pixel space.
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let bb = best.boundingBox
        let pixelRect = CGRect(
            x: bb.minX * w,
            y: (1 - bb.maxY) * h,
            width: bb.width * w,
            height: bb.height * h
        )
        return Result(boundingBox: pixelRect, confidence: best.confidence)
    }
}
```

- [ ] **Step 5: Run, expect PASS**

- [ ] **Step 6: Commit**

```bash
git add ios/slabbist/slabbist/Core/Vision/CardRectangleDetector.swift \
        ios/slabbist/slabbistTests/Core/Vision/CardRectangleDetectorTests.swift \
        ios/slabbist/slabbistTests/Resources/GradingFixtures/
git commit -m "feat(ios): add CardRectangleDetector wrapping VNDetectRectanglesRequest"
```

---

## Task 11: iOS — `CaptureQualityGate`

**Files:**
- Create: `ios/slabbist/slabbist/Core/Vision/CaptureQualityGate.swift`
- Create: `ios/slabbist/slabbistTests/Core/Vision/CaptureQualityGateTests.swift`

**Why all four checks live in one file:** They run on the same input and short-circuit on the first failure with a labeled reason. Keeping the orchestration in one place lets the capture VM consume a single `Result` enum.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
import CoreGraphics
import UIKit
@testable import slabbist

@Suite("CaptureQualityGate")
struct CaptureQualityGateTests {
    @Test("rejects below minimum resolution")
    func rejectsLowRes() {
        let image = solidImage(size: CGSize(width: 800, height: 1100), color: .white)
        let result = CaptureQualityGate().evaluate(
            image: image,
            cardDetection: CardRectangleDetector.Result(
                boundingBox: CGRect(x: 50, y: 50, width: 700, height: 1000),
                confidence: 0.95
            ),
            blurScore: 200,
            glareRatio: 0.001
        )
        if case .rejected(let reason) = result {
            #expect(reason.contains("resolution"))
        } else {
            Issue.record("expected rejection")
        }
    }

    @Test("rejects when card detection is missing")
    func rejectsNoCard() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100), color: .white)
        let result = CaptureQualityGate().evaluate(
            image: image,
            cardDetection: nil,
            blurScore: 200,
            glareRatio: 0.001
        )
        if case .rejected(let reason) = result {
            #expect(reason.lowercased().contains("card"))
        } else {
            Issue.record("expected rejection")
        }
    }

    @Test("rejects when blur score below threshold")
    func rejectsBlurry() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100), color: .white)
        let result = CaptureQualityGate().evaluate(
            image: image,
            cardDetection: CardRectangleDetector.Result(
                boundingBox: CGRect(x: 100, y: 200, width: 1300, height: 1700),
                confidence: 0.95
            ),
            blurScore: 50,
            glareRatio: 0.001
        )
        if case .rejected(let reason) = result {
            #expect(reason.lowercased().contains("blur"))
        } else {
            Issue.record("expected rejection")
        }
    }

    @Test("rejects when glare ratio above threshold")
    func rejectsGlare() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100), color: .white)
        let result = CaptureQualityGate().evaluate(
            image: image,
            cardDetection: CardRectangleDetector.Result(
                boundingBox: CGRect(x: 100, y: 200, width: 1300, height: 1700),
                confidence: 0.95
            ),
            blurScore: 200,
            glareRatio: 0.05
        )
        if case .rejected(let reason) = result {
            #expect(reason.lowercased().contains("glare"))
        } else {
            Issue.record("expected rejection")
        }
    }

    @Test("accepts when all four checks pass")
    func acceptsClean() {
        let image = solidImage(size: CGSize(width: 1500, height: 2100), color: .white)
        let det = CardRectangleDetector.Result(
            boundingBox: CGRect(x: 100, y: 200, width: 1300, height: 1700),
            confidence: 0.95
        )
        let result = CaptureQualityGate().evaluate(
            image: image,
            cardDetection: det,
            blurScore: 200,
            glareRatio: 0.001
        )
        if case .ok = result {} else { Issue.record("expected ok") }
    }

    private func solidImage(size: CGSize, color: UIColor) -> UIImage {
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
}
```

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Implement**

```swift
import Foundation
import UIKit

/// Pre-flight checks applied to a captured frame. The capture button stays
/// disabled until `evaluate(...)` returns `.ok`. A failed check returns a
/// human-readable reason that the UI surfaces to the user.
struct CaptureQualityGate {
    struct Thresholds {
        var minWidth: Int = 1500
        var minHeight: Int = 2100
        var minBlurScore: Double = 100
        var maxGlareRatio: Double = 0.02
    }

    enum Outcome: Equatable {
        case ok
        case rejected(reason: String)
    }

    let thresholds: Thresholds

    init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    func evaluate(
        image: UIImage,
        cardDetection: CardRectangleDetector.Result?,
        blurScore: Double,
        glareRatio: Double
    ) -> Outcome {
        let w = Int(image.size.width * image.scale)
        let h = Int(image.size.height * image.scale)
        if w < thresholds.minWidth || h < thresholds.minHeight {
            return .rejected(reason: "Photo resolution too low — move closer or use better light.")
        }
        if cardDetection == nil {
            return .rejected(reason: "Card not detected — frame the whole card with a contrasting background.")
        }
        if blurScore < thresholds.minBlurScore {
            return .rejected(reason: "Too blurry — hold steady and let the camera focus.")
        }
        if glareRatio > thresholds.maxGlareRatio {
            return .rejected(reason: "Too much glare — angle the card away from direct light.")
        }
        return .ok
    }
}
```

- [ ] **Step 4: Run, expect PASS**

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Vision/CaptureQualityGate.swift \
        ios/slabbist/slabbistTests/Core/Vision/CaptureQualityGateTests.swift
git commit -m "feat(ios): add CaptureQualityGate with resolution/card/blur/glare checks"
```

---

## Task 12: iOS — `StillImageCapture` (AVCapturePhotoOutput wrapper)

**Files:**
- Create: `ios/slabbist/slabbist/Core/Vision/StillImageCapture.swift`

**Why a new file rather than extending `CameraSession`:** The existing session is a video pipeline (`AVCaptureVideoDataOutput` + sample-buffer delegate). The grading flow needs a high-resolution still photo with EXIF orientation handling. Adding `AVCapturePhotoOutput` to the existing session is fine, but the photo capture **delegate plumbing** is its own concern; isolating it keeps the existing live OCR path untouched.

- [ ] **Step 1: Implement**

```swift
import AVFoundation
import UIKit

/// Captures a single high-resolution still photo from a `CameraSession`.
/// Adds an `AVCapturePhotoOutput` to the session lazily and orchestrates
/// the delegate callback as an `async` value.
@MainActor
final class StillImageCapture: NSObject {
    private let session: CameraSession
    private let photoOutput = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var attached = false

    init(session: CameraSession) {
        self.session = session
        super.init()
    }

    func attachIfNeeded() {
        guard !attached else { return }
        let cs = session.captureSession
        cs.beginConfiguration()
        defer { cs.commitConfiguration() }
        if cs.canAddOutput(photoOutput) {
            cs.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            attached = true
        }
    }

    func capture() async throws -> UIImage {
        attachIfNeeded()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UIImage, Error>) in
            self.continuation = cont
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            settings.flashMode = .off
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension StillImageCapture: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            defer { self.continuation = nil }
            if let error {
                self.continuation?.resume(throwing: error)
                return
            }
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                self.continuation?.resume(throwing: NSError(
                    domain: "StillImageCapture",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "no image data"]
                ))
                return
            }
            self.continuation?.resume(returning: image)
        }
    }
}
```

- [ ] **Step 2: Commit (no separate test — covered by E2E in Task 18)**

```bash
git add ios/slabbist/slabbist/Core/Vision/StillImageCapture.swift
git commit -m "feat(ios): add StillImageCapture wrapping AVCapturePhotoOutput"
```

---

## Task 13: iOS — `GradePhotoUploader`

**Files:**
- Create: `ios/slabbist/slabbist/Core/Data/Repositories/GradePhotoUploader.swift`

**Behavior:** Generates a per-estimate UUID, encodes both images as JPEG (quality 0.9), generates 400×560 thumbnails, uploads all four objects to `grade-photos/<userId>/<estimateId>/` with the conventions the Edge Function expects.

- [ ] **Step 1: Implement**

```swift
import Foundation
import UIKit
import Supabase

nonisolated struct GradePhotoUploader: Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
    }

    struct UploadResult: Sendable {
        let estimateId: UUID
        let frontPath: String
        let backPath: String
        let frontThumbPath: String
        let backThumbPath: String
    }

    func upload(front: UIImage, back: UIImage, userId: UUID) async throws -> UploadResult {
        let estimateId = UUID()
        let prefix = "\(userId.uuidString.lowercased())/\(estimateId.uuidString.lowercased())"

        let frontPath = "\(prefix)/front.jpg"
        let backPath = "\(prefix)/back.jpg"
        let frontThumbPath = "\(prefix)/front_thumb.jpg"
        let backThumbPath = "\(prefix)/back_thumb.jpg"

        let frontData = try jpegOrThrow(front, quality: 0.9)
        let backData = try jpegOrThrow(back, quality: 0.9)
        let frontThumbData = try jpegOrThrow(thumbnail(front), quality: 0.85)
        let backThumbData = try jpegOrThrow(thumbnail(back), quality: 0.85)

        let bucket = client.storage.from("grade-photos")
        try await bucket.upload(path: frontPath, file: frontData, options: FileOptions(contentType: "image/jpeg"))
        try await bucket.upload(path: backPath, file: backData, options: FileOptions(contentType: "image/jpeg"))
        try await bucket.upload(path: frontThumbPath, file: frontThumbData, options: FileOptions(contentType: "image/jpeg"))
        try await bucket.upload(path: backThumbPath, file: backThumbData, options: FileOptions(contentType: "image/jpeg"))

        return UploadResult(
            estimateId: estimateId,
            frontPath: frontPath,
            backPath: backPath,
            frontThumbPath: frontThumbPath,
            backThumbPath: backThumbPath
        )
    }

    private func jpegOrThrow(_ image: UIImage, quality: CGFloat) throws -> Data {
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw NSError(domain: "GradePhotoUploader", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "jpeg encoding failed"])
        }
        return data
    }

    private func thumbnail(_ image: UIImage) -> UIImage {
        let target = CGSize(width: 400, height: 560)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ios/slabbist/slabbist/Core/Data/Repositories/GradePhotoUploader.swift
git commit -m "feat(ios): add GradePhotoUploader for grade-photos bucket"
```

---

## Task 14: iOS — `GradeEstimateRepository` protocol + concrete

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Data/Repositories/RepositoryProtocols.swift`
- Create: `ios/slabbist/slabbist/Core/Data/Repositories/GradeEstimateRepository.swift`

- [ ] **Step 1: Add protocol + bundle slot**

In `RepositoryProtocols.swift`, append after the existing `ScanRepository` protocol block:

```swift
nonisolated protocol GradeEstimateRepository: Sendable {
    func listForCurrentUser(page: Page, includeTotalCount: Bool) async throws -> PagedResult<GradeEstimateDTO>
    func find(id: UUID) async throws -> GradeEstimateDTO?
    func setStarred(id: UUID, starred: Bool) async throws
    func delete(id: UUID) async throws

    /// Invokes the `/grade-estimate` Edge Function and returns the persisted row.
    func requestEstimate(
        frontPath: String,
        backPath: String,
        centeringFront: CenteringRatios,
        centeringBack: CenteringRatios,
        includeOtherGraders: Bool
    ) async throws -> GradeEstimateDTO
}
```

In the same file, replace the `AppRepositories` struct with:

```swift
nonisolated struct AppRepositories: Sendable {
    var stores: any StoreRepository
    var members: any StoreMemberRepository
    var lots: any LotRepository
    var scans: any ScanRepository
    var gradeEstimates: any GradeEstimateRepository

    static func live(client: SupabaseClient = AppSupabase.shared.client) -> AppRepositories {
        AppRepositories(
            stores: SupabaseStoreRepository(client: client),
            members: SupabaseStoreMemberRepository(client: client),
            lots: SupabaseLotRepository(client: client),
            scans: SupabaseScanRepository(client: client),
            gradeEstimates: SupabaseGradeEstimateRepository(client: client)
        )
    }
}
```

If existing tests construct `AppRepositories(...)` directly with positional or partial args, they will fail to compile. Use LSP `findReferences` on `AppRepositories(` to locate them and add `gradeEstimates:` arguments (use `SupabaseGradeEstimateRepository(client:)` or a fake).

- [ ] **Step 2: Implement the repository**

Create `ios/slabbist/slabbist/Core/Data/Repositories/GradeEstimateRepository.swift`:

```swift
import Foundation
import Supabase

nonisolated struct SupabaseGradeEstimateRepository: GradeEstimateRepository, Sendable {
    static let tableName = "grade_estimates"
    static let functionName = "grade-estimate"

    private let base: SupabaseRepository<GradeEstimateDTO>
    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
        self.base = SupabaseRepository(tableName: Self.tableName, client: client)
    }

    func listForCurrentUser(
        page: Page = .default,
        includeTotalCount: Bool = false
    ) async throws -> PagedResult<GradeEstimateDTO> {
        try await base.findPage(
            page: page,
            orderBy: "created_at",
            ascending: false,
            includeTotalCount: includeTotalCount
        )
    }

    func find(id: UUID) async throws -> GradeEstimateDTO? {
        try await base.find(id: id)
    }

    func setStarred(id: UUID, starred: Bool) async throws {
        do {
            _ = try await client.from(Self.tableName)
                .update(["is_starred": starred], returning: .minimal)
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            throw SupabaseError.map(error)
        }
    }

    func delete(id: UUID) async throws {
        try await base.delete(id: id)
    }

    func requestEstimate(
        frontPath: String,
        backPath: String,
        centeringFront: CenteringRatios,
        centeringBack: CenteringRatios,
        includeOtherGraders: Bool
    ) async throws -> GradeEstimateDTO {
        struct Body: Encodable {
            let front_image_path: String
            let back_image_path: String
            let centering_front: CenteringRatios
            let centering_back: CenteringRatios
            let include_other_graders: Bool
        }
        let body = Body(
            front_image_path: frontPath,
            back_image_path: backPath,
            centering_front: centeringFront,
            centering_back: centeringBack,
            include_other_graders: includeOtherGraders
        )
        do {
            let response: GradeEstimateDTO = try await client.functions
                .invoke(Self.functionName, options: FunctionInvokeOptions(body: body))
            return response
        } catch {
            throw SupabaseError.map(error)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Core/Data/Repositories/GradeEstimateRepository.swift \
        ios/slabbist/slabbist/Core/Data/Repositories/RepositoryProtocols.swift
git commit -m "feat(ios): add GradeEstimateRepository protocol and Supabase impl"
```

---

## Task 15: iOS — `GradingCaptureViewModel`

**Files:**
- Create: `ios/slabbist/slabbist/Features/Grading/Capture/GradingCaptureViewModel.swift`
- Create: `ios/slabbist/slabbistTests/Features/Grading/GradingCaptureViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
import UIKit
@testable import slabbist

@Suite("GradingCaptureViewModel")
@MainActor
struct GradingCaptureViewModelTests {
    @Test("starts in front-capture phase")
    func initialPhase() {
        let vm = GradingCaptureViewModel(repo: FakeGradeRepo(), uploader: FakeUploader(), userId: UUID())
        #expect(vm.phase == .front)
    }

    @Test("after front capture, advances to back-capture phase")
    func frontToBack() {
        let vm = GradingCaptureViewModel(repo: FakeGradeRepo(), uploader: FakeUploader(), userId: UUID())
        let img = UIImage()
        let cf = CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5)
        vm.recordFront(image: img, centering: cf)
        #expect(vm.phase == .back)
    }

    @Test("after back capture, uploads + requests estimate, then transitions to .done with id")
    func backToDone() async throws {
        let repo = FakeGradeRepo()
        let uploader = FakeUploader()
        let vm = GradingCaptureViewModel(repo: repo, uploader: uploader, userId: UUID())
        let img = UIImage()
        let cf = CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5)
        vm.recordFront(image: img, centering: cf)
        vm.recordBack(image: img, centering: cf)
        try await vm.runAnalysis(includeOtherGraders: false)
        if case let .done(id) = vm.phase {
            #expect(id == repo.lastReturnedID)
        } else {
            Issue.record("expected .done phase")
        }
    }
}

@MainActor
final class FakeUploader {
    var lastResult: GradePhotoUploader.UploadResult?
    func upload(front: UIImage, back: UIImage, userId: UUID) async throws -> GradePhotoUploader.UploadResult {
        let id = UUID()
        let prefix = "\(userId.uuidString)/\(id.uuidString)"
        let r = GradePhotoUploader.UploadResult(
            estimateId: id,
            frontPath: "\(prefix)/front.jpg",
            backPath: "\(prefix)/back.jpg",
            frontThumbPath: "\(prefix)/front_thumb.jpg",
            backThumbPath: "\(prefix)/back_thumb.jpg"
        )
        lastResult = r
        return r
    }
}

@MainActor
final class FakeGradeRepo: GradeEstimateRepository {
    private(set) var lastReturnedID = UUID()
    func listForCurrentUser(page: Page, includeTotalCount: Bool) async throws -> PagedResult<GradeEstimateDTO> {
        PagedResult(rows: [], totalCount: nil, page: page)
    }
    func find(id: UUID) async throws -> GradeEstimateDTO? { nil }
    func setStarred(id: UUID, starred: Bool) async throws {}
    func delete(id: UUID) async throws {}
    func requestEstimate(
        frontPath: String, backPath: String,
        centeringFront: CenteringRatios, centeringBack: CenteringRatios,
        includeOtherGraders: Bool
    ) async throws -> GradeEstimateDTO {
        return GradeEstimateDTO(
            id: lastReturnedID,
            userId: UUID(),
            scanId: nil,
            frontImagePath: frontPath,
            backImagePath: backPath,
            frontThumbPath: frontPath.replacingOccurrences(of: "front.jpg", with: "front_thumb.jpg"),
            backThumbPath: backPath.replacingOccurrences(of: "back.jpg", with: "back_thumb.jpg"),
            imagesPurgedAt: nil,
            centeringFront: centeringFront,
            centeringBack: centeringBack,
            subGrades: SubGrades(centering: 8, corners: 7, edges: 8, surface: 9),
            subGradeNotes: SubGradeNotes(centering: "n", corners: "n", edges: "n", surface: "n"),
            compositeGrade: 8,
            confidence: "high",
            verdict: "submit_value",
            verdictReasoning: "n",
            otherGraders: nil,
            modelVersion: "v1",
            isStarred: false,
            createdAt: Date()
        )
    }
}
```

Note: the VM needs to accept the uploader *protocol*. Define `protocol PhotoUploader` (in `GradePhotoUploader.swift`) with the `upload(...)` method, conform `GradePhotoUploader` to it, and make `FakeUploader` conform.

- [ ] **Step 2: Run tests, verify FAIL (compile)**

- [ ] **Step 3: Add `PhotoUploader` protocol**

In `GradePhotoUploader.swift`, above the struct:

```swift
nonisolated protocol PhotoUploader: Sendable {
    func upload(front: UIImage, back: UIImage, userId: UUID) async throws -> GradePhotoUploader.UploadResult
}

extension GradePhotoUploader: PhotoUploader {}
```

Make `FakeUploader` in the test file conform to `PhotoUploader`.

- [ ] **Step 4: Implement the view model**

```swift
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class GradingCaptureViewModel {
    enum Phase: Equatable {
        case front
        case back
        case uploading
        case analyzing
        case done(estimateId: UUID)
        case failed(message: String)
    }

    private(set) var phase: Phase = .front

    private let repo: any GradeEstimateRepository
    private let uploader: any PhotoUploader
    private let userId: UUID

    private var frontImage: UIImage?
    private var frontCentering: CenteringRatios?
    private var backImage: UIImage?
    private var backCentering: CenteringRatios?

    init(repo: any GradeEstimateRepository, uploader: any PhotoUploader, userId: UUID) {
        self.repo = repo
        self.uploader = uploader
        self.userId = userId
    }

    func recordFront(image: UIImage, centering: CenteringRatios) {
        frontImage = image
        frontCentering = centering
        phase = .back
    }

    func recordBack(image: UIImage, centering: CenteringRatios) {
        backImage = image
        backCentering = centering
    }

    func runAnalysis(includeOtherGraders: Bool) async throws {
        guard let frontImage, let frontCentering, let backImage, let backCentering else {
            phase = .failed(message: "Missing capture data")
            return
        }
        phase = .uploading
        let upload: GradePhotoUploader.UploadResult
        do {
            upload = try await uploader.upload(front: frontImage, back: backImage, userId: userId)
        } catch {
            phase = .failed(message: "Upload failed — try again.")
            throw error
        }
        phase = .analyzing
        do {
            let row = try await repo.requestEstimate(
                frontPath: upload.frontPath,
                backPath: upload.backPath,
                centeringFront: frontCentering,
                centeringBack: backCentering,
                includeOtherGraders: includeOtherGraders
            )
            phase = .done(estimateId: row.id)
        } catch {
            phase = .failed(message: "Analysis failed — try again.")
            throw error
        }
    }
}
```

- [ ] **Step 5: Run tests, verify PASS**

- [ ] **Step 6: Commit**

```bash
git add ios/slabbist/slabbist/Features/Grading/Capture/GradingCaptureViewModel.swift \
        ios/slabbist/slabbist/Core/Data/Repositories/GradePhotoUploader.swift \
        ios/slabbist/slabbistTests/Features/Grading/GradingCaptureViewModelTests.swift
git commit -m "feat(ios): GradingCaptureViewModel with phase machine + tests"
```

---

## Task 16: iOS — Capture UI (view + overlay + chip + first-run consent)

**Files:**
- Create: `ios/slabbist/slabbist/Features/Grading/Capture/GradingCaptureView.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Capture/CardOutlineOverlay.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Capture/QualityChip.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Capture/FirstRunConsentView.swift`

**Pattern reference:** existing scanning views in `Features/Scanning/`.

- [ ] **Step 1: Write `CardOutlineOverlay.swift`**

```swift
import SwiftUI

struct CardOutlineOverlay: View {
    let aligned: Bool

    var body: some View {
        GeometryReader { proxy in
            let cardSize = trumpCardSize(in: proxy.size)
            let rect = CGRect(
                x: (proxy.size.width - cardSize.width) / 2,
                y: (proxy.size.height - cardSize.height) / 2,
                width: cardSize.width,
                height: cardSize.height
            )
            ZStack {
                Color.black.opacity(0.45)
                    .mask {
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .frame(width: rect.width, height: rect.height)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    }
                RoundedRectangle(cornerRadius: 14)
                    .stroke(aligned ? AppColor.gold : Color.white.opacity(0.6), lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .ignoresSafeArea()
    }

    private func trumpCardSize(in container: CGSize) -> CGSize {
        let aspect: CGFloat = 0.71428  // standard trading card aspect (2.5x3.5)
        let maxW = container.width * 0.78
        let maxH = container.height * 0.72
        if maxW / aspect <= maxH {
            return CGSize(width: maxW, height: maxW / aspect)
        }
        return CGSize(width: maxH * aspect, height: maxH)
    }
}
```

- [ ] **Step 2: Write `QualityChip.swift`**

```swift
import SwiftUI

struct QualityChip: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
        }
    }
}
```

- [ ] **Step 3: Write `FirstRunConsentView.swift`**

```swift
import SwiftUI

struct FirstRunConsentView: View {
    let onAgree: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Pre-grade Estimator")
                .font(.largeTitle.bold())
            Text(consentBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            PrimaryGoldButton(title: "I understand — continue", action: onAgree)
                .padding(.horizontal, 24)
        }
        .padding()
    }

    private var consentBody: String {
        """
        This is an estimate, not a guarantee. The model can be wrong, especially on subtle surface defects \
        and corner wear that a photo can't reveal. Real grades depend on submission tier, current grader \
        trends, and inspection details we cannot see.

        Slabbist is not responsible for grading outcomes. Use this as a directional check before paying \
        for grading — not as a final answer.
        """
    }
}
```

- [ ] **Step 4: Write `GradingCaptureView.swift`**

```swift
import SwiftUI
import UIKit
import AVFoundation

struct GradingCaptureView: View {
    @State private var session = CameraSession()
    @State private var stillCapture: StillImageCapture?
    @State private var detector = CardRectangleDetector()
    @State private var gate = CaptureQualityGate()
    @State private var qualityMessage: String?
    @State private var showConsent: Bool = !UserDefaults.standard.bool(forKey: "preGradeConsentAccepted_v1")
    @State private var includeOtherGraders: Bool = false

    let viewModel: GradingCaptureViewModel
    let onComplete: (UUID) -> Void

    var body: some View {
        ZStack {
            CameraPreview(session: session.captureSession)
                .ignoresSafeArea()
            CardOutlineOverlay(aligned: qualityMessage == nil)
            VStack {
                Spacer()
                QualityChip(message: qualityMessage)
                    .padding(.bottom, 8)
                captureButton
                    .padding(.bottom, 32)
            }
        }
        .task {
            await session.requestAuthorization()
            try? session.configure()
            stillCapture = StillImageCapture(session: session)
            session.start()
        }
        .onDisappear { session.stop() }
        .sheet(isPresented: $showConsent) {
            FirstRunConsentView {
                UserDefaults.standard.set(true, forKey: "preGradeConsentAccepted_v1")
                showConsent = false
            }
            .interactiveDismissDisabled(true)
        }
        .onChange(of: viewModel.phase) { _, phase in
            if case let .done(id) = phase { onComplete(id) }
        }
    }

    private var captureButton: some View {
        Button {
            Task { await captureCurrentSide() }
        } label: {
            Circle()
                .fill(Color.white)
                .frame(width: 78, height: 78)
                .overlay(Circle().stroke(.black.opacity(0.2), lineWidth: 4))
        }
        .disabled(qualityMessage != nil)
        .accessibilityLabel(viewModel.phase == .front ? "Capture front" : "Capture back")
    }

    private func captureCurrentSide() async {
        guard let stillCapture else { return }
        do {
            let image = try await stillCapture.capture()
            let detection = try await detector.detect(in: image)
            let outcome = gate.evaluate(image: image, cardDetection: detection, blurScore: 200, glareRatio: 0)
            if case .rejected(let reason) = outcome {
                qualityMessage = reason
                return
            }
            qualityMessage = nil
            guard let det = detection else { return }
            let imageRect = CGRect(origin: .zero, size: CGSize(width: image.size.width * image.scale,
                                                                height: image.size.height * image.scale))
            let psaRatios = CenteringMeasurement.measure(cardRect: det.boundingBox, in: imageRect)
            let centering = CenteringRatios(
                left: psaRatios.left,
                right: psaRatios.right,
                top: psaRatios.top,
                bottom: psaRatios.bottom
            )
            switch viewModel.phase {
            case .front:
                viewModel.recordFront(image: image, centering: centering)
            case .back:
                viewModel.recordBack(image: image, centering: centering)
                try await viewModel.runAnalysis(includeOtherGraders: includeOtherGraders)
            default:
                break
            }
        } catch {
            qualityMessage = "Capture failed. Try again."
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
```

Note: `CameraPreview`/`PreviewUIView` may already exist for the bulk-scan flow. If so, reuse them and remove from this file.

- [ ] **Step 5: Verify build (no test for view layer — see Task 18 for E2E)**

Build the slabbist target. Resolve any reuse-vs-new conflicts (`CameraPreview`).

- [ ] **Step 6: Commit**

```bash
git add ios/slabbist/slabbist/Features/Grading/Capture/
git commit -m "feat(ios): grading capture UI with overlay, quality chip, and consent gate"
```

---

## Task 17: iOS — Report screen

**Files:**
- Create: `ios/slabbist/slabbist/Features/Grading/Report/GradeReportView.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Report/SubGradeCard.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Report/VerdictPill.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/Report/OtherGradersPanel.swift`

- [ ] **Step 1: Write `VerdictPill.swift`**

```swift
import SwiftUI

struct VerdictPill: View {
    let verdict: String
    let confidence: String

    var body: some View {
        HStack(spacing: 8) {
            Text(verdictLabel(verdict))
                .font(.headline)
            Text(confidence.capitalized + " confidence")
                .font(.caption)
                .opacity(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(verdictColor(verdict), in: Capsule())
        .foregroundStyle(.white)
    }

    private func verdictLabel(_ v: String) -> String {
        switch v {
        case "submit_express":     return "Submit — Express tier"
        case "submit_value":       return "Submit — Value tier"
        case "submit_economy":     return "Submit — Economy tier"
        case "do_not_submit":      return "Do not submit"
        case "borderline_reshoot": return "Borderline — reshoot"
        default:                   return v
        }
    }

    private func verdictColor(_ v: String) -> Color {
        switch v {
        case "submit_express": return .green
        case "submit_value":   return .teal
        case "submit_economy": return .blue
        case "do_not_submit":  return .red
        default:               return .orange
        }
    }
}
```

- [ ] **Step 2: Write `SubGradeCard.swift`**

```swift
import SwiftUI

struct SubGradeCard: View {
    let title: String
    let score: Double
    let note: String
    let dataPoint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(formatted(score))
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(AppColor.gold)
            }
            Text(note)
                .font(.body)
                .foregroundStyle(.primary)
            if let dataPoint {
                Text(dataPoint)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func formatted(_ s: Double) -> String {
        s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s)
    }
}
```

- [ ] **Step 3: Write `OtherGradersPanel.swift`**

```swift
import SwiftUI

struct OtherGradersPanel: View {
    let bundle: OtherGradersBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Other graders")
                .font(.headline)
            row("BGS", report: bundle.bgs)
            row("CGC", report: bundle.cgc)
            row("SGC", report: bundle.sgc)
            Text("These predictions use the same sub-grades with adjusted composite math, not separately calibrated models.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func row(_ name: String, report: PerGraderReport) -> some View {
        HStack {
            Text(name).bold().frame(width: 48, alignment: .leading)
            Text(String(format: "%.1f", report.compositeGrade)).font(.title3.bold()).foregroundStyle(AppColor.gold)
            Spacer()
            Text(report.verdict).font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 4: Write `GradeReportView.swift`**

```swift
import SwiftUI

struct GradeReportView: View {
    let estimate: GradeEstimateDTO
    var onStarToggle: ((Bool) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showOtherGraders = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                photos
                SubGradeCard(
                    title: "Centering",
                    score: estimate.subGrades.centering,
                    note: estimate.subGradeNotes.centering,
                    dataPoint: centeringDataPoint
                )
                SubGradeCard(title: "Corners", score: estimate.subGrades.corners,
                             note: estimate.subGradeNotes.corners, dataPoint: nil)
                SubGradeCard(title: "Edges", score: estimate.subGrades.edges,
                             note: estimate.subGradeNotes.edges, dataPoint: nil)
                SubGradeCard(title: "Surface", score: estimate.subGrades.surface,
                             note: estimate.subGradeNotes.surface, dataPoint: nil)

                if let other = estimate.otherGraders {
                    DisclosureGroup("Show other graders", isExpanded: $showOtherGraders) {
                        OtherGradersPanel(bundle: other)
                    }
                    .padding(16)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }

                disclaimer
            }
            .padding(16)
        }
        .navigationTitle("PSA \(formatted(estimate.compositeGrade))")
        .toolbar { toolbarItems }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PSA \(formatted(estimate.compositeGrade))")
                .font(.system(size: 48, weight: .heavy))
                .foregroundStyle(AppColor.gold)
            VerdictPill(verdict: estimate.verdict, confidence: estimate.confidence)
            Text(estimate.verdictReasoning)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var photos: some View {
        HStack(spacing: 12) {
            // Thumbnails are loaded asynchronously from Supabase storage (see Task 17.5).
            AsyncGradePhoto(path: estimate.frontThumbPath)
            AsyncGradePhoto(path: estimate.backThumbPath)
        }
        .frame(height: 220)
    }

    private var centeringDataPoint: String {
        let f = estimate.centeringFront
        let b = estimate.centeringBack
        return String(
            format: "Front L/R %.0f/%.0f T/B %.0f/%.0f  •  Back L/R %.0f/%.0f T/B %.0f/%.0f",
            f.left * 100, f.right * 100, f.top * 100, f.bottom * 100,
            b.left * 100, b.right * 100, b.top * 100, b.bottom * 100
        )
    }

    private var disclaimer: some View {
        Text("Estimate only — not a guarantee. Real grades depend on submission tier, grader trends, and minor surface defects not visible in photos. Slabbist is not responsible for grading outcomes.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                onStarToggle?(!estimate.isStarred)
            } label: {
                Image(systemName: estimate.isStarred ? "star.fill" : "star")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .destructive) {
                onDelete?()
            } label: {
                Image(systemName: "trash")
            }
        }
    }

    private func formatted(_ s: Double) -> String {
        s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s)
    }
}
```

- [ ] **Step 5: Add the photo loader**

Append to `GradeReportView.swift`:

```swift
struct AsyncGradePhoto: View {
    let path: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let data = try await AppSupabase.shared.client.storage
                .from("grade-photos")
                .download(path: path)
            image = UIImage(data: data)
        } catch {
            // leave placeholder
        }
    }
}
```

- [ ] **Step 6: Build, fix any compile errors, commit**

```bash
git add ios/slabbist/slabbist/Features/Grading/Report/
git commit -m "feat(ios): grade report screen with sub-grades, verdict, and other graders"
```

---

## Task 18: iOS — History screen + view model

**Files:**
- Create: `ios/slabbist/slabbist/Features/Grading/History/GradeHistoryView.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/History/GradeHistoryViewModel.swift`
- Create: `ios/slabbist/slabbist/Features/Grading/History/GradeHistoryRow.swift`
- Create: `ios/slabbist/slabbistTests/Features/Grading/GradeHistoryViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import slabbist

@Suite("GradeHistoryViewModel")
@MainActor
struct GradeHistoryViewModelTests {
    @Test("loads first page on .load()")
    func loads() async throws {
        let repo = HistoryFakeRepo(rows: [.fixture(grade: 8), .fixture(grade: 9)])
        let vm = GradeHistoryViewModel(repo: repo)
        await vm.load()
        #expect(vm.rows.count == 2)
    }

    @Test("filter starred narrows the list")
    func filterStarred() async throws {
        let repo = HistoryFakeRepo(rows: [
            .fixture(grade: 8, starred: false),
            .fixture(grade: 9, starred: true),
        ])
        let vm = GradeHistoryViewModel(repo: repo)
        await vm.load()
        vm.filter = .starred
        #expect(vm.visibleRows.count == 1)
        #expect(vm.visibleRows.first?.compositeGrade == 9)
    }
}

@MainActor
final class HistoryFakeRepo: GradeEstimateRepository {
    var rows: [GradeEstimateDTO]
    init(rows: [GradeEstimateDTO]) { self.rows = rows }
    func listForCurrentUser(page: Page, includeTotalCount: Bool) async throws -> PagedResult<GradeEstimateDTO> {
        PagedResult(rows: rows, totalCount: rows.count, page: page)
    }
    func find(id: UUID) async throws -> GradeEstimateDTO? { rows.first { $0.id == id } }
    func setStarred(id: UUID, starred: Bool) async throws {
        if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].isStarred = starred }
    }
    func delete(id: UUID) async throws { rows.removeAll { $0.id == id } }
    func requestEstimate(
        frontPath: String, backPath: String,
        centeringFront: CenteringRatios, centeringBack: CenteringRatios,
        includeOtherGraders: Bool
    ) async throws -> GradeEstimateDTO { fatalError("unused") }
}

extension GradeEstimateDTO {
    static func fixture(grade: Double, starred: Bool = false) -> GradeEstimateDTO {
        GradeEstimateDTO(
            id: UUID(), userId: UUID(), scanId: nil,
            frontImagePath: "", backImagePath: "",
            frontThumbPath: "", backThumbPath: "",
            imagesPurgedAt: nil,
            centeringFront: CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5),
            centeringBack:  CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5),
            subGrades: SubGrades(centering: grade, corners: grade, edges: grade, surface: grade),
            subGradeNotes: SubGradeNotes(centering: "", corners: "", edges: "", surface: ""),
            compositeGrade: grade, confidence: "high", verdict: "submit_value", verdictReasoning: "",
            otherGraders: nil, modelVersion: "v1", isStarred: starred, createdAt: Date()
        )
    }
}
```

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Implement the view model**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class GradeHistoryViewModel {
    enum Filter: Equatable { case all, starred }

    private(set) var rows: [GradeEstimateDTO] = []
    var filter: Filter = .all

    private let repo: any GradeEstimateRepository

    init(repo: any GradeEstimateRepository) {
        self.repo = repo
    }

    var visibleRows: [GradeEstimateDTO] {
        switch filter {
        case .all:     return rows
        case .starred: return rows.filter(\.isStarred)
        }
    }

    func load() async {
        do {
            let result = try await repo.listForCurrentUser(page: .default, includeTotalCount: false)
            rows = result.rows
        } catch {
            rows = []
        }
    }

    func toggleStar(id: UUID, starred: Bool) async {
        try? await repo.setStarred(id: id, starred: starred)
        if let i = rows.firstIndex(where: { $0.id == id }) {
            rows[i].isStarred = starred
        }
    }

    func delete(id: UUID) async {
        try? await repo.delete(id: id)
        rows.removeAll { $0.id == id }
    }
}
```

- [ ] **Step 4: Implement the row + list view**

```swift
// GradeHistoryRow.swift
import SwiftUI

struct GradeHistoryRow: View {
    let estimate: GradeEstimateDTO

    var body: some View {
        HStack(spacing: 12) {
            AsyncGradePhoto(path: estimate.frontThumbPath)
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text("PSA \(formatted(estimate.compositeGrade))")
                    .font(.headline)
                Text(estimate.verdict.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if estimate.isStarred {
                Image(systemName: "star.fill").foregroundStyle(AppColor.gold)
            }
            Text(estimate.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    private func formatted(_ s: Double) -> String {
        s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s)
    }
}
```

```swift
// GradeHistoryView.swift
import SwiftUI

struct GradeHistoryView: View {
    @State private var vm: GradeHistoryViewModel
    @State private var openCapture = false

    init(repo: any GradeEstimateRepository) {
        _vm = State(initialValue: GradeHistoryViewModel(repo: repo))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $vm.filter) {
                        Text("All").tag(GradeHistoryViewModel.Filter.all)
                        Text("Starred").tag(GradeHistoryViewModel.Filter.starred)
                    }
                    .pickerStyle(.segmented)
                }
                ForEach(vm.visibleRows) { e in
                    NavigationLink {
                        GradeReportView(
                            estimate: e,
                            onStarToggle: { Task { await vm.toggleStar(id: e.id, starred: $0) } },
                            onDelete:     { Task { await vm.delete(id: e.id) } }
                        )
                    } label: {
                        GradeHistoryRow(estimate: e)
                    }
                }
            }
            .navigationTitle("Grade")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openCapture = true } label: { Image(systemName: "camera.viewfinder") }
                        .accessibilityLabel("Grade a card")
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $openCapture) {
                NavigationStack {
                    GradingCaptureView(
                        viewModel: makeCaptureVM(),
                        onComplete: { _ in
                            openCapture = false
                            Task { await vm.load() }
                        }
                    )
                }
            }
        }
    }

    private func makeCaptureVM() -> GradingCaptureViewModel {
        GradingCaptureViewModel(
            repo: AppRepositories.live().gradeEstimates,
            uploader: GradePhotoUploader(),
            userId: UUID()  // wired by Task 19 to real session.userId
        )
    }
}
```

- [ ] **Step 5: Run tests, verify PASS**

- [ ] **Step 6: Commit**

```bash
git add ios/slabbist/slabbist/Features/Grading/History/ \
        ios/slabbist/slabbistTests/Features/Grading/GradeHistoryViewModelTests.swift
git commit -m "feat(ios): grade history list with filter, star, delete, and capture entry"
```

---

## Task 19: iOS — Wire shell tab + real userId injection

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Shell/RootTabView.swift`
- Modify: `ios/slabbist/slabbist/Features/Grading/History/GradeHistoryView.swift`

- [ ] **Step 1: Add the Grade tab**

Modify `RootTabView.swift`:

```swift
import SwiftUI

struct RootTabView: View {
    let currentUserId: UUID  // injected from session

    var body: some View {
        TabView {
            LotsListView()
                .tabItem { Label("Lots", systemImage: "square.stack.3d.up") }
            ScanShortcutView()
                .tabItem { Label("Scan", systemImage: "viewfinder") }
            GradeHistoryView(
                repo: AppRepositories.live().gradeEstimates,
                currentUserId: currentUserId
            )
                .tabItem { Label("Grade", systemImage: "checkmark.seal") }
            SettingsView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(AppColor.gold)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
```

Find the call sites of `RootTabView()` (likely in the auth shell that hands the session) and pass the resolved `auth.user.id` UUID. Use `findReferences` via LSP to locate them.

- [ ] **Step 2: Plumb `currentUserId` through `GradeHistoryView`**

Modify `GradeHistoryView.swift` to accept `currentUserId: UUID` and pass it into `makeCaptureVM()`.

- [ ] **Step 3: Build, fix, commit**

```bash
git add ios/slabbist/slabbist/Features/Shell/RootTabView.swift \
        ios/slabbist/slabbist/Features/Grading/History/GradeHistoryView.swift
git commit -m "feat(ios): add Grade tab to RootTabView and wire current user id"
```

---

## Task 20: Deploy + smoke test (manual)

**Files:** none (verification only)

- [ ] **Step 1: Set required Edge Function secrets**

Use Supabase MCP `mcp__supabase__deploy_edge_function` to deploy `grade-estimate`. Confirm `ANTHROPIC_API_KEY` is set in the project's function secrets via the Supabase dashboard. (Do not commit the key. Confirm with the user before pasting.)

- [ ] **Step 2: Build the iOS app on a real device**

A simulator can't capture physical photos. Build to a device and walk through:
1. Tap **Grade** tab.
2. First-run consent appears → tap "I understand — continue".
3. Tap the camera button.
4. Aim at a real card; observe the centering overlay highlights gold when aligned.
5. Capture front, flip prompt, capture back.
6. Watch upload + analyze spinner.
7. Report renders with all four sub-grade cards, verdict pill, photos.
8. Star the report → confirm star icon updates.
9. Return to history → confirm row appears at top with star.

Log any issues in `docs/superpowers/plans/2026-04-23-pre-grade-estimator-followups.md` rather than retroactively editing this plan.

- [ ] **Step 3: Verify rate limit + error paths**

- Run 21 estimates in one day → 21st returns 429.
- Disable network mid-analysis → user sees "Analysis failed" message, no row inserted.
- Submit a deliberately blurry photo → quality gate refuses with "Too blurry — hold steady..." message; no upload happens.

- [ ] **Step 4: Commit a smoke-test note**

If anything was discovered and patched during smoke, commit those fixes individually.

---

## Self-Review Checklist (run before handoff)

### Spec coverage
- [x] §3 user flow → Tasks 13, 15, 16, 17, 18 (capture flow + report + history)
- [x] §4 architecture → All tasks fit the diagram (CV → upload → function → persist → render)
- [x] §5 iOS implementation → Tasks 8–19 cover every file listed
- [x] §6 backend → Tasks 4–7 (shared, types, prompt, handler, tests)
- [x] §7 data model → Tasks 1, 2, 3 (table, bucket, purge)
- [x] §8 UI → Tasks 16, 17, 18 (capture, report, history)
- [x] §9 disclaimer → Task 16 (FirstRunConsentView) + Task 17 (footer)
- [x] §10 rate limits → Task 6 (handler check)
- [x] §11 telemetry → Captured in table columns (`model_version`, `created_at`, `confidence`) + handler `console.error` on failure paths. Aggregate dashboard is post-launch and noted in spec.
- [x] §12 migration plan → Tasks 1, 2, 3
- [x] §13 risks → Mitigations land in prompt rules (Task 5), validator (Task 5), gate (Task 11), rate limit (Task 6), 30-day purge (Task 3), `model_version` column (Task 1)
- [x] §14 open questions → Captured in plan body (fixture image note in Task 10, blur threshold in Task 11)

### Placeholder scan
- No "TBD", "TODO", or "implement later" in any task body. Every code step contains real code.

### Type consistency
- `CenteringRatios` defined once in `GradeEstimateDTO.swift` and reused by VM, repo, view, and uploader-consuming code.
- DTO field names match Postgres column names via `CodingKeys`.
- TS types in `_shared/anthropic.ts` and function `types.ts` align with Swift `CenteringRatios` JSON encoding.
- Verdict and confidence string values match the Postgres enums (`grade_verdict`, `grade_confidence`).

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-23-pre-grade-estimator.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. 20 tasks; some are independent (tasks 9–11 vision primitives, task 5 prompt) and parallelize well.
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints for review.

Which approach?
