-- 20260430120000_mover_ebay_listings.sql
-- Active eBay listings cached per movers card. This table mirrors the
-- "movers" lifecycle: each scraper run TRUNCATEs and re-INSERTs, so
-- there is no historical record — only the listings most recently
-- observed for the cards currently in public.movers. The iOS card-
-- detail screen reads this through `get_mover_ebay_listings` to
-- render a horizontal carousel under the price-history chart.
--
-- Why no FK to public.movers:
--   public.movers is rebuilt wholesale by refresh_movers(); a CASCADE
--   delete during refresh would briefly empty this table even when
--   the same products survive into the new run. Holding (product_id,
--   sub_type_name) as descriptive non-FK columns keeps the listings
--   stable across movers refreshes — they're only cleared when the
--   eBay-listings ingest itself runs.
--
-- Accuracy notes:
--   - The scraper enforces a strict title match server-side before
--     inserting (card_number must appear in the title; grading
--     service + grade must match a regex; lot/bundle/proxy/repack
--     keywords reject the listing). This table therefore only holds
--     listings the scraper believes correspond to *this* card.
--   - Despite that, listings can drift over time (relistings, item
--     ends, price changes). Treat the table as a snapshot bound to
--     the most recent ingest run; refreshed_at lets the iOS UI show
--     "as of <when>" if useful.

create table if not exists public.mover_ebay_listings (
  id              bigserial primary key,
  product_id      int           not null references public.tcg_products(product_id) on delete cascade,
  sub_type_name   text          not null,
  ebay_item_id    text          not null,
  title           text          not null,
  price           numeric(12,2) not null,
  currency        text          not null default 'USD',
  url             text          not null,
  image_url       text,
  grading_service text          not null
                  check (grading_service in ('PSA','BGS','CGC','SGC','TAG','HGA','GMA')),
  grade           text          not null,
  buying_options  text,
  end_at          timestamptz,
  refreshed_at    timestamptz   not null default now(),

  -- (product_id, sub_type_name, ebay_item_id) is the natural identity:
  -- one listing can only match one card variant in our model, and a
  -- given variant can have many listings. Unique index lets the
  -- ingest function do ON CONFLICT DO UPDATE within a run.
  unique (product_id, sub_type_name, ebay_item_id)
);

-- Read path: per-card listings for the detail screen. Sorted by
-- price ASC so the carousel leads with the cheapest available copy.
create index if not exists mover_ebay_listings_card_price_idx
  on public.mover_ebay_listings (product_id, sub_type_name, price);

alter table public.mover_ebay_listings enable row level security;

drop policy if exists mover_ebay_listings_public_read on public.mover_ebay_listings;
create policy mover_ebay_listings_public_read
  on public.mover_ebay_listings
  for select
  using (true);

grant select on public.mover_ebay_listings to anon, authenticated;
grant usage, select on sequence public.mover_ebay_listings_id_seq
  to anon, authenticated;

-- ---------------------------------------------------------------
-- Read RPC: listings for one card on the detail screen.
-- ---------------------------------------------------------------

create or replace function public.get_mover_ebay_listings(
  p_product_id    int,
  p_sub_type_name text default 'Normal',
  p_limit         int  default 24
)
returns table (
  ebay_item_id    text,
  title           text,
  price           numeric,
  currency        text,
  url             text,
  image_url       text,
  grading_service text,
  grade           text,
  buying_options  text,
  end_at          timestamptz,
  refreshed_at    timestamptz
)
language sql
stable
as $$
  select l.ebay_item_id, l.title, l.price, l.currency, l.url, l.image_url,
         l.grading_service, l.grade, l.buying_options, l.end_at, l.refreshed_at
  from public.mover_ebay_listings l
  where l.product_id    = p_product_id
    and l.sub_type_name = p_sub_type_name
  order by l.price asc nulls last
  limit greatest(p_limit, 0);
$$;

grant execute on function public.get_mover_ebay_listings(int, text, int)
  to anon, authenticated;
