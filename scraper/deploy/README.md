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
