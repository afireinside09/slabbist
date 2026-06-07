# Marketing Site iOS Feature Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the `marketing/` site so it reflects the iOS app's real, full feature set (adding Pre-grade, Movers, Grade Gains, Vendors, Transactions, offline-first), pushes download intent, teases the hidden easter egg without naming it, and rewrites present-tense claims the app does not back into roadmap/planned framing.

**Architecture:** All marketing UI is hand-built React client/server components using inline styles driven by the `SLAB` token map (`lib/tokens.ts`) and the `Icon` library (`components/icon.tsx`). Content lives hardcoded in components as typed arrays/JSX — there is no CMS, MDX, or component test runner. New work follows the exact existing patterns: `IntersectionObserver` visibility gating, inline-SVG mocks, OKLCH dark+gold palette, Instrument Serif / Inter Tight / JetBrains Mono, and the global keyframes (`sbmRise`, `sbmFade`, `sbmScanLine`, `sbmPop`) already defined in `globals.css` (which also globally neutralizes animation under `prefers-reduced-motion`).

**Tech Stack:** Next.js 16.2.4 (App Router), React 19, Tailwind v4 (configured but unused in components), Bun.

---

## Conventions & verification model (read first)

- **No component test runner exists.** "Verify" steps use the real project gates: `bun run lint` (fast, per task) and `bun run build` (type + build check, at phase boundaries). This matches the codebase — do not introduce Jest/Vitest for marketing components (Rule 11: match conventions).
- **Next 16 differs from training data.** Per `marketing/AGENTS.md`, before editing any `metadata` export read `marketing/node_modules/next/dist/docs/` for the current Metadata API. The existing `export const metadata: Metadata = {...}` pattern in `app/*/page.tsx` is the source of truth — match it; do not invent new APIs.
- **All commands run from `marketing/`.** Prefix with `cd /Users/dixoncider/slabbist/marketing` (or run from that cwd).
- **Easter-egg secrecy is a hard constraint.** The words `psyduck`, `pokedex`, `pokédex`, and `cameo` must NEVER appear anywhere in `marketing/` — not in copy, alt text, aria-labels, comments, or filenames. The teaser describes "something hidden" only. Final grep gate enforces this.
- **Commit after every task** with the message shown in that task's final step.
- **Work on a feature branch.** Before Task 1: `git checkout -b marketing-ios-feature-parity` (current branch is `main`).

---

## Source of truth: real iOS feature set (for copy accuracy)

Confirmed shipping (from app inventory) — safe to market present-tense:
- Bulk scan + photo scan, cert OCR for PSA/BGS/CGC/SGC/TAG, PSA cert lookup/validation.
- Comps via Poketrace: headline price, low/high/avg, sale count (n), trend, confidence, per-grade ladder, 30-day sparkline, eBay sold listings (Scale-gated), TCGplayer affiliate links.
- **Margin ladder**: threshold→percentage tiers (e.g. $10+ → 70%, $25+ → 75%), highest cleared tier applies, snapshotted at offer time. (This is the REAL pricing rule — NOT "event mode," NOT per-grader/per-set modifiers.)
- Lots workflow (drafting→priced→presented→accepted/declined→paid/voided), offer review sheet (lot total, line items, payment method + reference, mark paid), Transactions ledger (immutable, void w/ reason), Vendors registry.
- **Pre-grade**: live camera grading → PSA-equivalent composite + sub-grades (centering/corners/edges/surface) + confidence; manual centering measurement tool with snap-to-edge; grading history (All/Starred).
- **Movers**: gainers/losers by set + price tier, EN/JP, 30-day sparklines, eBay links.
- **Grade Gains**: raw→PSA-10 arbitrage rows, live grading-fee stepper, price-tier filter, offline fallback.
- Offline-first outbox sync (sync pill, retry/discard failures sheet), 30-day comp cache.
- Hidden easter-egg surface (do NOT name).

NOT found in app (treat as overclaim → demote to "planned"/remove unless Task 1 grep proves otherwise):
- Role-based buy-price visibility (owner vs associate) "enforced in the database."
- Event-mode / per-grader / per-set margin modifiers; margin-rule audit log.
- Print/email offer sheets; on-device signature capture / signed PDF.
- Square / Shopify / QuickBooks integrations; CSV/PDF exports.
- Collector marketplace, escrow, inspection window, reputation import (already framed "planned" — keep as planned).

---

## File structure

**Create:**
- `marketing/components/marketing/intelligence-suite.tsx` — homepage section for the three new pillars (Pre-grade, Movers, Grade Gains) + their inline-SVG mocks.
- `marketing/components/marketing/easter-egg-teaser.tsx` — dedicated cryptic teaser block + abstract peeking silhouette.

**Modify:**
- `marketing/components/icon.tsx` — add `gauge`, `crosshair` icon strokes.
- `marketing/components/marketing/hero.tsx` — subhead + 3rd capability (drop role claim).
- `marketing/app/page.tsx` — wire in `IntelligenceSuite` + `EasterEggTeaser`.
- `marketing/components/marketing/feature-row.tsx` — replace 4th tab (role visibility) with real margin-ladder feature; rewrite `MarginRulesPanel` mock.
- `marketing/app/features/page.tsx` — add Pre-grade / Movers / Grade Gains / back-office sections; fix `COUNTER`, `BACK_OFFICE`, `IntegrationsSection`, metadata.
- `marketing/app/for-shops/page.tsx`, `for-vendors/page.tsx`, `for-collectors/page.tsx` — audience point rewrites + new features.
- `marketing/app/press/page.tsx` — boilerplate + stats.
- `marketing/app/changelog/page.tsx` — new entry; fix fabricated entries.
- `marketing/app/layout.tsx` — root meta description.

**Deliverable artifact:**
- `marketing/OVERCLAIM-CHANGES.md` — before/after list of every demoted claim (Task 12), for user review, deleted before final merge if the user prefers (keep by default).

---

## Phase A — Evidence + primitives

### Task 1: Confirm overclaims against the iOS source (evidence before demotion)

**Files:** none modified — produces notes used by later tasks.

- [ ] **Step 1: Grep the iOS app for each disputed capability**

Run each from repo root `/Users/dixoncider/slabbist`:

```bash
grep -rin --include=*.swift -E "associate|role.?based|owner.*visib|visib.*role" ios/slabbist/slabbist/ | head -40
grep -rin --include=*.swift -E "event ?mode|per.?grader|per.?set|rule.*audit|margin.*modifier" ios/slabbist/slabbist/ | head -40
grep -rin --include=*.swift -E "signature|signed ?pdf|print|email.*offer|export.*csv|export.*pdf" ios/slabbist/slabbist/ | head -40
grep -rin --include=*.swift -E "square|shopify|quickbooks" ios/slabbist/slabbist/ | head -40
```

Expected: little to nothing for role-based visibility, event mode, signature, POS integrations. Margin ladder lives in the ladder editor (threshold/percentage) only.

- [ ] **Step 2: Record findings**

For each capability, write one line: `<claim> — CONFIRMED <file:line> | NOT FOUND`. Keep this list; it drives Tasks 4, 6, 9, 10, and the artifact in Task 12. If anything is unexpectedly CONFIRMED, keep that claim present-tense in later tasks instead of demoting it.

- [ ] **Step 3: No commit** (investigation only).

---

### Task 2: Add `gauge` and `crosshair` icons

**Files:**
- Modify: `marketing/components/icon.tsx:3-6` (type union), `:74-77` (before `default`)

- [ ] **Step 1: Extend the `IconName` union**

Change the union (currently ending `... | 'card' | 'reload' | 'flag';`) to add the two names:

```ts
export type IconName =
  | 'scan' | 'bolt' | 'check' | 'check-c' | 'arrow' | 'chart' | 'shield' | 'users'
  | 'lock' | 'mail' | 'eye' | 'x' | 'menu' | 'github' | 'sparkle' | 'layers'
  | 'tag' | 'store' | 'zap' | 'receipt' | 'signature' | 'card' | 'reload' | 'flag'
  | 'gauge' | 'crosshair';
```

- [ ] **Step 2: Add the two `case` arms** immediately before `default:` (after the `flag` case at line 75):

```tsx
    case 'gauge':
      return <svg {...common}><path d="M5 17a9 9 0 1 1 14 0"/><path d="M12 15l4.5-4"/><circle cx="12" cy="15" r="1.1"/></svg>;
    case 'crosshair':
      return <svg {...common}><circle cx="12" cy="12" r="8"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/></svg>;
```

- [ ] **Step 3: Lint**

Run: `bun run lint`
Expected: PASS (no unused / type errors).

- [ ] **Step 4: Commit**

```bash
git add components/icon.tsx
git commit -m "feat(marketing): add gauge and crosshair icons"
```

---

### Task 3: Build the IntelligenceSuite section + its three mocks

**Files:**
- Create: `marketing/components/marketing/intelligence-suite.tsx`

- [ ] **Step 1: Create the file with the full section + mocks**

```tsx
'use client';

import { useEffect, useRef, useState } from 'react';
import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';

type Pillar = {
  icon: IconName;
  eyebrow: string;
  title: string;
  blurb: string;
  mock: 'pregrade' | 'movers' | 'gains';
};

const PILLARS: Pillar[] = [
  {
    icon: 'gauge',
    eyebrow: 'Pre-grade',
    title: 'Grade the card before you risk a dollar.',
    blurb:
      'Point the camera at a raw card and Slabbist estimates the PSA-equivalent grade — composite plus centering, corners, edges, and surface, with a confidence read. A measurement tool snaps to the card edges so you can settle a borderline centering call on the spot.',
    mock: 'pregrade',
  },
  {
    icon: 'chart',
    eyebrow: 'Movers',
    title: "See where the market's heading.",
    blurb:
      'Top gainers and losers for any set and price tier, English or Japanese, with a 30-day trend on every card. Know what is climbing before you make the offer — and what is bleeding out before you get stuck with it.',
    mock: 'movers',
  },
  {
    icon: 'zap',
    eyebrow: 'Grade gains',
    title: 'Find the raw cards worth sending in.',
    blurb:
      'Slabbist ranks raw cards by the upside of grading them to a PSA 10, net of the grading fee. Dial the fee to match your submission tier and the profit recalculates instantly, so the only cards you see are the ones worth the wait.',
    mock: 'gains',
  },
];

export function IntelligenceSuite() {
  const ref = useRef<HTMLElement | null>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (!ref.current) return;
    const obs = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting) setVisible(true);
      },
      { threshold: 0.12 },
    );
    obs.observe(ref.current);
    return () => obs.disconnect();
  }, []);

  return (
    <section
      ref={ref}
      style={{
        padding: 'clamp(84px, 11vw, 120px) 0',
        borderTop: '1px solid ' + SLAB.hair,
      }}
    >
      <div className="slab-container" style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
        <div style={{ marginBottom: 'clamp(48px, 6vw, 72px)', maxWidth: 640 }}>
          <div
            style={{
              fontSize: 12,
              letterSpacing: 1.6,
              textTransform: 'uppercase',
              color: SLAB.gold,
              marginBottom: 18,
              fontWeight: 500,
            }}
          >
            More than a scanner
          </div>
          <h2
            style={{
              fontFamily: SLAB.serif,
              fontSize: 'clamp(40px, 5vw, 64px)',
              fontWeight: 400,
              letterSpacing: -1.5,
              lineHeight: 1.05,
              margin: 0,
            }}
          >
            Scan it, <span style={{ fontStyle: 'italic', color: SLAB.gold }}>grade it</span>, know
            the market.
          </h2>
          <p style={{ fontSize: 16, color: SLAB.muted, lineHeight: 1.6, marginTop: 20 }}>
            Comps tell you what a slab is worth today. Slabbist also tells you what a raw card would
            grade, where the set is heading, and which cards are worth sending in.
          </p>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 1, background: SLAB.hair, border: '1px solid ' + SLAB.hair, borderRadius: 20, overflow: 'hidden' }}>
          {PILLARS.map((p, i) => (
            <div
              key={p.mock}
              className="slab-intel-row"
              style={{
                display: 'grid',
                gridTemplateColumns: '1fr 1fr',
                gap: 'clamp(28px, 4vw, 56px)',
                alignItems: 'center',
                padding: 'clamp(28px, 4vw, 48px)',
                background: SLAB.ink,
                direction: i % 2 === 1 ? 'rtl' : 'ltr',
                animation: visible ? `sbmRise 0.7s ${i * 0.1}s ease backwards` : 'none',
                opacity: visible ? 1 : 0,
              }}
            >
              <div style={{ direction: 'ltr' }}>
                <div
                  style={{
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: 10,
                    fontSize: 12,
                    letterSpacing: 1.6,
                    textTransform: 'uppercase',
                    color: SLAB.gold,
                    fontWeight: 500,
                    marginBottom: 16,
                  }}
                >
                  <Icon name={p.icon} size={16} sw={1.8} />
                  {p.eyebrow}
                </div>
                <h3
                  style={{
                    fontFamily: SLAB.serif,
                    fontSize: 'clamp(26px, 3.2vw, 36px)',
                    fontWeight: 400,
                    letterSpacing: -0.8,
                    lineHeight: 1.12,
                    margin: '0 0 16px',
                  }}
                >
                  {p.title}
                </h3>
                <p style={{ fontSize: 15, color: SLAB.muted, lineHeight: 1.6, margin: 0 }}>
                  {p.blurb}
                </p>
              </div>
              <div style={{ direction: 'ltr' }}>
                {p.mock === 'pregrade' && <PreGradeMock />}
                {p.mock === 'movers' && <MoversMock />}
                {p.mock === 'gains' && <GainsMock />}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function MockShell({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div
      style={{
        aspectRatio: '4/3',
        borderRadius: 20,
        background: `linear-gradient(145deg, ${SLAB.elev}, ${SLAB.surface})`,
        border: '1px solid ' + SLAB.hair,
        padding: 22,
        position: 'relative',
        overflow: 'hidden',
        boxShadow: '0 30px 70px oklch(0 0 0 / 0.35)',
      }}
    >
      <div
        style={{
          fontSize: 11,
          letterSpacing: 2,
          textTransform: 'uppercase',
          color: SLAB.dim,
          marginBottom: 16,
          fontWeight: 500,
        }}
      >
        {label}
      </div>
      {children}
    </div>
  );
}

function PreGradeMock() {
  const subs: [string, string, number][] = [
    ['Centering', '9.5', 0.95],
    ['Corners', '9.0', 0.9],
    ['Edges', '9.5', 0.95],
    ['Surface', '10', 1.0],
  ];
  return (
    <MockShell label="Pre-grade · estimate">
      <div style={{ display: 'grid', gridTemplateColumns: '96px 1fr', gap: 18, alignItems: 'center' }}>
        <div
          style={{
            position: 'relative',
            aspectRatio: '5/7',
            borderRadius: 8,
            background: 'linear-gradient(150deg, oklch(0.34 0.1 250), oklch(0.13 0.04 250))',
            border: '1px solid ' + SLAB.hairStrong,
          }}
          aria-hidden
        >
          <div style={{ position: 'absolute', top: 0, bottom: 0, left: '50%', width: 1, background: SLAB.gold, opacity: 0.7 }} />
          <div style={{ position: 'absolute', left: 0, right: 0, top: '50%', height: 1, background: SLAB.gold, opacity: 0.7 }} />
          <div
            style={{
              position: 'absolute',
              top: 6,
              right: 6,
              fontFamily: SLAB.mono,
              fontSize: 11,
              fontWeight: 700,
              color: SLAB.ink,
              background: SLAB.gold,
              borderRadius: 6,
              padding: '3px 6px',
            }}
          >
            9.5
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {subs.map(([name, val, frac]) => (
            <div key={name}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: SLAB.muted, marginBottom: 4 }}>
                <span>{name}</span>
                <span style={{ fontFamily: SLAB.mono, color: SLAB.text }}>{val}</span>
              </div>
              <div style={{ height: 5, borderRadius: 3, background: SLAB.elev2, overflow: 'hidden' }}>
                <div style={{ height: '100%', width: `${frac * 100}%`, background: `linear-gradient(90deg, ${SLAB.goldDim}, ${SLAB.gold})` }} />
              </div>
            </div>
          ))}
          <div style={{ fontSize: 11, color: SLAB.dim, marginTop: 2 }}>Confidence · High</div>
        </div>
      </div>
    </MockShell>
  );
}

function MoversMock() {
  const rows: [string, string, boolean][] = [
    ['Umbreon ex · 161', '+18.4%', true],
    ['Pikachu ex · 238', '+11.2%', true],
    ['Sylveon ex · 156', '-6.1%', false],
    ['Eevee · 167', '-9.7%', false],
  ];
  return (
    <MockShell label="Movers · Surging Sparks · $50+">
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {rows.map(([name, delta, up], i) => (
          <div
            key={name}
            style={{
              display: 'grid',
              gridTemplateColumns: '28px 1fr auto 56px',
              gap: 12,
              alignItems: 'center',
              padding: '8px 10px',
              borderRadius: 10,
              background: i === 0 ? SLAB.elev2 : 'transparent',
              border: '1px solid ' + (i === 0 ? SLAB.hairStrong : SLAB.hair),
            }}
          >
            <div style={{ aspectRatio: '5/7', borderRadius: 4, background: `linear-gradient(145deg, oklch(0.34 0.1 ${i * 60}), oklch(0.14 0.04 ${i * 60}))` }} aria-hidden />
            <span style={{ fontSize: 12, color: SLAB.text, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name}</span>
            <span style={{ fontFamily: SLAB.mono, fontSize: 12, color: up ? SLAB.pos : SLAB.neg }}>{delta}</span>
            <svg viewBox="0 0 56 20" width="56" height="20" aria-hidden>
              <path
                d={up ? 'M0,16 L14,14 L28,10 L42,7 L56,3' : 'M0,5 L14,8 L28,9 L42,13 L56,17'}
                fill="none"
                stroke={up ? SLAB.pos : SLAB.neg}
                strokeWidth="1.6"
                strokeLinecap="round"
              />
            </svg>
          </div>
        ))}
      </div>
    </MockShell>
  );
}

function GainsMock() {
  return (
    <MockShell label="Grade gains · raw → PSA 10">
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ fontFamily: SLAB.mono, fontSize: 13, color: SLAB.muted }}>raw $42</div>
            <Icon name="arrow" size={14} color={SLAB.gold} sw={2} />
            <div style={{ fontFamily: SLAB.mono, fontSize: 13, color: SLAB.text }}>PSA 10 $410</div>
          </div>
          <span
            style={{
              fontSize: 11,
              fontFamily: SLAB.mono,
              padding: '4px 8px',
              borderRadius: 999,
              border: '1px solid ' + SLAB.hair,
              color: SLAB.muted,
            }}
          >
            fee $19 −/＋
          </span>
        </div>
        <div
          style={{
            padding: 16,
            borderRadius: 14,
            background: 'linear-gradient(145deg, oklch(0.22 0.06 78), oklch(0.14 0.03 78))',
            border: '1px solid oklch(0.82 0.13 78 / 0.27)',
          }}
        >
          <div style={{ fontSize: 10, letterSpacing: 1.5, textTransform: 'uppercase', color: SLAB.gold, fontWeight: 600, marginBottom: 4 }}>
            Profit to PSA 10
          </div>
          <div style={{ fontFamily: SLAB.serif, fontSize: 40, letterSpacing: -1, lineHeight: 1, color: SLAB.gold }}>
            +$349
          </div>
        </div>
        {([['Charizard · 199', '+$212'], ['Mew · 232', '+$94']] as const).map(([n, p]) => (
          <div key={n} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: SLAB.muted, paddingTop: 2 }}>
            <span>{n}</span>
            <span style={{ fontFamily: SLAB.mono, color: SLAB.pos }}>{p}</span>
          </div>
        ))}
      </div>
    </MockShell>
  );
}
```

- [ ] **Step 2: Add the mobile stacking rule** for `.slab-intel-row` so the two-column grid collapses on phones.

In `marketing/app/globals.css`, inside the existing `@media (max-width: 720px) { ... }` block (ends at line 144, before the closing brace), add:

```css
  .slab-intel-row { grid-template-columns: 1fr !important; direction: ltr !important; }
```

- [ ] **Step 3: Lint**

Run: `bun run lint`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add components/marketing/intelligence-suite.tsx app/globals.css
git commit -m "feat(marketing): add IntelligenceSuite section (pre-grade, movers, grade gains)"
```

---

### Task 4: Build the easter-egg teaser block

**Files:**
- Create: `marketing/components/marketing/easter-egg-teaser.tsx`

- [ ] **Step 1: Create the file**

The silhouette is an abstract, featureless rounded shape peeking from the right edge — deliberately NOT identifiable. No `psyduck`/`cameo`/`pokedex` anywhere.

```tsx
import { SLAB } from '@/lib/tokens';

export function EasterEggTeaser() {
  return (
    <section
      style={{
        padding: 'clamp(72px, 9vw, 104px) 0',
        borderTop: '1px solid ' + SLAB.hair,
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      {/* Abstract silhouette peeking in from the edge — intentionally unrecognizable. */}
      <div
        aria-hidden
        style={{
          position: 'absolute',
          right: -36,
          top: '50%',
          transform: 'translateY(-50%)',
          width: 150,
          height: 150,
          borderRadius: '50% 50% 46% 54% / 58% 58% 42% 42%',
          background: `radial-gradient(circle at 38% 34%, oklch(0.82 0.13 78 / 0.22), oklch(0.82 0.13 78 / 0.04))`,
          border: '1px solid oklch(0.82 0.13 78 / 0.18)',
          filter: 'blur(0.4px)',
          pointerEvents: 'none',
        }}
      />
      <div className="slab-container" style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px', position: 'relative' }}>
        <div style={{ maxWidth: 620 }}>
          <div
            style={{
              fontSize: 12,
              letterSpacing: 1.6,
              textTransform: 'uppercase',
              color: SLAB.gold,
              marginBottom: 18,
              fontWeight: 500,
            }}
          >
            One more thing
          </div>
          <h2
            style={{
              fontFamily: SLAB.serif,
              fontSize: 'clamp(32px, 4.5vw, 56px)',
              fontWeight: 400,
              letterSpacing: -1.4,
              lineHeight: 1.06,
              margin: 0,
            }}
          >
            There's something in here we{' '}
            <span style={{ fontStyle: 'italic', color: SLAB.gold }}>didn't</span> tell you about.
          </h2>
          <p style={{ fontSize: 17, color: SLAB.muted, lineHeight: 1.6, marginTop: 22 }}>
            Keep the app open and stay sharp. Every so often, something pokes its head in — blink and
            it's gone. Catch it, and a door opens. We won't say what's behind it.
          </p>
          <p style={{ fontSize: 17, color: SLAB.text, lineHeight: 1.6, marginTop: 14, fontStyle: 'italic' }}>
            Half the fun is finding out.
          </p>
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Lint**

Run: `bun run lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add components/marketing/easter-egg-teaser.tsx
git commit -m "feat(marketing): add easter-egg teaser block"
```

---

## Phase B — Homepage

### Task 5: Update the hero subhead + 3rd capability

**Files:**
- Modify: `marketing/components/marketing/hero.tsx:20-24` (3rd capability), `:152` (subhead)

- [ ] **Step 1: Rewrite the 3rd capability** (currently the `shield`/"Runs anywhere you buy" item whose body ends "Buy prices stay locked to owners and hidden from associates."). Replace that object (lines 20-25) with:

```tsx
  {
    icon: 'gauge',
    title: 'Grade, comp, and know the market',
    body: 'Estimate a raw card’s grade before you buy, comp graded slabs against real sales, and watch which cards are climbing. The buy desk and the market intel live in one app.',
  },
```

- [ ] **Step 2: Rewrite the hero subhead** (line 152). Replace the paragraph text with:

```tsx
          Slabbist turns your iPhone into a bulk scanner for graded Pokémon — real comps from recent sales, a grade estimate on any raw card, and market movers at a glance. Offer sheets in a tap, on your counter or the show floor.
```

- [ ] **Step 3: Lint**

Run: `bun run lint`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add components/marketing/hero.tsx
git commit -m "feat(marketing): broaden hero subhead and capability to grading + market intel"
```

---

### Task 6: Replace the FeatureRow role-visibility tab with the real margin ladder

**Files:**
- Modify: `marketing/components/marketing/feature-row.tsx:28-34` (4th `FEATS` entry), `:743-931` (`MarginRulesPanel`)

> Only do the demotion if Task 1 confirmed role-based visibility is NOT in the app. If it IS confirmed in code, skip this task and keep the existing tab.

- [ ] **Step 1: Replace the 4th `FEATS` entry** (the `shield` / "Buy price only for staff" object, lines 28-34) with:

```tsx
  {
    icon: 'tag',
    title: 'Your margin ladder does the math',
    blurb:
      'Set buy percentages by price tier once — pay 70% under $25, 75% over it, whatever your shop runs. Every slab gets priced against its comp automatically, and the ladder is locked into the offer the moment you present it.',
  },
```

- [ ] **Step 2: Rewrite `MarginRulesPanel`** (lines 743-931) to show the real ladder (tiers + a worked example), not Owner/Associate visibility. Replace the entire function with:

```tsx
function MarginRulesPanel() {
  const tiers: [string, string][] = [
    ['$0 – $25', '70%'],
    ['$25 – $50', '75%'],
    ['$50 – $200', '80%'],
    ['$200+', '85%'],
  ];
  return (
    <div
      style={{
        animation: 'sbmFade 0.5s',
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      <div
        style={{
          fontSize: 11,
          letterSpacing: 2,
          textTransform: 'uppercase',
          color: SLAB.dim,
          marginBottom: 14,
          fontWeight: 500,
        }}
      >
        Margin ladder · active
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginBottom: 18 }}>
        {tiers.map(([range, pct], i) => (
          <div
            key={range}
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              padding: '12px 14px',
              borderRadius: 10,
              background: i === 1 ? SLAB.elev2 : 'transparent',
              border: '1px solid ' + (i === 1 ? SLAB.hairStrong : SLAB.hair),
            }}
          >
            <span style={{ fontFamily: SLAB.mono, fontSize: 13, color: SLAB.text }}>{range}</span>
            <span style={{ fontFamily: SLAB.mono, fontSize: 13, color: SLAB.gold, fontWeight: 600 }}>
              pay {pct}
            </span>
          </div>
        ))}
      </div>

      <div
        style={{
          marginTop: 'auto',
          padding: 16,
          borderRadius: 14,
          background: 'linear-gradient(145deg, oklch(0.22 0.06 78), oklch(0.14 0.03 78))',
          border: '1px solid oklch(0.82 0.13 78 / 0.27)',
        }}
      >
        <div style={{ fontSize: 11, letterSpacing: 1.5, textTransform: 'uppercase', color: SLAB.gold, fontWeight: 600, marginBottom: 8 }}>
          This slab
        </div>
        <div style={{ fontFamily: SLAB.mono, fontSize: 13, color: SLAB.muted, lineHeight: 1.7 }}>
          <div>comp: <span style={{ color: SLAB.text }}>$42</span></div>
          <div>tier: <span style={{ color: SLAB.text }}>$25 – $50 · 75%</span></div>
          <div>buy: <span style={{ color: SLAB.text }}>$31</span></div>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Update the section heading** if it implies four "fast" things still hold — line 104 reads "Four things that actually make it fast." That remains accurate (still 4 tabs). No change needed.

- [ ] **Step 4: Lint**

Run: `bun run lint`
Expected: PASS (note: `Icon` `lock` import usage drops from this panel — confirm `Icon` is still used elsewhere in the file, which it is, in `CertOcrPanel`/`CompPanel`, so the import stays valid).

- [ ] **Step 5: Commit**

```bash
git add components/marketing/feature-row.tsx
git commit -m "fix(marketing): replace role-visibility tab with real margin ladder"
```

---

### Task 7: Wire IntelligenceSuite + EasterEggTeaser into the homepage

**Files:**
- Modify: `marketing/app/page.tsx`

- [ ] **Step 1: Replace the file** with the new composition (adds two imports + two elements):

```tsx
import { Nav } from '@/components/marketing/nav';
import { Hero } from '@/components/marketing/hero';
import { FeatureRow } from '@/components/marketing/feature-row';
import { IntelligenceSuite } from '@/components/marketing/intelligence-suite';
import { Workflow } from '@/components/marketing/workflow';
import { EasterEggTeaser } from '@/components/marketing/easter-egg-teaser';
import { Pricing } from '@/components/marketing/pricing';
import { FinalCta } from '@/components/marketing/final-cta';
import { Footer } from '@/components/marketing/footer';

export default function Home() {
  return (
    <>
      <Nav />
      <Hero />
      <FeatureRow />
      <IntelligenceSuite />
      <Workflow />
      <EasterEggTeaser />
      <Pricing />
      <FinalCta />
      <Footer />
    </>
  );
}
```

- [ ] **Step 2: Build** (first full build — catches any wiring/type issues across new components)

Run: `bun run build`
Expected: build succeeds, no type errors.

- [ ] **Step 3: Commit**

```bash
git add app/page.tsx
git commit -m "feat(marketing): wire intelligence suite + easter-egg teaser into homepage"
```

---

## Phase C — Features page

### Task 8: Add real feature sections + fix overclaims on `/features`

**Files:**
- Modify: `marketing/app/features/page.tsx`

- [ ] **Step 1: Update page metadata** (lines 8-12) to reflect the broader scope:

```tsx
export const metadata: Metadata = {
  title: 'Features · Slabbist',
  description:
    'Everything Slabbist does for card shops and show vendors. Bulk cert scanning, comps from real sales, on-device grade estimates, market movers, grade-gain arbitrage, and a margin ladder that prices every slab.',
};
```

- [ ] **Step 2: Rewrite the `COUNTER` array** (lines 74-99) — remove role-visibility, signature, and print/email; keep margin + the real offer sheet:

```tsx
const COUNTER: FeatureCard[] = [
  {
    icon: 'tag',
    title: 'A margin ladder you actually understand',
    blurb:
      'Set buy percentages by price tier once. Every slab is priced against its comp automatically, and you can override any single buy price by hand. The ladder is snapshotted onto the offer the moment you present it.',
  },
  {
    icon: 'receipt',
    title: 'Offer sheet, ready to present',
    blurb:
      'Roll a lot into one offer: total, per-slab line items, and the payment method and reference. Mark it paid and it drops into your transaction ledger, frozen and audit-safe.',
  },
  {
    icon: 'users',
    title: 'Vendors on file',
    blurb:
      'Keep a registry of who you buy from — phone, email, Instagram, notes. Attach a vendor to a lot in two taps; archived vendors stay readable in history.',
  },
  {
    icon: 'reload',
    title: 'Lot workflow that tracks itself',
    blurb:
      'Drafting, priced, presented, accepted, paid, or voided — every lot carries its state, and paid lots lock so a closed buy cannot be edited out from under you.',
  },
];
```

- [ ] **Step 3: Rewrite the `BACK_OFFICE` array** (lines 101-126) — remove "role" claims and QuickBooks/Square exports; market the real ledger + offline + Pre-grade history:

```tsx
const BACK_OFFICE: FeatureCard[] = [
  {
    icon: 'receipt',
    title: 'Transaction ledger',
    blurb:
      'Every paid lot becomes an immutable record — vendor, total, payment method, timestamp. Void with a reason if you have to; the audit trail stays intact.',
  },
  {
    icon: 'reload',
    title: 'Offline-first by design',
    blurb:
      'Scans, edits, prices, and offers are written locally first and synced in the background through an outbox. A failed write surfaces in a sheet you can retry — nothing is lost when the venue Wi-Fi quits.',
  },
  {
    icon: 'gauge',
    title: 'Grading history',
    blurb:
      'Every pre-grade estimate is saved with its photos, sub-grades, and reasoning. Star the keepers and filter your collection down to them.',
  },
  {
    icon: 'store',
    title: 'Built multi-tenant',
    blurb:
      'Your store’s data is scoped to your store and nobody else’s, enforced server-side. Run the buy desk knowing your numbers stay yours.',
  },
];
```

- [ ] **Step 4: Add three new `FeatureCard` arrays** for the intelligence surfaces. Insert after the `BACK_OFFICE` array (after line 126):

```tsx
const PREGRADE: FeatureCard[] = [
  {
    icon: 'gauge',
    title: 'PSA-equivalent grade estimate',
    blurb:
      'Frame a raw card and Slabbist returns a composite grade with centering, corners, edges, and surface sub-grades — plus a confidence read so you know how far to trust it.',
  },
  {
    icon: 'crosshair',
    title: 'Centering tool that snaps to the edges',
    blurb:
      'Drag the guides or tap an inner edge to snap them, and read the exact L/R and T/B ratios. Settle a borderline centering call before you commit a dollar.',
  },
  {
    icon: 'card',
    title: 'Front and back, kept on file',
    blurb:
      'Each estimate stores both photos and the reasoning behind the grade, so you can revisit why a card scored the way it did.',
  },
];

const MARKET: FeatureCard[] = [
  {
    icon: 'chart',
    title: 'Movers by set and tier',
    blurb:
      'Top gainers and losers for any set and price band, English or Japanese, each with a 30-day trend. See what is heating up before you make the offer.',
  },
  {
    icon: 'zap',
    title: 'Grade gains arbitrage',
    blurb:
      'Raw cards ranked by their upside to a PSA 10, net of the grading fee. Dial the fee to your submission tier and the profit recalculates on the spot.',
  },
  {
    icon: 'sparkle',
    title: 'Comps with the receipts',
    blurb:
      'Headline price, range, sale count, trend, and a per-grade ladder — with the recent eBay solds behind every number and a TCGplayer link when there is one.',
  },
];
```

- [ ] **Step 5: Render the new sections + keep the page flowing.** In the JSX (the `FeaturesPage` return, lines 128-172), insert two new `<Section>` blocks: a Pre-grade section after the `comps` section, and a Market section. Replace the body of `FeaturesPage` return with:

```tsx
    <PageShell>
      <PageHero
        eyebrow="Features"
        title="Everything the counter needs. Nothing it doesn't."
        italicize="counter"
        subtitle="Slabbist is purpose-built for the moment a stack of slabs hits your counter. Here is every piece that gets it scanned, graded, priced, offered, and closed."
      />

      <Section
        id="capture"
        eyebrow="Capture"
        title="Get the slab into the app in one second."
        cards={CAPTURE}
      />

      <FeatureRow />

      <Section
        id="comps"
        eyebrow="Comp engine"
        title="Real prices from real sales."
        cards={COMP_ENGINE}
      />

      <Section
        id="pre-grade"
        eyebrow="Pre-grade"
        title="Grade the card before you buy it."
        cards={PREGRADE}
      />

      <Section
        id="market"
        eyebrow="Market intel"
        title="Know where the market is going."
        cards={MARKET}
      />

      <Section
        id="counter"
        eyebrow="At the counter"
        title="From stack to signed-off offer."
        cards={COUNTER}
      />

      <Section
        id="back-office"
        eyebrow="Back office"
        title="Everything you need after the buy closes."
        cards={BACK_OFFICE}
      />

      <IntegrationsSection />

      <FinalCta />
    </PageShell>
```

- [ ] **Step 6: Fix `IntegrationsSection`** (lines 293-300 `rows`) — keep real integrations present-tense, move POS/accounting to a clearly-labeled planned row:

```tsx
  const rows: { name: string; what: string }[] = [
    { name: 'eBay', what: 'Recent sold listings feed the comp engine, with affiliate links on every comp tap.' },
    { name: 'TCGplayer', what: 'Raw card pricing and product links for non-graded comps.' },
    { name: 'PSA', what: 'Cert lookups and card identity resolution for graded slabs.' },
    { name: 'PSA / BGS / CGC / SGC / TAG', what: 'Cert OCR reads the label and grade off every major grader.' },
    { name: 'POS & accounting (planned)', what: 'Square, Shopify, and QuickBooks exports are on the roadmap, not shipping yet.' },
  ];
```

Also soften the section subhead (line 334) from "already wired up" to: `The tools you already use — with more on the way.`

- [ ] **Step 7: Build**

Run: `bun run build`
Expected: succeeds. (Confirms the `gauge`/`crosshair`/`card`/`zap`/`sparkle` icon names all resolve.)

- [ ] **Step 8: Commit**

```bash
git add app/features/page.tsx
git commit -m "feat(marketing): add pre-grade + market sections to /features, fix overclaims"
```

---

## Phase D — Audience pages

### Task 9: Rewrite `/for-shops` points

**Files:**
- Modify: `marketing/app/for-shops/page.tsx:12-49` (`POINTS`), `:60-62` (pain/shift if needed)

- [ ] **Step 1: Replace the `POINTS` array** — drop role-visibility / signature / event-mode; add Pre-grade + real margin/offer:

```tsx
const POINTS: AudiencePoint[] = [
  {
    icon: 'scan',
    title: 'Counter-grade capture',
    blurb:
      'Set the phone on a stand or hold it. Either way, sweep a stack of slabs in one pass without chasing focus between scans.',
  },
  {
    icon: 'gauge',
    title: 'Grade the walk-in before you offer',
    blurb:
      'A seller drops a raw card on the counter? Pre-grade gives you a PSA-equivalent estimate and centering read before you put a number on it.',
  },
  {
    icon: 'chart',
    title: 'Comps you can show the seller',
    blurb:
      'Every price is built from recent sales, with range, trend, and the actual solds behind it. Buy with confidence on the climbers, skip the ones bleeding out.',
  },
  {
    icon: 'tag',
    title: 'Your margin ladder, applied automatically',
    blurb:
      'Set buy percentages by price tier once and every slab gets priced against its comp. Override any single buy by hand when you need to.',
  },
  {
    icon: 'receipt',
    title: 'Offer sheet to paid, in one flow',
    blurb:
      'Roll the lot into an offer, attach the vendor, mark it paid. It drops into your transaction ledger, frozen and audit-safe.',
  },
  {
    icon: 'users',
    title: 'Vendor history at a glance',
    blurb:
      'Who sold you what, in which grade mix. Keep a registry with notes and pull a vendor onto a lot in two taps.',
  },
];
```

- [ ] **Step 2: Update the `shift` prop** (line 62) to drop the "prints" claim:

```tsx
        shift="Slabs scan, comps resolve, your margin applies, and the offer is ready to present before the seller finishes their coffee."
```

- [ ] **Step 3: Lint**

Run: `bun run lint`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/for-shops/page.tsx
git commit -m "feat(marketing): refresh /for-shops with pre-grade + real margin/offer flow"
```

---

### Task 10: Rewrite `/for-vendors` points

**Files:**
- Modify: `marketing/app/for-vendors/page.tsx:12-49` (`POINTS`), `:62-63` (pain/shift)

- [ ] **Step 1: Replace the `POINTS` array** — drop event-mode / signature / CSV-export; add Movers + Grade Gains + real offline:

```tsx
const POINTS: AudiencePoint[] = [
  {
    icon: 'reload',
    title: 'Offline queue',
    blurb:
      'Conference-center Wi-Fi drops at 11am. Scans keep stacking locally and comps fill in the moment signal returns — through an outbox that retries on its own.',
  },
  {
    icon: 'layers',
    title: 'Showcase in one pass',
    blurb:
      'Scan every slab in the case in minutes. Re-price the showcase on Sunday morning without redoing the work.',
  },
  {
    icon: 'chart',
    title: 'Movers before you buy',
    blurb:
      'See the top gainers and losers for the set in front of you, by price tier, English or Japanese. Know what is climbing before you make the offer.',
  },
  {
    icon: 'zap',
    title: 'Grade gains on the floor',
    blurb:
      'Spot the raw cards worth sending to PSA — ranked by upside to a 10, net of the grading fee you actually pay.',
  },
  {
    icon: 'receipt',
    title: 'Buylist from your phone',
    blurb:
      'A vendor wants to sell you a PSA 10. Scan, apply the lot rule, present the offer. No laptop, no spreadsheet.',
  },
  {
    icon: 'gauge',
    title: 'Pre-grade a raw on the spot',
    blurb:
      'Estimate a raw card’s grade and centering at the table, so a borderline buy is a decision, not a gamble.',
  },
];
```

- [ ] **Step 2: Update the `shift` prop** (line 63) to drop the export claim:

```tsx
        shift="One app runs the booth: pre-grading raws, pricing the case, reading the movers, and closing buylist offers — online or off."
```

- [ ] **Step 3: Lint**

Run: `bun run lint`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/for-vendors/page.tsx
git commit -m "feat(marketing): refresh /for-vendors with movers, grade gains, real offline"
```

---

### Task 11: Refresh `/for-collectors` (keep marketplace as planned, add real today-features)

**Files:**
- Modify: `marketing/app/for-collectors/page.tsx`

> The marketplace, escrow, inspection, and reputation import are not in the shipped app. Keep them but frame the marketplace explicitly as planned, and add the real things a collector can use today (Pre-grade, Movers, comps). Add the easter-egg nod.

- [ ] **Step 1: Update metadata** (lines 6-10):

```tsx
export const metadata: Metadata = {
  title: 'Slabbist for collectors',
  description:
    'Pre-grade your own cards, watch market movers, and comp any slab against real sales today. A fair marketplace with a 1% buyer fee is on the way.',
};
```

- [ ] **Step 2: Replace the `POINTS` array** (lines 12-49) — split into real-today + planned-marketplace, each labeled in the blurb:

```tsx
const POINTS: AudiencePoint[] = [
  {
    icon: 'gauge',
    title: 'Pre-grade your own cards',
    blurb:
      'Estimate a card’s PSA-equivalent grade and centering before you spend on a submission. Available today.',
  },
  {
    icon: 'chart',
    title: 'Market movers and real comps',
    blurb:
      'The same comp engine and gainers/losers stores use. See the last 30 days on the exact card you are eyeing. Available today.',
  },
  {
    icon: 'zap',
    title: 'Spot the grade-gain plays',
    blurb:
      'Find the raw cards worth grading, ranked by upside to a PSA 10 net of the fee. Available today.',
  },
  {
    icon: 'lock',
    title: 'Escrow + inspection window (planned)',
    blurb:
      'The coming marketplace will hold your money until the card arrives and you have had time to inspect it.',
  },
  {
    icon: 'tag',
    title: 'Zero seller fees (planned)',
    blurb:
      'No listing or commission fees. A 1% buyer fee will apply only at checkout; sellers net the sale price after payment processing.',
  },
  {
    icon: 'shield',
    title: 'Cert-verified listings (planned)',
    blurb:
      'Every slab will be cross-checked with the grader database before it goes live — no mismatched certs, no swapped slabs.',
  },
];
```

- [ ] **Step 3: Update the hero + pain/shift** (lines 56-63) so the marketplace reads as future and today-value leads:

```tsx
      <PageHero
        eyebrow="For collectors"
        title="Grade smarter today. Sell fairer tomorrow."
        italicize="fairer"
        subtitle="Pre-grade your own cards, watch the movers, and comp any slab against real sales right now. A marketplace that doesn't punish selling — 1% buyer fee, zero seller fees — is on the way."
      />
      <AudienceBody
        pain="You love the hobby but hate the tax. A 13% final-value fee, 3% payment processing, and a promoted-listing fee on top means a $500 slab nets you $420 if you are lucky."
        shift="Use Slabbist today to grade, comp, and track the market. When the marketplace opens, list for free and keep what selling elsewhere takes from you."
        points={POINTS}
        ctaLabel="Join the collector waitlist"
        waitlistAudience="collector"
      />
```

- [ ] **Step 4: Lint**

Run: `bun run lint`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/for-collectors/page.tsx
git commit -m "feat(marketing): lead /for-collectors with real today-features, mark marketplace planned"
```

---

## Phase E — Press, changelog, metadata, artifact

### Task 12: Fix the changelog (remove fabricated entries, add the real release)

**Files:**
- Modify: `marketing/app/changelog/page.tsx:24-90` (`ENTRIES`)

> The dates here are illustrative beta history (the project has no real public release log). Today is 2026-06-07. Replace the fabricated capability entries (role-based visibility, event-aware margin rules, signature-on-glass, print/email) with the real shipped features, and add a top entry covering the new surfaces + the hidden surprise.

- [ ] **Step 1: Replace the `ENTRIES` array** with:

```tsx
const ENTRIES: Entry[] = [
  {
    date: '2026-06-07',
    version: '0.10.0',
    title: 'Pre-grade, movers, and grade gains',
    tag: 'beta',
    bullets: [
      'Pre-grade: on-device PSA-equivalent grade estimates with centering, corners, edges, and surface sub-grades.',
      'Centering tool with snap-to-edge guides and live L/R, T/B ratios.',
      'Movers: top gainers and losers by set and price tier, English or Japanese.',
      'Grade gains: raw-to-PSA-10 arbitrage with a live grading-fee stepper.',
      'And a little something hidden. We are not going to tell you where.',
    ],
  },
  {
    date: '2026-04-18',
    version: '0.9.0',
    title: 'Lots, offers, and the transaction ledger',
    tag: 'beta',
    bullets: [
      'Roll scans into a lot, present an offer, and mark it paid with a payment method and reference.',
      'Paid lots freeze and drop into an immutable transaction ledger; void with a reason if you must.',
      'Vendor registry with contact details and notes, attachable to any lot.',
    ],
  },
  {
    date: '2026-03-28',
    version: '0.8.2',
    title: 'TAG grading support',
    tag: 'beta',
    bullets: [
      'Added cert OCR for TAG-graded slabs alongside PSA, BGS, CGC, and SGC.',
      'Confidence scoring now weighs comp volume and spread per grade.',
      'Fixed a sync stall when a queued scan lacked a cert number.',
    ],
  },
  {
    date: '2026-03-10',
    version: '0.8.0',
    title: 'Margin ladder',
    tag: 'beta',
    bullets: [
      'Set buy percentages by price tier; the highest cleared tier prices each slab against its comp.',
      'Override any single buy price by hand.',
      'The ladder is snapshotted onto an offer the moment you present it.',
    ],
  },
  {
    date: '2026-01-22',
    version: '0.6.0',
    title: 'Offline-first queue',
    tag: 'preview',
    bullets: [
      'Scans, edits, and offers persist locally and sync on reconnect through an outbox.',
      'Failed writes surface in a sheet you can retry or discard.',
    ],
  },
  {
    date: '2025-12-08',
    version: '0.5.0',
    title: 'Comp engine v1',
    tag: 'internal',
    bullets: [
      'Recent-sales pricing with range, sale count, trend, and a per-grade ladder.',
      '30-day price history on every card.',
      'Tap any price to see the sales behind it.',
    ],
  },
];
```

- [ ] **Step 2: Lint**

Run: `bun run lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add app/changelog/page.tsx
git commit -m "fix(marketing): changelog reflects real shipped features, tease hidden surprise"
```

---

### Task 13: Update press stats + boilerplate, and the root meta description

**Files:**
- Modify: `marketing/app/press/page.tsx:40-53`, `marketing/app/layout.tsx:25-29`

- [ ] **Step 1: Update the press boilerplate + stats** (lines 39-53). Replace both `Card` blocks with:

```tsx
          <Card
            label="Boilerplate"
            lines={[
              'Slabbist is an iOS app for Pokémon hobby stores and show vendors. It bulk-scans graded slabs and returns real comps from recent sales, estimates the grade of raw cards on-device, surfaces market movers and raw-to-graded arbitrage, and turns a stack into a priced offer. Founded in 2025 and based in the Pacific Northwest.',
            ]}
          />
          <Card
            label="Stats"
            lines={[
              'Bulk cert scanning for PSA, BGS, CGC, SGC, and TAG',
              'On-device grade estimates with centering, corners, edges, surface',
              'Movers and grade-gain arbitrage by set and price tier',
              'Offline-first — works when the venue Wi-Fi quits',
              'Free on iOS',
            ]}
          />
```

- [ ] **Step 2: Update the root meta description** in `app/layout.tsx` (lines 26-28):

```tsx
  title: "Slabbist · Price a stack of slabs faster than you can count them",
  description:
    "Slabbist turns your iPhone into a bulk scanner for graded Pokémon — real comps from recent sales, on-device grade estimates, market movers, and grade-gain arbitrage. Offer sheets in a tap, free on iOS.",
```

- [ ] **Step 3: Lint**

Run: `bun run lint`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/press/page.tsx app/layout.tsx
git commit -m "feat(marketing): update press kit + root metadata for full feature set"
```

---

### Task 14: Write the overclaim before/after artifact

**Files:**
- Create: `marketing/OVERCLAIM-CHANGES.md`

- [ ] **Step 1: Write the artifact** documenting every demoted claim, using the Task 1 evidence. Format:

```markdown
# Marketing overclaim reconciliation — 2026-06-07

Claims rewritten because the shipped iOS app does not back them (verified via grep in Task 1).

| Claim (before) | Where it lived | Status | After |
|---|---|---|---|
| Role-based buy-price visibility "enforced in the database" (owner sees comp/cost/margin, associate sees buy only) | hero capability; feature-row 4th tab + MarginRulesPanel; features COUNTER + BACK_OFFICE; for-shops point; changelog v0.8.0 | NOT FOUND in app | Replaced with the real margin ladder; multi-tenant store scoping kept (that IS real via RLS) |
| Event-mode / per-grader / per-set margin modifiers; rule audit log | feature-row MarginRulesPanel; features; for-shops/for-vendors points; changelog v0.7.0 | NOT FOUND | Replaced with real tier-based margin ladder |
| Print/email offer sheets | features COUNTER; for-shops; changelog v0.9.0 | NOT FOUND | "Offer sheet, ready to present" (on-screen lot total + line items + payment method/ref + mark paid) |
| On-device signature capture / signed PDF | features COUNTER; for-shops; for-vendors; changelog v0.9.0 | NOT FOUND | Removed |
| Square / Shopify / QuickBooks integrations + CSV/PDF exports | features IntegrationsSection + BACK_OFFICE; for-vendors | NOT FOUND | Labeled "POS & accounting (planned)" |
| Collector marketplace, escrow, inspection, reputation import | for-collectors | NOT FOUND (always roadmap) | Kept but explicitly marked "(planned)"; real today-features lead |

If Task 1 found any of these CONFIRMED in code, that row is omitted and the claim was kept present-tense.
```

Fill the table from the actual Task 1 findings (adjust any row that grep flipped).

- [ ] **Step 2: Commit**

```bash
git add OVERCLAIM-CHANGES.md
git commit -m "docs(marketing): record overclaim before/after reconciliation"
```

---

## Phase F — Final verification

### Task 15: Full build, lint, and secrecy grep

**Files:** none.

- [ ] **Step 1: Clean build**

Run: `bun run build`
Expected: succeeds with no type errors or unresolved imports.

- [ ] **Step 2: Lint**

Run: `bun run lint`
Expected: PASS.

- [ ] **Step 3: Easter-egg secrecy gate** (must return nothing)

```bash
grep -rinE "psyduck|pok[eé]dex|cameo" marketing/ --include=*.tsx --include=*.ts --include=*.css --include=*.md
```
Expected: zero matches. If anything matches, rewrite it before proceeding.

- [ ] **Step 4: Residual-overclaim grep** (manual review of any hits)

```bash
grep -rinE "signature|quickbooks|shopify|square|associate|event mode|print or email|print and email" marketing/app marketing/components
```
Expected: only the intentional "(planned)" POS row and any harmless matches (e.g. CSS `square`-unrelated). Review each hit; demote or remove stragglers.

- [ ] **Step 5: Spot-check rendering** (optional but recommended)

Run: `bun dev`, open `http://localhost:3000`, and confirm: hero subhead mentions grading/movers; the IntelligenceSuite renders three rows with mocks; the easter-egg teaser shows the abstract silhouette and never names it; `/features`, `/for-shops`, `/for-vendors`, `/for-collectors`, `/changelog`, `/press` all build and read correctly. Toggle OS reduce-motion and confirm animations are neutralized.

- [ ] **Step 6: Final commit (if Step 4/5 required fixes)**

```bash
git add -A
git commit -m "chore(marketing): final verification fixes for feature-parity pass"
```

---

## Self-review notes

- **Spec coverage:** four-pillar reframe (Tasks 3, 5, 8) ✓; Pre-grade/Movers/Grade Gains (Tasks 3, 8, 9, 10, 11) ✓; Vendors/Transactions/offline (Task 8) ✓; easter-egg teaser, never named (Tasks 4, 7, 15) ✓; new SVG mocks (Task 3) ✓; overclaim auto-fix + before/after list (Tasks 1, 6, 8, 9, 10, 11, 12, 14) ✓; every-page scope incl. press/changelog/metadata (Tasks 12, 13) ✓.
- **Type consistency:** new icon names `gauge`/`crosshair` added to the union in Task 2 before first use (Tasks 3, 5, 8, 9, 10, 11); `FeatureCard`/`AudiencePoint`/`Entry` shapes reused unchanged; `IntelligenceSuite`/`EasterEggTeaser` named exports match their imports in Task 7.
- **Verification model:** lint per task, full build at phase boundaries and at the end — matching a codebase with no component test runner (documented up top).
