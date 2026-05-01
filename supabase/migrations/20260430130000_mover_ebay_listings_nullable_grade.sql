-- 20260430130000_mover_ebay_listings_nullable_grade.sql
-- Relax mover_ebay_listings: allow NULL grading_service / grade so the
-- ingest can keep listings that pass eBay's server-side "Graded" aspect
-- filter even when the title doesn't carry the grader's name. Previously
-- the matcher rejected anything without a "(PSA|BGS|...) <grade>" token in
-- the title, which threw out perfectly valid slabs whose sellers put the
-- grader only in eBay's item-specifics. The CHECK is rewritten to permit
-- NULL while still constraining non-null values to the known service set.

alter table public.mover_ebay_listings
  alter column grading_service drop not null;

alter table public.mover_ebay_listings
  alter column grade drop not null;

alter table public.mover_ebay_listings
  drop constraint if exists mover_ebay_listings_grading_service_check;

alter table public.mover_ebay_listings
  add constraint mover_ebay_listings_grading_service_check
  check (
    grading_service is null
    or grading_service in ('PSA','BGS','CGC','SGC','TAG','HGA','GMA')
  );
