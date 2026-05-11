-- supabase/tests/lot_offer_state_transitions.sql
--
-- Smoke test that the enum exists and the new columns are present + index'd.
-- The actual state-machine enforcement lives in the iOS OfferRepository (and
-- in /transaction-commit's `accepted` precondition); the database is a
-- typed dropbox.

begin;
select plan(4);
create extension if not exists pgtap;

select has_column('lots', 'vendor_id', 'lots has vendor_id');
select has_column('lots', 'lot_offer_state', 'lots has lot_offer_state');
select col_default_is('lots', 'lot_offer_state', 'drafting', 'lot_offer_state defaults to drafting');
select has_index('lots', 'lots_offer_state', array['store_id','lot_offer_state']::name[], 'index on (store_id, lot_offer_state) exists');

select * from finish();
rollback;
