# Poketrace graded ingest on GCP — design

**Date:** 2026-06-04
**Branch:** `worktree-poketrace-gcp-ingest` (off `main`)
**Status:** approved design, pending implementation plan

## Goal

Run the existing `poketrace-comp` ingest as a daily, self-contained job on GCP,
capped at **9000 Poketrace requests/day** (10,000/day plan limit, 1000 headroom),
scoped to the newest "modern-era" cards.

The plan tier can be upgraded as the user base grows; the cap is a single
configurable value (`--max-requests`), not a structural constraint.

## Background

`scraper/src/graded/ingest/poketrace-comp.ts` already implements the retrieval:

- `runPoketraceCompIngest` loads candidate products **newest-set-first**
  (`grade_comp_groups` → `grade_comp_candidates_for_group`), English only
  (`category_id = 3`), excluding sets < 90 days old (no graded market yet), and
  only products with a market price and stale/absent comp (`resolved_at` null or
  > 7 days).
- For each candidate it searches Poketrace by `tcgplayer_id` (1 request), and on
  a match fetches PSA-10 detail (1 more request), upserting `tcg_grade_comp`.
- It already honours `--max-requests` (hard request ceiling) and `--daily-floor`
  (halt when the `x-ratelimit-daily-remaining` response header drops below the
  floor).
- It records a run row in `graded_ingest_runs` with stats.

Today the scraper's cron jobs run on **GitHub Actions** (see
`scraper/.github/workflows/`). There is **no** GCP or Docker infrastructure in
the repo. This work adds a GCP deployment for the poketrace-comp job only.

## Decisions (resolved during brainstorming)

1. **Reuse the existing job** and deploy it to GCP. No new retrieval logic.
2. **Cap = 9000 requests/day (hard).** Run with `--max-requests 9000`. The
   `--daily-floor 200` guard stays as a backstop against request-count drift.
3. **"Modern era" is implicit** — newest-first ordering + the 9000 cap means
   only the most recent cards are ever reached; vintage sets at the bottom of
   the list are never touched. **No schema migration, no new published_on
   cutoff.**
4. **Cloud Run Job + Cloud Scheduler**, provisioned via a checked-in `gcloud`
   deploy script (no Terraform; repo has no existing IaC).

## Scope

### In scope
- `scraper/Dockerfile` + `scraper/.dockerignore` — package the Bun CLI.
- `scraper/deploy/deploy.sh` — idempotent gcloud provisioning script.
- `scraper/deploy/README.md` — operator runbook.

### Explicitly out of scope
- Any change to `poketrace-comp.ts`, `poketrace.ts`, `cli.ts`, or other ingest
  logic. (If a defect surfaces it is a separate change.)
- Any Supabase schema migration or new DB object.
- iOS app changes.
- Changes to the existing GitHub Actions workflows. (The GH Actions path is left
  intact; GCP is additive. Whether to later retire the GH path is a separate
  decision.)

## Architecture

```
Cloud Scheduler (daily cron, 0 9 * * * UTC by default)
        │ invokes via Cloud Run Admin API (run.jobs.run)
        ▼
Cloud Run Job  ──pulls image──► Artifact Registry
   │  env from Secret Manager:
   │    POKETRACE_API_KEY, SUPABASE_URL, SUPABASE_SECRET_KEY
   │  command: bun run cli run graded poketrace-comp
   │           --max-requests 9000 --daily-floor 200
   ▼
 Supabase  (tcg_grade_comp upsert + graded_ingest_runs row)
```

### Components

**Dockerfile (`scraper/Dockerfile`)**
- Base: official `oven/bun` image (version pinned to match `package.json`
  engines / CI `setup-bun`).
- Copy `package.json` + lockfile, `bun install --frozen-lockfile`, copy source.
- `ENTRYPOINT`/`CMD` runs the CLI. The 9000 cap and floor are passed as CMD args
  (overridable at the Cloud Run Job level via `--args`), so the cap can be tuned
  without rebuilding the image.
- Reads config from env vars only (the existing `loadConfig` already supports
  this; `.env*` files are dockerignored).

**Cloud Run Job**
- Runs to completion and exits — no HTTP server, no idle billing.
- Single task, no parallelism (the ingest is inherently sequential against one
  rate-limited upstream).
- Task timeout generous enough for a 9000-request walk (default **30 min**).
- **Max retries = 0**: the job is safely re-runnable (idempotent upserts + the
  7-day staleness gate), so an automatic mid-budget retry would waste request
  budget rather than help. A failed run is picked up by the next day's schedule.
- Env vars sourced from Secret Manager secret references.

**Cloud Scheduler**
- One job, cron `0 9 * * *` (UTC), configurable via a script variable.
- Targets the Cloud Run Admin API `:run` endpoint for the Job, authenticated
  with a dedicated service account holding `roles/run.invoker` (or the minimal
  `run.jobs.run` permission) on the Job.

**Secret Manager**
- Three secrets: `POKETRACE_API_KEY`, `SUPABASE_URL`, `SUPABASE_SECRET_KEY`.
- Values supplied by the operator's shell environment at deploy time; never
  committed. The Job's runtime service account gets
  `roles/secretmanager.secretAccessor` on each.

### Provisioning script (`scraper/deploy/deploy.sh`)

Idempotent and re-runnable. Reads configuration from environment variables with
sensible defaults:

| Var | Default | Meaning |
|---|---|---|
| `GCP_PROJECT` | (required) | target project id |
| `GCP_REGION` | `us-central1` | region for AR, Run, Scheduler |
| `SCHEDULE` | `0 9 * * *` | Scheduler cron (UTC) |
| `MAX_REQUESTS` | `9000` | passed to the CLI |
| `DAILY_FLOOR` | `200` | passed to the CLI |
| `JOB_TIMEOUT` | `1800s` | Cloud Run Job task timeout |

Steps (each guarded so re-runs update rather than fail):
1. `gcloud services enable` — Cloud Run, Cloud Build, Artifact Registry,
   Cloud Scheduler, Secret Manager.
2. Create the Artifact Registry Docker repo if absent.
3. Build + push the image via **Cloud Build** (`gcloud builds submit`) so no
   local Docker daemon is required.
4. Create/update the three Secret Manager secrets from the operator's env
   (skip writing a new version if the value is unchanged / unset, with a clear
   warning).
5. Create/update the runtime service account; grant `secretAccessor`.
6. `gcloud run jobs deploy` the Job with image, region, secrets-as-env, args,
   timeout, retries=0.
7. Create/update the scheduler service account; grant invoke on the Job.
8. Create/update the Cloud Scheduler job.

### Runbook (`scraper/deploy/README.md`)
- Prerequisites: `gcloud` authenticated, `GCP_PROJECT` set, the three secret
  values exported.
- One-time setup vs. redeploy (both are just `./deploy.sh`).
- Manual smoke test: `gcloud run jobs execute <job> --region <region>` then
  inspect logs and the latest `graded_ingest_runs` row.
- How to change the cap (set `MAX_REQUESTS` and redeploy, or edit the Job args
  directly) — relevant when the Poketrace plan is upgraded.

## Error handling
- The CLI already exits non-zero on failure; Cloud Run marks the execution
  failed and surfaces logs. No automatic retry (see above) — the daily schedule
  is the recovery mechanism.
- The `--daily-floor` guard prevents exhausting the upstream daily quota even if
  request counting drifts.
- Idempotent upserts mean a partial run followed by a re-run causes no
  duplication or corruption.

## Verification / success criteria
- `bun run typecheck` and the existing `poketrace-comp` tests stay green
  (no logic changed — this confirms the worktree baseline is intact).
- `scraper/Dockerfile` builds successfully (locally `docker build` or via
  Cloud Build).
- `deploy.sh` passes `bash -n` and a shellcheck-clean review; re-running it is a
  no-op-or-update, never a hard failure on existing resources.
- A manual `gcloud run jobs execute` produces a `graded_ingest_runs` row with
  `status = completed` and `requests <= 9000`.

## Risks / open notes
- Secret values are operator-supplied at deploy time; the script must never echo
  or commit them.
- Cloud Build needs the Artifact Registry repo and appropriate Cloud Build
  service-account permissions; the script enables APIs but the operator's
  account must have project-level rights to create these resources (documented
  in the runbook).
- The 30-min timeout assumes 9000 sequential requests complete comfortably; if
  upstream latency makes that tight, raise `JOB_TIMEOUT`.
