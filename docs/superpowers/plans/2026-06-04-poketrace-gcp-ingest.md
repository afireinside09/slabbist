# Poketrace Graded Ingest on GCP — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package the existing `poketrace-comp` scraper job into a container and deploy it as a daily Cloud Run Job (Cloud Scheduler-triggered) capped at 9000 Poketrace requests/day.

**Architecture:** No ingest logic changes. Add a Dockerfile that runs the existing CLI command, and an idempotent `gcloud` deploy script that provisions Artifact Registry → Cloud Run Job → Cloud Scheduler, with the three secrets in Secret Manager. The 9000 cap is passed as a Cloud Run Job arg, not baked into the image.

**Tech Stack:** Bun + tsx (existing scraper runtime), Docker, GCP (Cloud Run Jobs, Cloud Scheduler, Artifact Registry, Secret Manager, Cloud Build), bash + gcloud.

**Spec:** `docs/superpowers/specs/2026-06-04-poketrace-gcp-ingest-design.md`

---

## Notes for the implementer

- **Work in this worktree** (`worktree-poketrace-gcp-ingest`, off `main`). All paths below are relative to the worktree root.
- This is **infrastructure / packaging**, not application logic. There are no new unit tests to write — the existing `poketrace-comp` tests already cover the logic and **must stay green** (we change none of it). "Verification" here means: container builds, script parses clean, existing tests unaffected.
- The CLI entrypoint already exists and works: `bun run cli run graded poketrace-comp --max-requests <n> --daily-floor <n>` (see `scraper/src/cli.ts:83-100`). Do **not** modify it.
- The existing eBay workflow (`scraper/.github/workflows/ingest-graded-ebay.yml`) is the reference for env-var names: `SUPABASE_URL`, `SUPABASE_SECRET_KEY` (mapped from the service-role key), and `bun install --frozen-lockfile` + `bun run cli ...`.

---

## File Structure

| File | Responsibility |
|---|---|
| Create: `scraper/.dockerignore` | Keep build context small; exclude secrets/tests/infra. |
| Create: `scraper/Dockerfile` | Bun image that runs the existing CLI command. Cap/floor are the default CMD, overridable. |
| Create: `scraper/deploy/deploy.sh` | Idempotent gcloud provisioning of AR + Cloud Run Job + Scheduler + secrets. |
| Create: `scraper/deploy/README.md` | Operator runbook: prerequisites, deploy, smoke test, changing the cap. |

---

## Task 1: Establish a clean baseline

**Files:** none (verification only)

- [ ] **Step 1: Install deps and confirm the existing suite is green**

Run:
```bash
cd scraper && bun install --frozen-lockfile && bun run typecheck && bun run test
```
Expected: typecheck exits 0; vitest reports all tests passing (including `tests/graded/ingest/poketrace-comp.test.ts` and `tests/graded/sources/poketrace.test.ts`). If anything fails here, STOP and report — it is a pre-existing issue, not introduced by this plan.

- [ ] **Step 2: Confirm the CLI command is recognized**

Run:
```bash
cd scraper && bun run cli run graded --help
```
Expected: help text lists the `poketrace-comp` job and the `--max-requests` / `--daily-floor` options. (No network call is made by `--help`.)

---

## Task 2: Add the `.dockerignore`

**Files:**
- Create: `scraper/.dockerignore`

- [ ] **Step 1: Write the `.dockerignore`**

Create `scraper/.dockerignore` with exactly:
```
node_modules
dist
coverage
.vitest-cache
.env
.env.local
*.log
.DS_Store
tests
.github
deploy
pnpm-lock.yaml
```
Rationale: runtime needs only `package.json`, `bun.lock`, `tsconfig.json`, and `src/`. Excluding `.env*` guarantees no local secrets leak into the image; excluding `deploy/` avoids the image containing its own deploy script; `pnpm-lock.yaml` is excluded because the image installs via `bun.lock`.

- [ ] **Step 2: Commit**

```bash
git add scraper/.dockerignore
git commit -m "build(scraper): add .dockerignore for the poketrace-comp image"
```

---

## Task 3: Add the Dockerfile

**Files:**
- Create: `scraper/Dockerfile`

- [ ] **Step 1: Write the Dockerfile**

Create `scraper/Dockerfile` with exactly:
```dockerfile
# syntax=docker/dockerfile:1
# Runs the existing poketrace-comp ingest CLI directly under Bun. Bun executes
# the TypeScript entry natively and resolves the @/* tsconfig path alias, so no
# tsx/transpile step is needed at runtime. Config is supplied via env vars
# (Secret Manager on Cloud Run); no secrets are baked in.
FROM oven/bun:1

WORKDIR /app

# Install dependencies first for layer caching. Runtime deps (commander,
# @supabase/supabase-js, dotenv, etc.) come from the frozen lockfile.
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

# Application source.
COPY tsconfig.json ./
COPY src ./src

# ENTRYPOINT is the fixed command; CMD holds the cap/floor so they can be
# overridden at the Cloud Run Job level (--args) without rebuilding the image.
# NOTE: invoke bun directly, NOT `bun run cli` — the npm `cli` script shells out
# to tsx, and bun->tsx->esbuild fails at runtime (Cannot find module cjs/index.cjs).
ENTRYPOINT ["bun", "src/cli.ts", "run", "graded", "poketrace-comp"]
CMD ["--max-requests", "9000", "--daily-floor", "200"]
```

- [ ] **Step 2: Build the image locally to verify it compiles**

Run (requires a local Docker daemon; if unavailable, skip to Step 3 and rely on Cloud Build during deploy):
```bash
cd scraper && docker build -t poketrace-comp:local .
```
Expected: build succeeds through all layers, ending with the `ENTRYPOINT`/`CMD` instructions. No `bun install` lockfile-mismatch error.

- [ ] **Step 3: Verify the entrypoint resolves (fails fast on missing env, which proves wiring)**

Run:
```bash
docker run --rm poketrace-comp:local --help
```
Expected: Commander prints the `poketrace-comp` help/usage (the `--help` flag is handled before any config load), confirming `bun run cli ... poketrace-comp` is correctly wired. (If Docker is unavailable, this is covered by the Cloud Build + manual execute in Task 5.)

- [ ] **Step 4: Commit**

```bash
git add scraper/Dockerfile
git commit -m "build(scraper): containerize the poketrace-comp ingest job"
```

---

## Task 4: Add the deploy script

**Files:**
- Create: `scraper/deploy/deploy.sh`

- [ ] **Step 1: Write `scraper/deploy/deploy.sh`**

Create `scraper/deploy/deploy.sh` with exactly:
```bash
#!/usr/bin/env bash
# Provision / update the Poketrace graded-comp ingest on GCP:
#   Artifact Registry image -> Cloud Run Job -> daily Cloud Scheduler trigger.
# Idempotent: safe to re-run to ship a new image or change configuration.
#
# Required env:
#   GCP_PROJECT                 target GCP project id
# Optional env (defaults shown):
#   GCP_REGION=us-central1
#   SCHEDULE="0 9 * * *"        Cloud Scheduler cron, UTC
#   MAX_REQUESTS=9000           hard request ceiling per run (10k/day plan limit)
#   DAILY_FLOOR=200             stop when x-ratelimit-daily-remaining < this
#   JOB_TIMEOUT=1800s           Cloud Run Job task timeout
# Secret values (read from env; required on FIRST run, reused thereafter):
#   POKETRACE_API_KEY, SUPABASE_URL, SUPABASE_SECRET_KEY
set -euo pipefail

: "${GCP_PROJECT:?set GCP_PROJECT to your GCP project id}"
REGION="${GCP_REGION:-us-central1}"
SCHEDULE="${SCHEDULE:-0 9 * * *}"
MAX_REQUESTS="${MAX_REQUESTS:-9000}"
DAILY_FLOOR="${DAILY_FLOOR:-200}"
JOB_TIMEOUT="${JOB_TIMEOUT:-1800s}"

REPO="slabbist"
IMAGE="${REGION}-docker.pkg.dev/${GCP_PROJECT}/${REPO}/poketrace-comp:latest"
JOB="poketrace-comp"
SCHED="poketrace-comp-daily"
RUN_SA="poketrace-comp-job@${GCP_PROJECT}.iam.gserviceaccount.com"
SCHED_SA="poketrace-comp-sched@${GCP_PROJECT}.iam.gserviceaccount.com"

# This script lives in scraper/deploy; the Docker build context is its parent.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_CONTEXT="$(dirname "$SCRIPT_DIR")"

gcloud config set project "$GCP_PROJECT" >/dev/null

echo "==> Enabling required APIs"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  cloudscheduler.googleapis.com \
  secretmanager.googleapis.com

echo "==> Artifact Registry repo ($REPO)"
gcloud artifacts repositories describe "$REPO" --location "$REGION" >/dev/null 2>&1 \
  || gcloud artifacts repositories create "$REPO" \
       --repository-format=docker --location "$REGION" \
       --description="Slabbist container images"

echo "==> Service accounts"
gcloud iam service-accounts describe "$RUN_SA" >/dev/null 2>&1 \
  || gcloud iam service-accounts create poketrace-comp-job \
       --display-name="Poketrace comp Cloud Run Job runtime"
gcloud iam service-accounts describe "$SCHED_SA" >/dev/null 2>&1 \
  || gcloud iam service-accounts create poketrace-comp-sched \
       --display-name="Poketrace comp Cloud Scheduler invoker"

echo "==> Secrets (Secret Manager)"
upsert_secret() {
  local name="$1" val="$2"
  if ! gcloud secrets describe "$name" >/dev/null 2>&1; then
    if [[ -z "$val" ]]; then
      echo "ERROR: secret $name does not exist and \$$name is empty. Export it and re-run." >&2
      exit 1
    fi
    gcloud secrets create "$name" --replication-policy=automatic
    printf '%s' "$val" | gcloud secrets versions add "$name" --data-file=-
  elif [[ -n "$val" ]]; then
    printf '%s' "$val" | gcloud secrets versions add "$name" --data-file=-
  else
    echo "    $name exists and \$$name is empty -> keeping current version"
  fi
  gcloud secrets add-iam-policy-binding "$name" \
    --member="serviceAccount:${RUN_SA}" \
    --role="roles/secretmanager.secretAccessor" >/dev/null
}
upsert_secret POKETRACE_API_KEY   "${POKETRACE_API_KEY:-}"
upsert_secret SUPABASE_URL        "${SUPABASE_URL:-}"
upsert_secret SUPABASE_SECRET_KEY "${SUPABASE_SECRET_KEY:-}"

echo "==> Build + push image via Cloud Build"
gcloud builds submit "$BUILD_CONTEXT" --tag "$IMAGE"

echo "==> Cloud Run Job ($JOB)"
gcloud run jobs deploy "$JOB" \
  --image "$IMAGE" \
  --region "$REGION" \
  --service-account "$RUN_SA" \
  --max-retries 0 \
  --task-timeout "$JOB_TIMEOUT" \
  --args="--max-requests,${MAX_REQUESTS},--daily-floor,${DAILY_FLOOR}" \
  --set-secrets="POKETRACE_API_KEY=POKETRACE_API_KEY:latest,SUPABASE_URL=SUPABASE_URL:latest,SUPABASE_SECRET_KEY=SUPABASE_SECRET_KEY:latest"

echo "==> Grant Scheduler permission to run the Job"
gcloud run jobs add-iam-policy-binding "$JOB" \
  --region "$REGION" \
  --member="serviceAccount:${SCHED_SA}" \
  --role="roles/run.invoker" >/dev/null

JOB_URI="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${GCP_PROJECT}/jobs/${JOB}:run"

echo "==> Cloud Scheduler ($SCHED, '$SCHEDULE' UTC)"
if gcloud scheduler jobs describe "$SCHED" --location "$REGION" >/dev/null 2>&1; then
  gcloud scheduler jobs update http "$SCHED" \
    --location "$REGION" \
    --schedule="$SCHEDULE" \
    --time-zone="Etc/UTC" \
    --uri="$JOB_URI" \
    --http-method=POST \
    --oauth-service-account-email="$SCHED_SA"
else
  gcloud scheduler jobs create http "$SCHED" \
    --location "$REGION" \
    --schedule="$SCHEDULE" \
    --time-zone="Etc/UTC" \
    --uri="$JOB_URI" \
    --http-method=POST \
    --oauth-service-account-email="$SCHED_SA"
fi

echo "==> Done."
echo "    Manual run:  gcloud run jobs execute $JOB --region $REGION"
echo "    Logs:        gcloud run jobs executions list --job $JOB --region $REGION"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scraper/deploy/deploy.sh
```

- [ ] **Step 3: Syntax-check the script**

Run:
```bash
bash -n scraper/deploy/deploy.sh && echo "SYNTAX OK"
```
Expected: prints `SYNTAX OK` with no parse errors.

- [ ] **Step 4: Lint with shellcheck if available (optional but preferred)**

Run:
```bash
command -v shellcheck >/dev/null && shellcheck scraper/deploy/deploy.sh || echo "shellcheck not installed — skipping"
```
Expected: either no findings, or the skip message. If shellcheck reports real issues (not style nags), fix them inline.

- [ ] **Step 5: Commit**

```bash
git add scraper/deploy/deploy.sh
git commit -m "build(scraper): add idempotent GCP deploy script for poketrace-comp"
```

---

## Task 5: Add the operator runbook

**Files:**
- Create: `scraper/deploy/README.md`

- [ ] **Step 1: Write `scraper/deploy/README.md`**

Create `scraper/deploy/README.md` with exactly:
````markdown
# Poketrace graded-comp ingest — GCP deployment

Deploys the existing `poketrace-comp` scraper job as a daily **Cloud Run Job**
triggered by **Cloud Scheduler**, capped at 9000 Poketrace requests/day.

There is no ingest code here — `deploy.sh` only packages
`scraper/src/cli.ts run graded poketrace-comp` and wires GCP around it.

## Prerequisites

- `gcloud` installed and authenticated: `gcloud auth login`
- A GCP project you can create resources in; export it: `export GCP_PROJECT=your-project-id`
- The three secret values exported in your shell **for the first deploy**
  (subsequent deploys reuse the stored versions if these are unset):

  ```bash
  export POKETRACE_API_KEY=...
  export SUPABASE_URL=https://<ref>.supabase.co
  export SUPABASE_SECRET_KEY=...        # Supabase secret/service-role key
  ```

## Deploy (first time and every redeploy)

```bash
cd scraper/deploy
./deploy.sh
```

The script is idempotent. It enables APIs, creates the Artifact Registry repo,
builds + pushes the image with Cloud Build, upserts the secrets, creates/updates
the Cloud Run Job, and creates/updates the daily Scheduler trigger. Re-running it
ships a new image and applies any config changes.

### Configuration (environment variables)

| Var | Default | Meaning |
|---|---|---|
| `GCP_PROJECT` | _(required)_ | Target project id. |
| `GCP_REGION` | `us-central1` | Region for Artifact Registry, Run, Scheduler. |
| `SCHEDULE` | `0 9 * * *` | Scheduler cron, UTC. |
| `MAX_REQUESTS` | `9000` | Hard per-run request ceiling (10k/day plan, 1k headroom). |
| `DAILY_FLOOR` | `200` | Stop when `x-ratelimit-daily-remaining` drops below this. |
| `JOB_TIMEOUT` | `1800s` | Cloud Run Job task timeout. |

## Smoke test

Run the job once on demand and watch it:

```bash
gcloud run jobs execute poketrace-comp --region "${GCP_REGION:-us-central1}" --wait
gcloud run jobs executions list --job poketrace-comp --region "${GCP_REGION:-us-central1}"
```

Then confirm a run row landed in Supabase (most recent first):

```sql
select id, status, started_at, finished_at, stats
from graded_ingest_runs
where source = 'poketrace-comp'
order by started_at desc
limit 1;
```

A healthy run has `status = 'completed'` and `stats.requests <= 9000`.

## Changing the cap (e.g. after a Poketrace plan upgrade)

Either redeploy with a new ceiling:

```bash
MAX_REQUESTS=20000 ./deploy.sh
```

…or update just the Job args without rebuilding:

```bash
gcloud run jobs update poketrace-comp --region "${GCP_REGION:-us-central1}" \
  --args="--max-requests,20000,--daily-floor,200"
```

## Troubleshooting

- **`gcloud builds submit` permission denied:** your account needs Cloud Build
  Editor + Artifact Registry Writer on the project, and the Cloud Build service
  account needs Artifact Registry Writer (granted automatically on first build in
  most projects).
- **Scheduler create fails needing an App Engine app:** in older projects run
  `gcloud app create --region=<region>` once, then re-run `./deploy.sh`.
- **Job exits non-zero:** check execution logs with
  `gcloud run jobs executions list --job poketrace-comp --region <region>` then
  `gcloud logging read` for the failing execution. The daily schedule retries
  the next day; `--max-retries 0` means no automatic in-run retry (intentional,
  to avoid wasting request budget).
````

- [ ] **Step 2: Commit**

```bash
git add scraper/deploy/README.md
git commit -m "docs(scraper): runbook for poketrace-comp GCP deployment"
```

---

## Task 6: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Confirm no application code changed and tests still pass**

Run:
```bash
cd scraper && bun run typecheck && bun run test
```
Expected: identical green result to Task 1 — this plan adds only Docker/deploy/doc files, so the suite is unaffected.

- [ ] **Step 2: Confirm the diff is exactly the four new files**

Run:
```bash
git diff --name-status main...HEAD
```
Expected (plus the two design/plan docs already committed):
```
A    scraper/.dockerignore
A    scraper/Dockerfile
A    scraper/deploy/README.md
A    scraper/deploy/deploy.sh
```
No `M` (modified) lines under `scraper/src/`. If any appear, revert them — the spec forbids ingest-logic changes.

- [ ] **Step 3: Report completion**

Summarize: files added, baseline tests green before and after, and that GCP provisioning itself (running `deploy.sh` against a real project) is an operator step requiring live GCP credentials — not part of this code change. Then proceed to `superpowers:finishing-a-development-branch`.

---

## Self-Review (completed by plan author)

- **Spec coverage:** Dockerfile + .dockerignore (spec "What changes in the scraper") → Tasks 2–3. deploy.sh (spec "Provisioning script") → Task 4. README runbook → Task 5. 9000 cap via `--max-requests` arg → Dockerfile CMD + Job `--args`. `--daily-floor 200` backstop → both. Secrets in Secret Manager + runtime SA → Task 4 `upsert_secret`. Scheduler daily trigger + invoker SA → Task 4. No schema/migration, no GH Actions change, no iOS change → enforced by Task 6 Step 2. Verification criteria (typecheck/tests green, build succeeds, bash -n clean, manual execute) → Tasks 1, 3, 4, 5, 6.
- **Placeholder scan:** none — every file's full content is inline.
- **Type/name consistency:** resource names are defined once at the top of `deploy.sh` (`JOB`, `SCHED`, `RUN_SA`, `SCHED_SA`, `IMAGE`, `REPO`) and reused; env-var names match `loadConfig` (`POKETRACE_API_KEY`, `SUPABASE_URL`, `SUPABASE_SECRET_KEY`) and the Cloud Run `--set-secrets` mapping; CLI flags match `cli.ts` (`--max-requests`, `--daily-floor`).
