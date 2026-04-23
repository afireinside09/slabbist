# Sub-project 6 — Store workflow: transactions, vendor DB, offers

Turns a lot into an actual business transaction.

## Scope

- Vendor / customer contact database with purchase history.
- Offer generation from a lot: attach vendor, apply margin rule to per-scan comp, produce total offered price.
- Transaction log — lot → offer → transaction with timestamps, payment method, who did the buy.
- "Show customer" mode — a presenter view that strips internal margin data, shows only clean comp numbers.
- Printable / emailable offer sheets (PDF via server-side render or PDFKit).
- QR code receipts linking back to the comp data for transparency.
- Digital signature capture on iPad for buy agreements.
- ID capture / verification for large buys (compliance).

## Features captured

- Vendor/customer contact database with purchase history
- Shared store buylist with target buy prices (referenced here, owned by sub-project 7)
- Transaction log
- "Show customer" mode
- Printable/emailable offer sheets
- QR code receipts
- Digital signature capture
- ID capture for large buys
- End-of-day recap (partial — see sub-project 8)

## Dependencies

- Sub-projects 1 (roles), 5 (lots)

## Unblocks

- Sub-project 7 (margin rules plug into offer generation)
- Sub-project 8 (analytics aggregate transactions)
