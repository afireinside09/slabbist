# Marketing site → full iOS feature parity + conversion push

**Date:** 2026-06-07
**Status:** Design approved, pending spec review
**Surfaces:** `marketing/` (Next.js 16.2.4 + React 19 + Tailwind v4, Bun)

## Problem

The marketing site (`marketing/`) and the shipping iOS app have drifted apart in two directions:

1. **The app ships flagship features the site never mentions.** Pre-grade (camera grading + centering tool), Movers (market momentum), Grade Gains (raw→graded arbitrage), the Vendors registry, the Transactions ledger, and a hidden easter-egg surface are all invisible on the site. The site still sells a single idea — *"iPhone bulk scanner + real comps."*
2. **The site claims things the app does not appear to ship.** Role-based buy-price visibility "enforced in the database," Square/Shopify/QuickBooks integrations, signature capture, and print/email offer sheets read as present-tense capabilities. Some are roadmap; some overclaim.

The goal: make the marketing site reflect the app's real, full feature set, push hard on download intent, and tease the hidden easter egg **without naming what it is** — the user should discover it in the app.

## Goals

- Reframe the site around the app's actual scope: a buy-side operating system, not just a scanner.
- Add marketing coverage for every real flagship feature: Pre-grade, Movers, Grade Gains, Vendors, Transactions, offline-first sync.
- Strengthen download conversion.
- Add a dedicated easter-egg teaser that promises something hidden without revealing it (no "Psyduck," no "Pokédex," anywhere — copy, alt text, comments, filenames).
- Rewrite present-tense claims the app doesn't back into roadmap/future tense, and produce an explicit before/after list of every demoted claim.

## Non-goals

- No new dependencies, no Tailwind-class migration. Match the existing hand-built inline-SVG + `lib/tokens.ts` aesthetic exactly.
- No backend/API changes (the `/api/waitlist` flow stays as-is).
- No changes to the iOS app or Supabase schema.
- No real App Store download link yet — the app is closed beta; conversion CTA remains the waitlist, but copy leans into "download" intent for launch.

## Design direction (non-negotiable, from `.impeccable.md`)

Dark + gold OKLCH palette via `lib/tokens.ts` (`SLAB` tokens), Instrument Serif (headlines) + Inter Tight (body) + JetBrains Mono (data), 4pt spacing rhythm, WCAG 2.2 AA. All copy is hardcoded in components (no CMS/MDX). Reuse the `Icon` library in `components/icon.tsx`; add new icon strokes there if a feature needs one (e.g. grading, chart-up).

## Messaging architecture

New spine: **Scan it. Grade it. Comp it. Know the market. Make the offer.**

Four pillars replace the single scanner pitch:

1. **Capture & Comp** (already on site) — bulk scan, cert lookup (PSA/BGS/CGC/SGC/TAG), real comps from recent sales, margin ladder, offer sheets. Existing `FeatureRow` covers this.
2. **Pre-grade** (NEW) — camera grades a card to a PSA-equivalent composite + sub-grades (centering/corners/edges/surface) with a confidence read, plus a manual centering measurement tool. Angle: *grade a walk-in before you commit a dollar.*
3. **Movers** (NEW) — top gainers/losers by set and price tier, English/Japanese, 30-day sparklines. Angle: *see where the market's heading.*
4. **Grade Gains** (NEW) — raw→PSA-10 arbitrage finder with a live grading-fee stepper and per-set profit rows. Angle: *find the cards worth sending in.*

Plus back-office: Vendors registry, Transactions ledger, offline-first outbox sync. Plus the hidden delight (easter-egg teaser).

## Components

### New components (`components/marketing/`)

- **`intelligence-suite.tsx`** — homepage section presenting the three new pillars (Pre-grade, Movers, Grade Gains), each with a heading, benefit blurb, and a new inline-SVG mock. Follows the visibility-triggered animation pattern used by `feature-row.tsx` / `workflow.tsx`.
- **`easter-egg-teaser.tsx`** — dedicated standalone block. Cryptic copy + a faint, **unidentifiable** silhouette peeking from a screen edge (abstract shape, not the real character). Respects reduced-motion.

### New SVG mocks (inline, matching existing mock style in `hero.tsx` / `feature-row.tsx`)

- **Pre-grade mock** — a card frame with centering guides, a gold grade badge ("9.5"), four labeled sub-grade bars.
- **Movers mock** — stacked rows with green/red % deltas and mini sparklines.
- **Grade Gains mock** — raw→PSA-10 arrow, profit figure in mono gold, a fee-stepper chip.

Mocks live inside their feature components (consistent with how `hero.tsx` and `feature-row.tsx` inline their mocks today).

### Modified components / pages

- **`app/page.tsx`** — insert `<IntelligenceSuite>` (after `FeatureRow`) and `<EasterEggTeaser>` (before `Pricing` or `FinalCta`). Tighten the hero subhead via `hero.tsx`.
- **`components/marketing/hero.tsx`** — subhead promises grading + market intel, not only scanning. Headline unchanged.
- **`app/features/page.tsx`** — add feature-card sections for Pre-grade (grading + centering), Movers, Grade Gains, Vendors, Transactions, offline-first sync, and the easter-egg teaser. Apply overclaim fixes (below).
- **`app/for-shops/page.tsx`** — lead with Pre-grade ("grade the walk-in before you offer") alongside comps.
- **`app/for-vendors/page.tsx`** — add Movers + Grade Gains as show-floor market intel; emphasize offline-first.
- **`app/for-collectors/page.tsx`** — add Pre-grade ("grade your own") + a nod to the hidden encyclopedia; keep marketplace explicitly **planned**.
- **`app/press/page.tsx`** — boilerplate + stats updated to include grading & market intelligence.
- **`app/changelog/page.tsx`** — new version entry shipping Pre-grade, Movers, Grade Gains, and "a hidden surprise."
- **`app/layout.tsx`** + per-page `metadata` — meta descriptions mention grading + market intel.
- **`components/icon.tsx`** — add any new icon strokes the new sections need (e.g. grading/centering, chart-up), matching the existing 24-icon style.

## Easter-egg teaser content

Dedicated block, draft voice (final wording tunable):

> **There's something in here we didn't tell you about.**
> Keep the app open and stay sharp. Once in a while, something pokes its head in — blink and it's gone. Catch it, and a door opens. We won't say what's behind it. *Half the fun is finding out.*

Constraints:
- Never names or depicts the actual character or the screen it unlocks.
- Visual is an abstract silhouette peeking from an edge — not recognizable as the real asset.
- No spoilers in alt text, aria-labels, comments, or filenames (e.g. don't name a file `psyduck-*`).

## Overclaim fixes

During implementation, grep the iOS source to confirm before demoting any claim, then rewrite unbacked present-tense claims to roadmap/future tense. Produce an explicit before/after list of every change for user review.

Claims to verify and likely demote (present → "planned"):

- **Square / Shopify / QuickBooks integrations** — not found in app inventory → "Planned integrations."
- **Role-based buy-price visibility "enforced in the database"** — tenant `store_id` RLS exists, but per-role (associate vs owner) visibility within a store was not surfaced in the app → soften to roadmap unless found.
- **Signature capture, print/email offer sheets** — app has an offer review sheet (payment method/reference, mark-paid) but not these specific affordances → soften.

Claims to keep present-tense (app-backed):

- eBay / TCGplayer affiliate links, PSA/BGS/CGC/SGC/TAG cert support, real comps from recent sales, margin ladder, offline-first, free on iOS.

Claims already correctly framed as future:

- Collector marketplace and the 1% buyer fee — keep as "planned."

## Data flow

No runtime data flow changes. All content remains hardcoded in components as TypeScript arrays/JSX (matching current organization: `CAPABILITIES`, `FEATS`, `TIERS`, etc.). The waitlist API and Supabase admin client are untouched.

## Accessibility & motion

- All new sections meet WCAG 2.2 AA contrast against the dark palette.
- New animations gate on `prefers-reduced-motion` (match existing component pattern).
- New SVG mocks are decorative (`aria-hidden`) with the meaning carried by adjacent text; the easter-egg silhouette is decorative and unnamed.

## Testing / verification

- `cd marketing && bun run build` succeeds with no type errors.
- `bun run lint` clean.
- Manual review: every new section renders on home/features/audience pages; reduced-motion disables animation; no occurrence of the easter-egg's real name anywhere (`grep -ri psyduck marketing/`, `grep -ri pokedex marketing/`, `grep -ri cameo marketing/` all empty).
- Before/after overclaim list delivered to user.

## Out of scope / follow-ups

- Real App Store badge + link when the app exits closed beta.
- Actual product screenshots/video (current site is all inline SVG; keeping that).
- An interactive easter egg embedded on the marketing site itself (was offered, user chose a dedicated teaser block instead).
