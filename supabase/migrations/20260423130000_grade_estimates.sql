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

create index grade_estimates_scan_id
  on grade_estimates (scan_id)
  where scan_id is not null;

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
