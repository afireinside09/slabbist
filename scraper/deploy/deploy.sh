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
