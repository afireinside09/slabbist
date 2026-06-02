# Slabbist Glossary

Domain vocabulary, grounded in how the specs use each term. Definitions are durable; for the mechanics behind a term, follow the value loop that uses it (`value-loops.md`).

| Term | Definition |
|---|---|
| **Slab** | A graded Pokémon card in a PSA/CGC/BGS/SGC/TAG holder. The primary buy unit. |
| **Cert number** | The unique serial on the slab holder (e.g. PSA 12345678). OCR'd from the label during a scan. |
| **Cert** | The certification on the slab — grader + grade (e.g. "PSA 10", "CGC 9.5"). |
| **Grade** | The numeric score (1–10, including half-grades). Each grade has its own market price. |
| **Grader / grading service** | The certifier: PSA, CGC, BGS, SGC, TAG. Each has its own pricing market and pop reports. |
| **Comp** | The market valuation of a graded slab from a data source. Includes a headline price, per-grade ladder, and metadata. |
| **Headline price** | The market price for the exact (grader, grade) of the slab in hand — the anchor for an offer. |
| **Per-grade ladder** | The matrix of prices across Raw / lower grades / 10 for the card. Supports crack-and-resubmit ("what's the upside if I regrade?") reasoning. |
| **Source** | The data feed behind a comp — e.g. `pokemonpricetracker`, `poketrace`. See `architecture-map.md`. |
| **Reconciled** | When multiple sources exist, the blended headline (e.g. average), with fallback to a single source if another fails. |
| **Fanout** | Fetching multiple comp sources in parallel on one request, failures isolated per source. |
| **Watchlist** | The curated subset of graded slabs the scraper tracks on a schedule. Not the whole catalog. |
| **Lot** | A named bundle of scans a vendor is selling. Stateful, from open to paid. |
| **Scan** | A single slab inside a lot — its cert, grade, comp, and buy price. |
| **Offer** | The store's proposed total and per-line prices sent to a vendor. Stateful: presented → accepted/declined. |
| **Buy price** | The store's per-slab offer, derived from comp × margin; the operator can override any line. |
| **Vendor ask** | A fallback manual-input price field for a scan. |
| **Margin** | The store's profit multiplier applied to comp (per-lot or per-store default). |
| **Vendor** | A contact in the store's vendor DB, with queryable purchase history. Store-scoped. |
| **Transaction** | The immutable ledger row created when an offer is paid. Line items snapshot vendor name, comps, and buy prices; voids are new rows, nothing mutates. |
| **Raw** | An ungraded, TCGPlayer-indexed card. Decoupled from graded identities (no FKs). |
| **Graded identity** | The normalized tuple `(game, language, set, card_number, variant, grader, cert_number)` that maps to graded comps. |
| **Pop report** | Grading population stats (how many copies graded, distribution by grade). Signals submission difficulty / gem-rate; not a comp source. |
| **Grade gains** | The profit from grading a raw card — the spread between its graded comp and its raw price (net of grading fee). Used to find high-ROI submissions. |
| **Trend** | A source-provided price direction (up / down / stable). |
| **Confidence** | A source-provided trust signal for a comp, driven by sale count and recency. |
| **Outbox** | The on-device queue of pending writes that sync to Supabase when online. The offline-first mechanism. |
| **store_id** | The multi-tenant scope key. All data tables are store-scoped via RLS. |
