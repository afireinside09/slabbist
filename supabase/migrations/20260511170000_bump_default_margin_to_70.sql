-- Bump the default offer percentage from 0.60 to 0.70.
--
-- The iOS Margin picker now ranges 70%-100% (in 5% increments), and the
-- in-app Margin Ladder defaults to a floor of 0.70 for slabs under the
-- lowest threshold. Anything below 0.70 in existing rows is clamped up so
-- the picker can render the value within its slider range and so the
-- ladder's "floor" assumption holds.
--
-- Check constraint stays at [0,1] — admins can still write any valid
-- percentage via direct SQL; the iOS surfaces are what enforce the 70%
-- floor for new edits.

alter table stores
  alter column default_margin_pct set default 0.7000;

update stores
   set default_margin_pct = 0.7000
 where default_margin_pct < 0.7000;

update lots
   set margin_pct_snapshot = 0.7000
 where margin_pct_snapshot is not null
   and margin_pct_snapshot < 0.7000;
