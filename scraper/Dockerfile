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
ENTRYPOINT ["bun", "src/cli.ts", "run", "graded", "poketrace-comp"]
CMD ["--max-requests", "9000", "--daily-floor", "200"]
