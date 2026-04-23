-- Enums used across tenant, scan, and lot tables.
create type store_role as enum ('owner', 'manager', 'associate');
create type lot_status as enum ('open', 'closed', 'converted');
create type grader as enum ('PSA', 'BGS', 'CGC', 'SGC', 'TAG');
create type scan_status as enum ('pending_validation', 'validated', 'validation_failed', 'manual_entry');
