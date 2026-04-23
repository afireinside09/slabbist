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
