# Marketing Homepage Flow Walkthrough — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the homepage's high-level feature sections with a continuous "pinned device, advancing screens" walkthrough of the real buy-side flow (scan → comp → margin → offer → paid) plus a compact secondary-flows section, so the page reads as the actual app working.

**Architecture:** Two new client components. `FlowWalkthrough` pins an iPhone frame while an `IntersectionObserver` tracks which copy beat is centered and crossfades the phone's screen to the matching high-fidelity recreation; it degrades to a stacked, static layout on mobile (≤720px) and with `prefers-reduced-motion`. The five screen recreations are pure presentational components built from `SLAB` tokens + inline SVG/HTML, grounded in the real SwiftUI views. `BeyondTheOffer` reuses the existing Pre-grade/Movers/Grade-Gains mocks in a tighter section. No new dependencies; all content hardcoded.

**Tech Stack:** Next.js 16.2.4 App Router, React 19, TypeScript, inline styles + `lib/tokens.ts`, `components/icon.tsx`. Verification gate: `bun run build` (TS typecheck; lint is baseline-red per repo convention). There is no component test runner in `marketing/`, so each task is verified by a clean build plus the stated manual check.

**Spec:** `docs/superpowers/specs/2026-06-08-marketing-homepage-flow-walkthrough-design.md`

---

## File Structure

- Create `marketing/components/marketing/flow-steps.ts` — the `FlowStep` type + `FLOW_STEPS` copy/data (one responsibility: narrative content).
- Create `marketing/components/marketing/flow-screens.tsx` — the five screen recreations + a `FlowScreen` dispatcher (one responsibility: visual recreations).
- Create `marketing/components/marketing/flow-walkthrough.tsx` — the pinned/stacked harness (one responsibility: scroll orchestration + layout).
- Create `marketing/components/marketing/beyond-the-offer.tsx` — compact secondary-flows section.
- Modify `marketing/app/page.tsx` — new section order; drop replaced sections.
- Modify `marketing/components/marketing/hero.tsx` — subhead only.
- Modify `marketing/components/marketing/nav.tsx` — remove the Pricing link.
- Modify `marketing/components/marketing/footer.tsx` — remove the Pricing link.
- Delete (after import check) `feature-row.tsx`, `workflow.tsx`, `intelligence-suite.tsx`.

> Note: `nav.tsx` already has a `{ label: 'How it works', href: '/#how-it-works' }` link and footer the same. The walkthrough section MUST use `id="how-it-works"` so those existing anchors resolve. No new nav link needs adding.

All commands run from `marketing/`. Commit after each task.

---

## Task 1: Flow narrative data (`flow-steps.ts`)

**Files:**
- Create: `marketing/components/marketing/flow-steps.ts`

- [ ] **Step 1: Write the data module**

```ts
export type FlowStepId = 'scan' | 'comp' | 'margin' | 'offer' | 'paid';

export type FlowStep = {
  id: FlowStepId;
  n: string;        // '01'..'05'
  kicker: string;   // short uppercase label
  title: string;    // serif headline
  body: string;     // one or two sentences, dealer voice
};

export const FLOW_STEPS: FlowStep[] = [
  {
    id: 'scan',
    n: '01',
    kicker: 'Scan the stack',
    title: 'Point the camera. Keep going.',
    body: 'OCR reads the cert off each slab and queues it. Rows fill in as comps land — and keep queuing offline when the show wifi drops.',
  },
  {
    id: 'comp',
    n: '02',
    kicker: 'The defensible number',
    title: 'A real number, with its receipts.',
    body: 'Recent sold sales reconciled into one price, with a per-grade ladder and confidence. Not a vibe — a number you can show the seller.',
  },
  {
    id: 'margin',
    n: '03',
    kicker: 'Set your margin',
    title: 'Your spread, applied down the stack.',
    body: 'Every line gets a buy price — comp × your margin. Use a flat percentage or the store ladder, and override any single line by hand.',
  },
  {
    id: 'offer',
    n: '04',
    kicker: 'Send the offer',
    title: 'One total. Every line. In front of them.',
    body: 'Roll the lot into an offer: total, per-slab lines, payment method and reference. Make the call while the seller is still at the counter.',
  },
  {
    id: 'paid',
    n: '05',
    kicker: 'Mark it paid',
    title: 'Closed, frozen, on the books.',
    body: 'Paid lots lock into an immutable receipt — vendor, total, method, timestamp. Void with a reason if you must; the trail stays intact.',
  },
];
```

- [ ] **Step 2: Verify build**

Run: `bun run build`
Expected: compiles, no type errors (module is unused so far — that's fine).

- [ ] **Step 3: Commit**

```bash
git add components/marketing/flow-steps.ts
git commit -m "feat(marketing): add flow walkthrough step data"
```

---

## Task 2: Comp screen recreation (exemplar) + screen dispatcher (`flow-screens.tsx`)

This task establishes the screen file, shared screen primitives, and the richest screen (Comp). Tasks 3–6 add the other four screens to the SAME file following these primitives.

**Source of truth:** `ios/.../Features/Comp/CompCardView.swift`. Reproduce: headline serif price, hero caption, AVG/RANGE/SALES aggregate strip, sparkline, per-grade ladder rail, "Comp data from Poketrace" footer.

**Files:**
- Create: `marketing/components/marketing/flow-screens.tsx`

- [ ] **Step 1: Write shared primitives + the Comp screen**

```tsx
import { SLAB } from '@/lib/tokens';

// ---- shared screen chrome -------------------------------------------------
// Every screen renders inside the device viewport at a fixed logical size so
// the recreations line up across crossfades. The device frame is owned by
// flow-walkthrough.tsx; screens fill their parent.
const screenWrap: React.CSSProperties = {
  position: 'absolute',
  inset: 0,
  background: SLAB.surface,
  padding: 18,
  overflow: 'hidden',
  display: 'flex',
  flexDirection: 'column',
  gap: 12,
  fontFamily: SLAB.sans,
  color: SLAB.text,
};

function Kicker({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ fontSize: 10, letterSpacing: 1.4, textTransform: 'uppercase', color: SLAB.dim, fontWeight: 500 }}>
      {children}
    </div>
  );
}

function Card({ children, style }: { children: React.ReactNode; style?: React.CSSProperties }) {
  return (
    <div
      style={{
        background: SLAB.elev,
        border: '1px solid ' + SLAB.hair,
        borderRadius: 14,
        padding: 14,
        ...style,
      }}
    >
      {children}
    </div>
  );
}

// ---- 02 · Comp ------------------------------------------------------------
const LADDER: [string, string, boolean][] = [
  ['Raw', '$4', false],
  ['PSA 10', '$185', true],
  ['PSA 9.5', '$112', false],
  ['PSA 9', '$68', false],
  ['PSA 8', '$34', false],
  ['BGS 10', '$215', false],
];

function CompScreen() {
  return (
    <div style={screenWrap}>
      <Card>
        <div style={{ fontFamily: SLAB.serif, fontSize: 40, letterSpacing: -1, lineHeight: 1 }}>$188</div>
        <div style={{ fontSize: 10, letterSpacing: 2, textTransform: 'uppercase', color: SLAB.dim, marginTop: 6 }}>
          Poketrace · n=14 · PSA 10
        </div>
        <div style={{ display: 'flex', marginTop: 14, borderTop: '1px solid ' + SLAB.hair, paddingTop: 12 }}>
          {([['AVG', '$188'], ['RANGE', '$175–$210'], ['SALES', 'n=14 ▲']] as const).map(([t, v], i) => (
            <div key={t} style={{ flex: 1, paddingLeft: i ? 12 : 0, borderLeft: i ? '1px solid ' + SLAB.hair : 'none' }}>
              <div style={{ fontSize: 9, letterSpacing: 1.2, textTransform: 'uppercase', color: SLAB.dim }}>{t}</div>
              <div style={{ fontFamily: SLAB.mono, fontSize: 13, fontWeight: 600, marginTop: 3 }}>{v}</div>
            </div>
          ))}
        </div>
        {/* sparkline */}
        <svg width="100%" height="32" viewBox="0 0 200 32" style={{ marginTop: 12 }} aria-hidden>
          <polyline points="0,24 30,20 60,22 90,14 120,16 150,8 200,6" fill="none" stroke={SLAB.gold} strokeWidth="1.5" />
        </svg>
      </Card>

      <Kicker>Per-grade ladder</Kicker>
      <div style={{ display: 'flex', gap: 8, overflowX: 'hidden' }}>
        {LADDER.map(([g, p, hot]) => (
          <div
            key={g}
            style={{
              flex: '0 0 auto',
              padding: '8px 10px',
              borderRadius: 10,
              border: (hot ? '1.5px solid ' + SLAB.gold : '1px solid ' + SLAB.hair),
            }}
          >
            <div style={{ fontSize: 9, letterSpacing: 1.2, textTransform: 'uppercase', color: SLAB.dim }}>{g}</div>
            <div style={{ fontFamily: SLAB.mono, fontSize: 13, marginTop: 2 }}>{p}</div>
          </div>
        ))}
      </div>

      <div style={{ marginTop: 'auto', fontSize: 11, color: SLAB.dim }}>Comp data from Poketrace</div>
    </div>
  );
}

// ---- dispatcher (extended in later tasks) --------------------------------
export function FlowScreen({ step }: { step: number }) {
  switch (step) {
    case 1:
      return <CompScreen />;
    default:
      return <CompScreen />; // replaced as screens are added in Tasks 3–6
  }
}
```

- [ ] **Step 2: Verify build**

Run: `bun run build`
Expected: compiles, no type errors.

- [ ] **Step 3: Commit**

```bash
git add components/marketing/flow-screens.tsx
git commit -m "feat(marketing): add comp screen recreation + screen primitives"
```

---

## Task 3: Scan screen recreation

**Source:** `ScanQueueView.swift` / `ScanRowTrailingState.swift`. A dark queue panel: "Queue" kicker + "12 scanned", then scan rows: status dot + `GRADER · CERT` + trailing state (mono $ / "Set price" pill / `$25 ✎` / "pending validation").

**Files:**
- Modify: `marketing/components/marketing/flow-screens.tsx`

- [ ] **Step 1: Add the Scan screen above the dispatcher**

```tsx
type ScanRow = { grader: string; cert: string; dot: string; trail: React.ReactNode };

function ScanScreen() {
  const rows: ScanRow[] = [
    { grader: 'PSA', cert: '12345678', dot: SLAB.pos, trail: <span style={{ fontFamily: SLAB.mono, fontWeight: 600 }}>$188</span> },
    { grader: 'BGS', cert: '0098761234', dot: SLAB.gold, trail: <Pill>Set price</Pill> },
    { grader: 'CGC', cert: '4012998877', dot: SLAB.gold, trail: <span style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim }}>pending validation</span> },
    { grader: 'SGC', cert: '88412290', dot: SLAB.muted, trail: <span style={{ fontFamily: SLAB.mono, fontWeight: 600 }}>$42 ✎</span> },
    { grader: 'PSA', cert: '55120934', dot: SLAB.pos, trail: <span style={{ fontFamily: SLAB.mono, fontWeight: 600 }}>$96</span> },
  ];
  return (
    <div style={{ ...screenWrap, background: SLAB.ink, justifyContent: 'flex-end' }}>
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(ellipse at 50% 35%, oklch(0.13 0.005 78), oklch(0.05 0.002 78))' }} aria-hidden />
      {/* scan-frame brackets */}
      <div style={{ position: 'absolute', top: 70, left: 40, right: 40, height: 150, border: '1px solid ' + SLAB.hairStrong, borderRadius: 10 }} aria-hidden />
      <Card style={{ position: 'relative', background: 'oklch(0.10 0.004 78 / 0.94)' }}>
        <Kicker>Queue</Kicker>
        <div style={{ margin: '2px 0 10px' }}>
          <span style={{ fontFamily: SLAB.mono, fontSize: 20, fontWeight: 600 }}>12</span>
          <span style={{ color: SLAB.muted, fontSize: 13 }}> scanned</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {rows.map((r, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span style={{ width: 8, height: 8, borderRadius: 999, background: r.dot, flexShrink: 0 }} />
              <span style={{ fontFamily: SLAB.mono, fontSize: 12 }}>{r.grader} · {r.cert}</span>
              <span style={{ marginLeft: 'auto', fontSize: 12 }}>{r.trail}</span>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}

function Pill({ children }: { children: React.ReactNode }) {
  return (
    <span style={{ fontSize: 11, color: SLAB.gold, border: '1px solid ' + SLAB.gold, borderRadius: 999, padding: '2px 8px' }}>
      {children}
    </span>
  );
}
```

- [ ] **Step 2: Wire into the dispatcher** — change `case 0` to return `<ScanScreen />` (add `case 0: return <ScanScreen />;`).

- [ ] **Step 3: Verify build** — Run: `bun run build`. Expected: compiles.

- [ ] **Step 4: Commit**

```bash
git add components/marketing/flow-screens.tsx
git commit -m "feat(marketing): add scan screen recreation"
```

---

## Task 4: Margin screen recreation

**Source:** `LotDetailView.swift` + `LotMarginSheet.swift`. Show: "ESTIMATED" hero total, a "Margin — 70% of comp" row with a Fixed%/Store-ladder toggle and snap chips, and slab lines each with comp + "Buy $131" (comp × margin; gold when overridden).

**Files:**
- Modify: `marketing/components/marketing/flow-screens.tsx`

- [ ] **Step 1: Add the Margin screen above the dispatcher**

```tsx
function MarginScreen() {
  const lines: [string, string, string, boolean][] = [
    // name, comp, buy, overridden
    ['Charizard #4', '$188', 'Buy $131', false],
    ['Blastoise #2', '$96', 'Buy $67', false],
    ['Venusaur #15', '$74', 'Buy $60', true],
  ];
  return (
    <div style={screenWrap}>
      <Card>
        <Kicker>Estimated</Kicker>
        <div style={{ fontFamily: SLAB.serif, fontSize: 38, letterSpacing: -1, lineHeight: 1, marginTop: 4 }}>$1,240</div>
        <div style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim, marginTop: 4 }}>across 9 slabs · 2 manual</div>
      </Card>

      <Card>
        <Kicker>Margin</Kicker>
        <div style={{ display: 'flex', gap: 4, background: SLAB.elev2, borderRadius: 10, padding: 3, margin: '8px 0' }}>
          <div style={{ flex: 1, textAlign: 'center', fontSize: 11, padding: '6px 0', borderRadius: 8, background: SLAB.gold, color: SLAB.ink, fontWeight: 600 }}>Fixed %</div>
          <div style={{ flex: 1, textAlign: 'center', fontSize: 11, padding: '6px 0', color: SLAB.muted }}>Store ladder</div>
        </div>
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {['70%', '75%', '80%', '85%', '90%'].map((c) => (
            <span key={c} style={{ fontSize: 11, fontFamily: SLAB.mono, padding: '4px 8px', borderRadius: 999, border: (c === '70%' ? '1.5px solid ' + SLAB.gold : '1px solid ' + SLAB.hair), color: c === '70%' ? SLAB.gold : SLAB.muted }}>{c}</span>
          ))}
        </div>
      </Card>

      <Kicker>Slabs</Kicker>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        {lines.map(([name, comp, buy, over]) => (
          <div key={name} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ width: 8, height: 8, borderRadius: 999, background: SLAB.pos }} />
            <span style={{ fontSize: 12 }}>{name}</span>
            <span style={{ marginLeft: 'auto', fontFamily: SLAB.mono, fontSize: 11, color: SLAB.muted }}>{comp}</span>
            <span style={{ fontFamily: SLAB.mono, fontSize: 12, fontWeight: 600, color: over ? SLAB.gold : SLAB.text }}>{buy}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Wire `case 2: return <MarginScreen />;` into the dispatcher.**

- [ ] **Step 3: Verify build** — Run: `bun run build`. Expected: compiles.

- [ ] **Step 4: Commit**

```bash
git add components/marketing/flow-screens.tsx
git commit -m "feat(marketing): add margin screen recreation"
```

---

## Task 5: Offer screen recreation

**Source:** `OfferReviewView.swift`. Show: "Vendor" header, "Offer total" serif $1,240 with "9 lines · 70% margin", per-line `GRADER GRADE · CERT → $buy`, a Payment card (method segmented = cash, reference field), gold "Mark paid" CTA.

**Files:**
- Modify: `marketing/components/marketing/flow-screens.tsx`

- [ ] **Step 1: Add the Offer screen above the dispatcher**

```tsx
function OfferScreen() {
  const lines: [string, string][] = [
    ['PSA 10 · 12345678', '$131'],
    ['PSA 9 · 0098761234', '$67'],
    ['PSA 10 · 4012998877', '$60'],
  ];
  return (
    <div style={screenWrap}>
      <div>
        <Kicker>Vendor</Kicker>
        <div style={{ fontFamily: SLAB.serif, fontSize: 22, letterSpacing: -0.4 }}>Mike&apos;s Card Shop</div>
      </div>
      <Card>
        <Kicker>Offer total</Kicker>
        <div style={{ fontFamily: SLAB.serif, fontSize: 38, letterSpacing: -1, lineHeight: 1, marginTop: 4 }}>$1,240</div>
        <div style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim, marginTop: 4 }}>9 lines · 70% margin</div>
      </Card>
      <Kicker>Lines</Kicker>
      <Card>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
          {lines.map(([l, v]) => (
            <div key={l} style={{ display: 'flex', alignItems: 'center' }}>
              <span style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.muted }}>{l}</span>
              <span style={{ marginLeft: 'auto', fontFamily: SLAB.mono, fontSize: 13, fontWeight: 600 }}>{v}</span>
            </div>
          ))}
        </div>
      </Card>
      <Card>
        <Kicker>Payment</Kicker>
        <div style={{ display: 'flex', gap: 4, background: SLAB.elev2, borderRadius: 10, padding: 3, margin: '8px 0 6px' }}>
          {['cash', 'check', 'digital'].map((m) => (
            <div key={m} style={{ flex: 1, textAlign: 'center', fontSize: 11, padding: '6px 0', borderRadius: 8, background: m === 'cash' ? SLAB.gold : 'transparent', color: m === 'cash' ? SLAB.ink : SLAB.muted, fontWeight: m === 'cash' ? 600 : 400 }}>{m}</div>
          ))}
        </div>
        <div style={{ fontSize: 11, color: SLAB.dim, border: '1px solid ' + SLAB.hair, borderRadius: 8, padding: '8px 10px' }}>Reference (check #, Venmo handle, …)</div>
      </Card>
      <div style={{ marginTop: 'auto', textAlign: 'center', background: SLAB.gold, color: SLAB.ink, fontWeight: 600, fontSize: 13, padding: '12px 0', borderRadius: 10 }}>Mark paid</div>
    </div>
  );
}
```

- [ ] **Step 2: Wire `case 3: return <OfferScreen />;`.**

- [ ] **Step 3: Verify build** — Run: `bun run build`. Expected: compiles.

- [ ] **Step 4: Commit**

```bash
git add components/marketing/flow-screens.tsx
git commit -m "feat(marketing): add offer screen recreation"
```

---

## Task 6: Paid screen recreation + finalize dispatcher

**Source:** `TransactionDetailView.swift`. Show: "Receipt" header, vendor + timestamp, "Total" serif $1,240 + "cash", frozen line rows (name / `set · GRADER GRADE` / $buy). No gold in the steady receipt.

**Files:**
- Modify: `marketing/components/marketing/flow-screens.tsx`

- [ ] **Step 1: Add the Paid screen above the dispatcher**

```tsx
function PaidScreen() {
  const lines: [string, string, string][] = [
    ['Charizard #4', 'Base Set · PSA 10', '$131'],
    ['Blastoise #2', 'Base Set · PSA 9', '$67'],
    ['Venusaur #15', 'Base Set · PSA 10', '$60'],
  ];
  return (
    <div style={screenWrap}>
      <div>
        <Kicker>Receipt</Kicker>
        <div style={{ fontFamily: SLAB.serif, fontSize: 22, letterSpacing: -0.4 }}>Mike&apos;s Card Shop</div>
        <div style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim, marginTop: 2 }}>Jun 7, 2026 at 2:14 PM</div>
      </div>
      <Card>
        <Kicker>Total</Kicker>
        <div style={{ fontFamily: SLAB.serif, fontSize: 38, letterSpacing: -1, lineHeight: 1, marginTop: 4 }}>$1,240</div>
        <div style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim, marginTop: 4 }}>cash</div>
      </Card>
      <Kicker>Lines</Kicker>
      <Card>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {lines.map(([name, sub, v]) => (
            <div key={name} style={{ display: 'flex', alignItems: 'center' }}>
              <div>
                <div style={{ fontSize: 13 }}>{name}</div>
                <div style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim }}>{sub}</div>
              </div>
              <span style={{ marginLeft: 'auto', fontFamily: SLAB.mono, fontSize: 13, fontWeight: 600 }}>{v}</span>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}
```

- [ ] **Step 2: Finalize the dispatcher** so all five cases are wired:

```tsx
export function FlowScreen({ step }: { step: number }) {
  switch (step) {
    case 0: return <ScanScreen />;
    case 1: return <CompScreen />;
    case 2: return <MarginScreen />;
    case 3: return <OfferScreen />;
    case 4: return <PaidScreen />;
    default: return <ScanScreen />;
  }
}
```

- [ ] **Step 3: Verify build** — Run: `bun run build`. Expected: compiles.

- [ ] **Step 4: Commit**

```bash
git add components/marketing/flow-screens.tsx
git commit -m "feat(marketing): add paid screen recreation, finalize dispatcher"
```

---

## Task 7: The walkthrough harness (`flow-walkthrough.tsx`)

Pinned device + observer-driven crossfade; stacked static fallback for mobile/reduced-motion.

**Files:**
- Create: `marketing/components/marketing/flow-walkthrough.tsx`

- [ ] **Step 1: Write the component**

```tsx
'use client';

import { useEffect, useRef, useState } from 'react';
import { SLAB } from '@/lib/tokens';
import { FLOW_STEPS, type FlowStep } from './flow-steps';
import { FlowScreen } from './flow-screens';

const VIEWPORT_W = 300;
const VIEWPORT_H = 620;

function Device({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        width: VIEWPORT_W,
        height: VIEWPORT_H,
        borderRadius: 44,
        background: 'oklch(0.06 0.003 78)',
        padding: 10,
        margin: '0 auto',
        boxShadow: '0 30px 70px oklch(0 0 0 / 0.40), 0 0 0 1px oklch(0.16 0.005 78), 0 0 0 6px oklch(0.21 0.006 78)',
      }}
    >
      <div style={{ position: 'relative', width: '100%', height: '100%', borderRadius: 36, overflow: 'hidden' }}>
        {children}
      </div>
    </div>
  );
}

function Beat({ step, active }: { step: FlowStep; active: boolean }) {
  return (
    <div style={{ opacity: active ? 1 : 0.4, transition: 'opacity 0.3s ease' }}>
      <div style={{ fontFamily: SLAB.mono, fontSize: 12, color: SLAB.gold, marginBottom: 10 }}>{step.n}</div>
      <div style={{ fontSize: 11, letterSpacing: 1.6, textTransform: 'uppercase', color: SLAB.dim, marginBottom: 12, fontWeight: 500 }}>{step.kicker}</div>
      <h3 style={{ fontFamily: SLAB.serif, fontSize: 'clamp(28px, 3.4vw, 40px)', fontWeight: 400, letterSpacing: -1, lineHeight: 1.05, margin: '0 0 16px' }}>{step.title}</h3>
      <p style={{ fontSize: 15, color: SLAB.muted, lineHeight: 1.6, maxWidth: '46ch', margin: 0 }}>{step.body}</p>
    </div>
  );
}

function SectionHeader() {
  return (
    <div style={{ marginBottom: 'clamp(40px, 5vw, 64px)', maxWidth: 620 }}>
      <div style={{ fontSize: 12, letterSpacing: 1.6, textTransform: 'uppercase', color: SLAB.gold, marginBottom: 18, fontWeight: 500 }}>How it works</div>
      <h2 style={{ fontFamily: SLAB.serif, fontSize: 'clamp(40px, 5vw, 64px)', fontWeight: 400, letterSpacing: -1.5, lineHeight: 1.05, margin: 0 }}>
        Watch a stack turn into a paid offer.
      </h2>
    </div>
  );
}

export function FlowWalkthrough() {
  const [active, setActive] = useState(0);
  const [stacked, setStacked] = useState(false);
  const beatRefs = useRef<(HTMLDivElement | null)[]>([]);

  useEffect(() => {
    const rm = window.matchMedia('(prefers-reduced-motion: reduce)');
    const mob = window.matchMedia('(max-width: 720px)');
    const update = () => setStacked(rm.matches || mob.matches);
    update();
    rm.addEventListener('change', update);
    mob.addEventListener('change', update);
    return () => {
      rm.removeEventListener('change', update);
      mob.removeEventListener('change', update);
    };
  }, []);

  useEffect(() => {
    if (stacked) return;
    const obs = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            const i = beatRefs.current.indexOf(e.target as HTMLDivElement);
            if (i >= 0) setActive(i);
          }
        });
      },
      { rootMargin: '-45% 0px -45% 0px', threshold: 0 },
    );
    beatRefs.current.forEach((el) => el && obs.observe(el));
    return () => obs.disconnect();
  }, [stacked]);

  const sectionStyle: React.CSSProperties = {
    padding: 'clamp(84px, 11vw, 120px) 0',
    borderTop: '1px solid ' + SLAB.hair,
  };
  const container: React.CSSProperties = { maxWidth: 1180, margin: '0 auto', padding: '0 24px' };

  if (stacked) {
    return (
      <section id="how-it-works" style={sectionStyle}>
        <div style={container}>
          <SectionHeader />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'clamp(56px, 9vw, 80px)' }}>
            {FLOW_STEPS.map((s, i) => (
              <div key={s.id}>
                <div style={{ width: VIEWPORT_W, maxWidth: '100%', marginBottom: 28 }}>
                  <Device>
                    <FlowScreen step={i} />
                  </Device>
                </div>
                <Beat step={s} active />
              </div>
            ))}
          </div>
        </div>
      </section>
    );
  }

  return (
    <section id="how-it-works" style={sectionStyle}>
      <div style={container}>
        <SectionHeader />
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 48, alignItems: 'start' }}>
          <div style={{ position: 'sticky', top: 100, height: 'fit-content' }}>
            <Device>
              {FLOW_STEPS.map((s, i) => (
                <div
                  key={s.id}
                  aria-hidden
                  style={{ position: 'absolute', inset: 0, opacity: active === i ? 1 : 0, transition: 'opacity 0.4s ease', pointerEvents: 'none' }}
                >
                  <FlowScreen step={i} />
                </div>
              ))}
            </Device>
          </div>
          <div>
            {FLOW_STEPS.map((s, i) => (
              <div
                key={s.id}
                ref={(el) => {
                  beatRefs.current[i] = el;
                }}
                style={{ minHeight: '78vh', display: 'flex', flexDirection: 'column', justifyContent: 'center' }}
              >
                <Beat step={s} active={active === i} />
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
```

> Note on the `<FlowScreen>` chrome: screens use `position: absolute; inset: 0` (see `screenWrap`), so each fills the `Device` viewport whether stacked (one screen) or pinned (five stacked + crossfaded). Confirm visually that the stacked path shows exactly one screen per step.

- [ ] **Step 2: Verify build** — Run: `bun run build`. Expected: compiles (still unused by a page).

- [ ] **Step 3: Commit**

```bash
git add components/marketing/flow-walkthrough.tsx
git commit -m "feat(marketing): add pinned/stacked flow walkthrough harness"
```

---

## Task 8: BeyondTheOffer secondary section

Reuse the three mocks from `intelligence-suite.tsx` in a tighter three-beat section. Before writing, open `intelligence-suite.tsx` and copy its Pre-grade / Movers / Grade-Gains mock JSX into local mock functions here (so deleting `intelligence-suite.tsx` in Task 11 is safe).

**Files:**
- Create: `marketing/components/marketing/beyond-the-offer.tsx`

- [ ] **Step 1: Write the section**

```tsx
import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';

type Beat = { icon: IconName; kicker: string; title: string; body: string };

const BEATS: Beat[] = [
  { icon: 'gauge', kicker: 'Pre-grade', title: 'Grade the walk-in first', body: 'Camera-grade a raw card to a PSA-equivalent composite with sub-grades before you commit a dollar to submission.' },
  { icon: 'chart', kicker: 'Movers', title: 'See where the market’s heading', body: 'Top gainers and losers by set and price tier, English or Japanese, with a 30-day trend on every card.' },
  { icon: 'zap', kicker: 'Grade gains', title: 'Find the cards worth sending in', body: 'Raw cards ranked by their upside to a PSA 10, net of the grading fee — dial the fee to your submission tier.' },
];

export function BeyondTheOffer() {
  return (
    <section style={{ padding: 'clamp(84px, 11vw, 120px) 0', borderTop: '1px solid ' + SLAB.hair }}>
      <div style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
        <div style={{ marginBottom: 'clamp(40px, 5vw, 56px)', maxWidth: 620 }}>
          <div style={{ fontSize: 12, letterSpacing: 1.6, textTransform: 'uppercase', color: SLAB.gold, marginBottom: 18, fontWeight: 500 }}>Beyond the offer</div>
          <h2 style={{ fontFamily: SLAB.serif, fontSize: 'clamp(36px, 4.5vw, 52px)', fontWeight: 400, letterSpacing: -1.2, lineHeight: 1.05, margin: 0 }}>
            The market intelligence around every buy.
          </h2>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: 1, background: SLAB.hair, border: '1px solid ' + SLAB.hair, borderRadius: 16, overflow: 'hidden' }}>
          {BEATS.map((b) => (
            <div key={b.kicker} style={{ padding: '28px 26px 32px', background: SLAB.ink, display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <Icon name={b.icon} size={17} sw={1.8} color={SLAB.gold} />
                <div style={{ fontSize: 11, letterSpacing: 1.4, textTransform: 'uppercase', color: SLAB.dim, fontWeight: 500 }}>{b.kicker}</div>
              </div>
              <div style={{ fontFamily: SLAB.serif, fontSize: 24, letterSpacing: -0.4 }}>{b.title}</div>
              <div style={{ fontSize: 14, color: SLAB.muted, lineHeight: 1.55 }}>{b.body}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
```

> If you want the richer mini-screens from `intelligence-suite.tsx` instead of icon beats, port those mock JSX blocks into this file in place of the icon row. The icon-beat version above is the minimum that satisfies the spec.

- [ ] **Step 2: Verify build** — Run: `bun run build`. Expected: compiles.

- [ ] **Step 3: Commit**

```bash
git add components/marketing/beyond-the-offer.tsx
git commit -m "feat(marketing): add beyond-the-offer secondary section"
```

---

## Task 9: Tighten the hero subhead

**Files:**
- Modify: `marketing/components/marketing/hero.tsx`

- [ ] **Step 1: Locate the hero subhead paragraph** (the descriptive sentence under the H1). Read the file and find the current subhead text.

- [ ] **Step 2: Replace the subhead copy** with text that sets up the walkthrough and invites the scroll. Keep the existing element/styles; change only the string. Target copy:

```
Scan a stack of graded slabs, get a defensible number from real sales, and hand the seller an offer before they leave the counter. Here’s the whole flow.
```

- [ ] **Step 3: Verify build** — Run: `bun run build`. Expected: compiles.

- [ ] **Step 4: Commit**

```bash
git add components/marketing/hero.tsx
git commit -m "feat(marketing): point hero subhead at the flow walkthrough"
```

---

## Task 10: Wire the homepage

**Files:**
- Modify: `marketing/app/page.tsx`

- [ ] **Step 1: Replace the file** with the new section order:

```tsx
import { Nav } from '@/components/marketing/nav';
import { Hero } from '@/components/marketing/hero';
import { FlowWalkthrough } from '@/components/marketing/flow-walkthrough';
import { BeyondTheOffer } from '@/components/marketing/beyond-the-offer';
import { EasterEggTeaser } from '@/components/marketing/easter-egg-teaser';
import { Pricing } from '@/components/marketing/pricing';
import { FinalCta } from '@/components/marketing/final-cta';
import { Footer } from '@/components/marketing/footer';

export default function Home() {
  return (
    <>
      <Nav />
      <Hero />
      <FlowWalkthrough />
      <BeyondTheOffer />
      <EasterEggTeaser />
      <Pricing />
      <FinalCta />
      <Footer />
    </>
  );
}
```

- [ ] **Step 2: Verify build + manual review** — Run: `bun run build`. Then `bun dev`, open `/`, scroll the walkthrough: the device should pin and the screen should crossfade scan→comp→margin→offer→paid as beats pass. The `/#how-it-works` nav link should jump to the section.

- [ ] **Step 3: Manual responsive/motion check** — In devtools, set width ≤720px: the section renders stacked (no pin). Enable "Emulate prefers-reduced-motion: reduce": stacked, no crossfade.

- [ ] **Step 4: Commit**

```bash
git add app/page.tsx
git commit -m "feat(marketing): rebuild homepage around the flow walkthrough"
```

---

## Task 11: Remove the Pricing nav/footer links and delete orphaned components

**Files:**
- Modify: `marketing/components/marketing/nav.tsx`
- Modify: `marketing/components/marketing/footer.tsx`
- Delete: `marketing/components/marketing/feature-row.tsx`, `workflow.tsx`, `intelligence-suite.tsx`

- [ ] **Step 1: Remove the Pricing link from `nav.tsx`** — delete the line `{ label: 'Pricing', href: '/#pricing' },` from `NAV_LINKS`.

- [ ] **Step 2: Remove the Pricing link from `footer.tsx`** — delete the line `{ label: 'Pricing', href: '/#pricing' },` from the Product column's `links`.

- [ ] **Step 3: Confirm the three components are orphaned**

Run: `grep -rn "feature-row\|FeatureRow\|workflow\|Workflow\|intelligence-suite\|IntelligenceSuite" app components`
Expected: no imports remain (only the files' own definitions). If anything still imports them, stop and resolve before deleting.

- [ ] **Step 4: Delete the orphaned files**

```bash
git rm components/marketing/feature-row.tsx components/marketing/workflow.tsx components/marketing/intelligence-suite.tsx
```

- [ ] **Step 5: Verify build** — Run: `bun run build`. Expected: compiles; all 15 routes generate.

- [ ] **Step 6: Commit**

```bash
git add components/marketing/nav.tsx components/marketing/footer.tsx
git commit -m "chore(marketing): drop Pricing nav/footer links and orphaned homepage sections"
```

---

## Task 12: Final verification

- [ ] **Step 1: Full build** — Run: `bun run build`. Expected: success, 15 routes, no type errors.

- [ ] **Step 2: Grep checks**

Run: `grep -rn "/#pricing" app components` → Expected: none.
Run: `grep -rn "how-it-works" app components` → Expected: nav link, footer link, and the `id="how-it-works"` on the section.

- [ ] **Step 3: Manual pass** — `bun dev`: home scrolls scan→paid with the pinned device; secondary section reads Pre-grade/Movers/Grade-Gains; mobile + reduced-motion both render stacked-static; `/features` and audience pages unchanged and still build.

- [ ] **Step 4: Final commit (if any stragglers)**

```bash
git add -A && git commit -m "test(marketing): verify homepage flow walkthrough end-to-end"
```

---

## Self-Review (completed during authoring)

- **Spec coverage:** continuous scan→comp→margin→offer→paid narrative (Tasks 2–7, 10) ✓; high-fidelity recreations grounded in real views (Tasks 2–6) ✓; pinned w/ crossfade (Task 7) ✓; mobile + reduced-motion stacked fallback (Task 7, 10) ✓; BeyondTheOffer secondary (Task 8) ✓; hero subhead (Task 9) ✓; remove Pricing nav/footer (Task 11) ✓; remove FeatureRow/Workflow/IntelligenceSuite (Task 11) ✓; `aria-hidden` screens (screen primitives + harness) ✓; AA contrast (uses `SLAB` post-`dim`-fix) ✓; no new deps / hardcoded content ✓; build/reduced-motion/mobile verification (Task 12) ✓. Other pages untouched ✓.
- **Type consistency:** `FlowStep`/`FLOW_STEPS` (Task 1) consumed in Tasks 7; `FlowScreen({ step }: { step: number })` defined Task 2, extended 3–6, consumed Task 7; `screenWrap`/`Kicker`/`Card`/`Pill` defined Task 2/3 before use. ✓
- **Placeholders:** none — every code step is complete; the only "your choice" note (richer BeyondTheOffer mocks) has a complete default implementation. ✓
