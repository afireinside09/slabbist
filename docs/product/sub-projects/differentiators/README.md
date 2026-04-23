# Differentiators — prototype early

Features worth spiking on during earlier sub-projects to validate demand and pricing model. These don't map cleanly to one sub-project — they tend to be cross-cutting.

## The list

- **Event mode** — auto-adjust margins during set releases, major tournaments, card shows. Built on sub-project 7 (margin rules) with a time-window modifier layer.
- **Card show mode** — lightweight, offline-first, fast scanning profile. Already addressed natively by the offline-first architecture in sub-project 5. Surface as an explicit mode once we have real card-show usage data.
- **Fraud / fake detection** — suspicious cert numbers (reused, out-of-range), known counterfeits, label-vs-cert mismatch (the "C" option from OCR validation). Cross-cuts sub-projects 3, 5, and 9.
- **Price alert subscriptions** on specific cards — extends the want list (sub-project 7) with server-side alerting (sub-project 12 push).
- **Collection valuation for walk-in customers** — a consumer-facing lightweight version of bulk scan that a store runs for a walk-in. Essentially a pre-sale variant of sub-project 5 + 6.

## How to apply

When building a sub-project that the list above crosses into, think about the cross-cutting feature's hooks even if we're not implementing it. For example, in sub-project 3's scan pipeline, leave room for a label-OCR secondary pass (fraud detection) behind a feature flag.
