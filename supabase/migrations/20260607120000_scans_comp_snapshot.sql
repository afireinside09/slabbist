-- supabase/migrations/20260607120000_scans_comp_snapshot.sql
--
-- Freeze the comp that justified an offer onto the scan at offer-send time.
-- Set by OfferUseCase.sendToOffer (via the updateScanComp outbox kind).
-- See plan: docs/superpowers/plans/2026-06-07-comp-snapshot-and-scan-photo-persistence.md

alter table scans add column if not exists comp_snapshot text;
alter table scans add column if not exists comp_snapshot_at timestamptz;

comment on column scans.comp_snapshot is
  'Immutable JSON-string blob (CompSnapshotWire) of the comp behind the offer, frozen at offer-send. Text, not jsonb: an audit/retrieval record mirroring the on-device GradedMarketSnapshot *JSON convention, not a server-side query target.';
comment on column scans.comp_snapshot_at is
  'Timestamp the comp_snapshot was frozen (the moment the lot was presented). NULL until the lot is sent to offer.';
