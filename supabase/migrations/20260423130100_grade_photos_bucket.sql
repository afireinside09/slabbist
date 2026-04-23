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
