# Sub-project 12 — Marketplace, web dashboard, Android

Platform expansion and the monetization foundation.

## Scope

- iOS + Android + web — Android is a React Native or Kotlin native rewrite decision, web is the admin/reporting surface.
- Offline mode with sync on every platform.
- Push notifications (price alerts, pop shifts, team activity).
- Multi-device sync for the same store.
- Audit log for compliance.
- Data export / account portability.
- API for power users and integrations.
- **Marketplace foundation (monetization):**
  - Store profiles and discoverability
  - Inter-store trading/buying network
  - Anonymized aggregate comp data — "what hobby stores are actually paying"
  - Buylist syndication — stores publish buylists, collectors sell into them
  - Consignment workflow
  - Escrow / payment processing
  - Ratings and reviews
  - Shipping label generation

## Features captured

- iOS and Android apps
- Web dashboard
- Offline mode with sync
- Push notifications
- Multi-device sync
- Audit log
- Data export / portability
- Public API
- Marketplace features (all of the above)

## Dependencies

- Mostly everything — this is the expansion layer that presumes sub-projects 1–11.
