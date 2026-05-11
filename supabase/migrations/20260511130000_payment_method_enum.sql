-- supabase/migrations/20260511130000_payment_method_enum.sql

create type payment_method as enum ('cash', 'check', 'store_credit', 'digital', 'other');
