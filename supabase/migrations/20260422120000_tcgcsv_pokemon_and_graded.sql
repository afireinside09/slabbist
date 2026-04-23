-- 20260422120000_tcgcsv_pokemon_and_graded.sql
-- Slabbist sub-project 2: raw Pokémon catalog (tcgcsv.com) + graded card data.
-- Raw and graded domains are intentionally decoupled (no FKs between them).

-- =============================================================================
-- Raw domain (tcg_*)
-- =============================================================================

create table if not exists public.tcg_categories (
  category_id     int primary key,
  name            text not null,
  modified_on     timestamptz
);

create table if not exists public.tcg_groups (
  group_id          int primary key,
  category_id       int not null references public.tcg_categories(category_id) on delete cascade,
  name              text not null,
  abbreviation      text,
  is_supplemental   boolean not null default false,
  published_on      date,
  modified_on       timestamptz
);
create index if not exists tcg_groups_category_id_idx on public.tcg_groups(category_id);

create table if not exists public.tcg_products (
  product_id          int primary key,
  group_id            int not null references public.tcg_groups(group_id) on delete cascade,
  category_id         int not null,
  name                text not null,
  clean_name          text,
  image_url           text,
  url                 text,
  modified_on         timestamptz,
  image_count         int,
  is_presale          boolean not null default false,
  presale_release_on  date,
  presale_note        text,
  card_number         text,
  rarity              text,
  card_type           text,
  hp                  text,
  stage               text,
  extended_data       jsonb
);
create index if not exists tcg_products_group_id_idx on public.tcg_products(group_id);
create index if not exists tcg_products_card_number_idx on public.tcg_products(card_number);

create table if not exists public.tcg_scrape_runs (
  id               uuid primary key default gen_random_uuid(),
  category_id      int not null,
  started_at       timestamptz not null default now(),
  finished_at      timestamptz,
  status           text not null default 'running' check (status in ('running','completed','failed','stale')),
  groups_total     int not null default 0,
  groups_done      int not null default 0,
  products_upserted int not null default 0,
  prices_upserted  int not null default 0,
  error_message    text
);

create table if not exists public.tcg_prices (
  product_id         int not null references public.tcg_products(product_id) on delete cascade,
  sub_type_name      text not null,
  low_price          numeric(12,2),
  mid_price          numeric(12,2),
  high_price         numeric(12,2),
  market_price       numeric(12,2),
  direct_low_price   numeric(12,2),
  updated_at         timestamptz not null default now(),
  primary key (product_id, sub_type_name)
);
create index if not exists tcg_prices_product_id_idx on public.tcg_prices(product_id);

create table if not exists public.tcg_price_history (
  id                 bigserial primary key,
  scrape_run_id      uuid not null references public.tcg_scrape_runs(id) on delete cascade,
  product_id         int not null references public.tcg_products(product_id) on delete cascade,
  sub_type_name      text not null,
  low_price          numeric(12,2),
  mid_price          numeric(12,2),
  high_price         numeric(12,2),
  market_price       numeric(12,2),
  direct_low_price   numeric(12,2),
  captured_at        timestamptz not null default now()
);
create index if not exists tcg_price_history_product_captured_idx
  on public.tcg_price_history(product_id, captured_at desc);

-- =============================================================================
-- Graded domain (graded_*)
-- =============================================================================

create table if not exists public.graded_card_identities (
  id              uuid primary key default gen_random_uuid(),
  game            text not null default 'pokemon',
  language        text not null check (language in ('en','jp')),
  set_name        text not null,
  set_code        text,
  year            int,
  card_number     text,
  card_name       text not null,
  variant         text,
  created_at      timestamptz not null default now()
);
create index if not exists graded_card_identities_lookup_idx
  on public.graded_card_identities(set_code, card_number);
create unique index if not exists graded_card_identities_unique_idx
  on public.graded_card_identities(game, language, set_name, card_number, coalesce(variant,''));

create table if not exists public.graded_cards (
  id               uuid primary key default gen_random_uuid(),
  identity_id      uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service  text not null check (grading_service in ('PSA','CGC','BGS','SGC','TAG')),
  cert_number      text not null,
  grade            text not null,
  graded_at        date,
  source_payload   jsonb,
  created_at       timestamptz not null default now(),
  unique (grading_service, cert_number)
);
create index if not exists graded_cards_identity_idx on public.graded_cards(identity_id);

create table if not exists public.graded_card_pops (
  id                bigserial primary key,
  identity_id       uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service   text not null,
  grade             text not null,
  population        int not null,
  captured_at       timestamptz not null default now()
);
create index if not exists graded_card_pops_identity_captured_idx
  on public.graded_card_pops(identity_id, captured_at desc);

create table if not exists public.graded_market (
  identity_id       uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service   text not null,
  grade             text not null,
  low_price         numeric(12,2),
  median_price      numeric(12,2),
  high_price        numeric(12,2),
  last_sale_price   numeric(12,2),
  last_sale_at      timestamptz,
  sample_count_30d  int not null default 0,
  sample_count_90d  int not null default 0,
  updated_at        timestamptz not null default now(),
  primary key (identity_id, grading_service, grade)
);
create index if not exists graded_market_identity_idx on public.graded_market(identity_id);

create table if not exists public.graded_market_sales (
  id                 bigserial primary key,
  identity_id        uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service    text not null,
  grade              text not null,
  source             text not null,
  source_listing_id  text not null,
  sold_price         numeric(12,2) not null,
  sold_at            timestamptz not null,
  title              text,
  url                text,
  captured_at        timestamptz not null default now(),
  unique (source, source_listing_id)
);
create index if not exists graded_market_sales_sold_at_idx on public.graded_market_sales(sold_at desc);
create index if not exists graded_market_sales_lookup_idx
  on public.graded_market_sales(identity_id, grading_service, grade);

create table if not exists public.graded_cert_sales (
  id                 bigserial primary key,
  graded_card_id     uuid not null references public.graded_cards(id) on delete cascade,
  source             text not null,
  source_listing_id  text not null,
  sold_price         numeric(12,2) not null,
  sold_at            timestamptz not null,
  title              text,
  url                text,
  captured_at        timestamptz not null default now(),
  unique (source, source_listing_id)
);
create index if not exists graded_cert_sales_card_idx on public.graded_cert_sales(graded_card_id);

create table if not exists public.graded_ingest_runs (
  id              uuid primary key default gen_random_uuid(),
  source          text not null,
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,
  status          text not null default 'running' check (status in ('running','completed','failed','stale')),
  stats           jsonb not null default '{}'::jsonb,
  error_message   text
);

-- =============================================================================
-- RLS: public read, service-role write.
-- =============================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'tcg_categories','tcg_groups','tcg_products','tcg_prices','tcg_price_history','tcg_scrape_runs',
    'graded_card_identities','graded_cards','graded_card_pops','graded_market',
    'graded_market_sales','graded_cert_sales','graded_ingest_runs'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_public_read', t);
    execute format('create policy %I on public.%I for select using (true)', t || '_public_read', t);
  end loop;
end $$;
