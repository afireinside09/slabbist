# Marketing overclaim reconciliation — 2026-06-07

Claims rewritten because the shipped iOS app does not back them (verified via grep in Task 1).

| Claim (before) | Where it lived | Status | After |
|---|---|---|---|
| Role-based buy-price visibility "enforced in the database" (owner sees comp/cost/margin, associate sees buy only) | hero capability; feature-row 4th tab + MarginRulesPanel; features COUNTER + BACK_OFFICE; for-shops point; changelog v0.8.0; **about page paragraph**; **security page hero + "Role enforcement" pillar** | NOT FOUND in app (a `StoreRole` enum exists at `ios/slabbist/slabbist/Core/Models/StoreMember.swift:4-5` but is never used to gate buy-price/comp/margin visibility in any view — model/repo/DTO plumbing only, zero role-branching in Features/) | Replaced with the real margin ladder; the about/security role claims reframed to **multi-tenant `store_id` tenant isolation** (that IS real via RLS) |
| Event-mode / per-grader / per-set margin modifiers; rule audit log | feature-row MarginRulesPanel; features; for-shops/for-vendors points; changelog v0.7.0 | NOT FOUND (PerGrader hits are pre-grade DTOs; per-set hits are Movers caching) | Replaced with real tier-based margin ladder |
| Print/email offer sheets | features COUNTER; for-shops; for-vendors subtitle; **homepage workflow Step 05**; **about page**; changelog v0.9.0 | NOT FOUND (only incidental hit: a "printed frame edge" comment) | "Offer sheet, ready to present" (on-screen lot total + line items + payment method/ref + mark paid); workflow Step 05 → present offer → ledger |
| On-device signature capture / signed PDF | features COUNTER; for-shops; for-vendors; **homepage workflow Step 05**; changelog v0.9.0 | NOT FOUND (only incidental hit: SF Symbol `square.and.arrow.up`) | Removed (the now-orphaned `signature` icon was also deleted from the Icon library) |
| Square / Shopify / QuickBooks integrations + CSV/PDF exports | features IntegrationsSection + BACK_OFFICE; for-vendors | NOT FOUND (only incidental hits: SF Symbol names containing "square") | Labeled "POS & accounting (planned)" |
| Collector marketplace, escrow, inspection, reputation import | for-collectors | NOT FOUND (always roadmap) | Kept but explicitly marked "(planned)"; real today-features lead |

If Task 1 found any of these CONFIRMED in code, that row is omitted and the claim was kept present-tense. All four disputed capabilities resolved to NOT FOUND, so every row above is a demotion.
