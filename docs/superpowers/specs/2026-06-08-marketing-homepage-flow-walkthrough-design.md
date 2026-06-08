# Marketing homepage → hero-flow walkthrough

**Date:** 2026-06-08
**Status:** Design approved, pending spec review
**Surfaces:** `marketing/` (Next.js 16.2.4 + React 19 + Tailwind v4, Bun)

## Problem

The marketing homepage explains Slabbist as a **high-level feature list** rather than
showing the product in motion. It reads as generic: a hero, a tabbed feature row, a
three-pillar "intelligence suite," and a numbered process strip — none of which let a
prospective dealer *watch the app do the job*. The screens shown are abstract inline-SVG
mocks that don't resemble the shipping app.

This **revises the homepage approach** of `2026-06-07-marketing-ios-feature-parity-design.md`.
That spec deliberately added high-level coverage of every flagship feature (the four-pillar
spine, `IntelligenceSuite`, `FeatureRow`). We now want the homepage to walk the end-user
through the app's actual **flow**, end to end. The parity spec's work on the other pages
(`/features`, audience pages), the easter-egg teaser, and the overclaim demotions remains
valid and is **out of scope** here.

## Goal

Rebuild the homepage as a single continuous narrative of the core buy-side flow —
**scan → comp → margin → offer → paid** — rendered as high-fidelity recreations of the
real iOS screens, so the page reads as "this is the actual app working," not a feature
brochure. Follow with a compact section for the three secondary flows.

## Non-goals

- No new dependencies. Match the existing hand-built inline-SVG + `lib/tokens.ts` aesthetic
  and the no-CMS, hardcoded-content architecture.
- No backend/API changes (`/api/waitlist` untouched).
- No changes to the iOS app or Supabase schema.
- No changes to `/features` or the audience pages in this pass — they keep the
  feature-parity breadth from the prior spec.
- No real screenshots/photos or video — screens are code-built recreations.

## Design direction (non-negotiable, from `.impeccable.md`)

Dark + gold OKLCH palette via `lib/tokens.ts` (`SLAB`), Instrument Serif (headlines) +
Inter Tight (body) + JetBrains Mono (data/metrics), 4pt spacing, WCAG 2.2 AA, hairlines
not shadows, gold rare and load-bearing. Numbers are first-class (mono). Reuse `Icon`
in `components/icon.tsx`; add strokes there if a screen needs one.

## Page structure

New `app/page.tsx` section order:

```
Nav → Hero (tightened subhead) → FlowWalkthrough (NEW) → BeyondTheOffer (NEW)
    → EasterEggTeaser → Pricing (free note) → FinalCta → Footer
```

**Removed from the homepage** (roles absorbed by the two new sections):
`FeatureRow`, `Workflow`, `IntelligenceSuite`. Delete each component file only after
verifying it has no other importer; otherwise leave the file and just drop it from
`page.tsx`.

## Components

### `components/marketing/flow-walkthrough.tsx` (NEW) — the centerpiece

A two-column "pinned device, advancing screens" section.

- **Layout:** a **sticky** iPhone frame (reuse the device-frame styling from `hero.tsx`)
  on one side; a column of **copy beats** (step number, serif title, body) on the other.
- **Activation:** an `IntersectionObserver` watches each copy beat; the most-visible beat
  sets the active step index. No scroll-position listeners.
- **Screen transition:** the phone renders the active step's screen; steps **crossfade via
  opacity** (compositor-friendly). The non-active screens are not visually shown.
- **Five steps** (the real hero flow), each a high-fidelity screen recreation:
  1. **Scan the stack** — BulkScan: a list of scan rows filling in with comps; pending /
     offline badges on rows awaiting validation/comp.
  2. **The defensible number** — Comp detail: reconciled headline price, per-source rows
     (price / range / trend / confidence), the **per-grade ladder** (raw → top grade),
     a history sparkline.
  3. **Set your margin** — Lot view: per-line buy prices computed as comp × margin, with
     the margin-mode toggle.
  4. **Send the offer** — Offer sheet: total, per-slab line items, payment method /
     reference.
  5. **Mark it paid** — an immutable transaction receipt in the ledger.
- **Fidelity:** each screen is grounded in the actual SwiftUI views — read
  `ios/slabbist/slabbist/Features/{Scanning,Comp,Lots,Offers,Transactions}` for real
  layout, labels, and states, and recreate them with `SLAB` tokens + inline SVG/HTML.
- **Sample data:** realistic and hardcoded (real card/set names, plausible grades, a
  believable ladder and margin math). Stored as a typed array/JSX in the component,
  matching the existing `CAPABILITIES`/`FEATS` organization.

### `components/marketing/beyond-the-offer.tsx` (NEW) — compact secondary section

Three tight beats — **Pre-grade**, **Movers**, **Grade Gains** — each with a heading,
one-line benefit, and a mini-screen. Reuse and upgrade the existing Pre-grade / Movers /
Grade-Gains mocks currently living in `IntelligenceSuite`. Framing: the offer is the
spine; this is the market intelligence around it.

### Modified

- **`app/page.tsx`** — new section order above; remove the three replaced sections.
- **`components/marketing/hero.tsx`** — tighten the subhead to set up the walkthrough
  (promise the flow, invite the scroll). Headline unchanged.
- **`components/marketing/nav.tsx`** — remove the **Pricing** link; add a **"How it works"**
  link anchoring to the walkthrough section (`/#how-it-works`).
- **`components/marketing/footer.tsx`** — remove the **Pricing** link.

## Responsive & motion (degradation is part of the design)

- **`prefers-reduced-motion: reduce`** and **mobile (≤720px):** the section degrades to a
  **stacked, static** layout — no pinning, no morph. Each step renders its own screen
  inline, above its copy, in source order. Reuse the existing
  `.slab-feature-panel { position: static !important }` responsive hook pattern; gate the
  pinning/observer behavior on a `matchMedia('(prefers-reduced-motion: reduce)')` check in
  JS (the CSS blanket reduced-motion reset cannot stop JS-driven state).
- The sticky column never traps keyboard focus; copy is plain readable text in source
  order regardless of layout mode.

## Accessibility

- WCAG 2.2 AA contrast throughout (the `dim` token now passes after the prior audit fix).
- Recreated screens are decorative: `aria-hidden`, with all meaning carried by the adjacent
  copy beats.
- Step activation must not move focus or announce; it is a visual enhancement only.

## Data flow

No runtime data-flow changes. All content is hardcoded in components as TypeScript
arrays/JSX. The waitlist API and Supabase admin client are untouched.

## Testing / verification

- `cd marketing && bun run build` succeeds with no type errors (the real gate; lint is
  baseline-red per repo convention).
- Reduced-motion: section renders stacked and static (no pin, no crossfade).
- Mobile (≤720px): section renders stacked and static.
- No **Pricing** link in nav or footer; **"How it works"** link scrolls to the walkthrough.
- No regressions on `/features` or audience pages.
- Manual review: the five screens read as the real app; the narrative flows scan → paid.

## Out of scope / follow-ups

- `/features` and audience-page restructuring around flows (a later pass if desired).
- Real App Store badge/link when the app exits closed beta.
- Real screenshots/video.
