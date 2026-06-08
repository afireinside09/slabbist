import type { Metadata } from 'next';
import { SLAB } from '@/lib/tokens';
import { PageShell, PageHero } from '@/components/marketing/page-shell';

export const metadata: Metadata = {
  title: 'Changelog · Slabbist',
  description: 'Every Slabbist release — what shipped, what changed, and what is coming.',
};

type Entry = {
  date: string;
  version: string;
  title: string;
  tag: 'beta' | 'internal' | 'preview';
  bullets: string[];
};

const TAG_STYLES: Record<Entry['tag'], { bg: string; fg: string; label: string }> = {
  beta: { bg: 'oklch(0.82 0.13 78 / 0.13)', fg: SLAB.gold, label: 'Closed beta' },
  internal: { bg: 'oklch(0.21 0.007 78)', fg: SLAB.muted, label: 'Internal' },
  preview: { bg: 'oklch(0.78 0.14 155 / 0.15)', fg: SLAB.pos, label: 'Preview' },
};

const ENTRIES: Entry[] = [
  {
    date: '2026-06-07',
    version: '0.10.0',
    title: 'Pre-grade, movers, and grade gains',
    tag: 'beta',
    bullets: [
      'Pre-grade: estimate the PSA-equivalent grade on-device with centering, corners, edges, and surface sub-grades.',
      'Centering tool with snap-to-edge guides and live left/right and top/bottom ratios.',
      'Movers: top gainers and losers by set and price tier, English or Japanese.',
      'Grade gains: see how much profit you could make grading a raw card to PSA 10, with a live grading-fee stepper.',
      'There is also something hidden in here. We are not going to tell you where.',
    ],
  },
  {
    date: '2026-04-18',
    version: '0.9.0',
    title: 'Lots, offers, and the transaction ledger',
    tag: 'beta',
    bullets: [
      'Group scans into a lot, present an offer, and mark it paid with a payment method and reference number.',
      'Paid lots lock and move into a permanent transaction ledger. You can void one with a reason if you need to.',
      'Vendor registry with contact details and notes, attachable to any lot.',
    ],
  },
  {
    date: '2026-03-28',
    version: '0.8.2',
    title: 'TAG grading support',
    tag: 'beta',
    bullets: [
      'The camera now reads cert numbers on TAG-graded slabs alongside PSA, BGS, CGC, and SGC.',
      'Confidence scoring now accounts for comp volume and price spread per grade.',
      'Fixed a sync stall when a queued scan had no cert number.',
    ],
  },
  {
    date: '2026-03-10',
    version: '0.8.0',
    title: 'Margin ladder',
    tag: 'beta',
    bullets: [
      'Set a buy percentage for each price tier. Each slab prices against its comp at the highest tier it clears.',
      'Override any single buy price by hand.',
      'The ladder locks onto an offer the moment you present it.',
    ],
  },
  {
    date: '2026-01-22',
    version: '0.6.0',
    title: 'Offline-first queue',
    tag: 'preview',
    bullets: [
      'Scans, edits, and offers save locally and sync when you reconnect.',
      'Failed syncs surface in a sheet you can retry or discard.',
    ],
  },
  {
    date: '2025-12-08',
    version: '0.5.0',
    title: 'Comp engine v1',
    tag: 'internal',
    bullets: [
      'Prices from recent sales, with range, sale count, trend, and a per-grade breakdown.',
      '30-day price history on every card.',
      'Tap any price to see the individual sales behind it.',
    ],
  },
];

export default function ChangelogPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Changelog"
        title="What shipped, when it shipped, and what broke."
        italicize="broke"
        subtitle="Slabbist is in closed beta with a handful of stores. Here is everything that has gone out — what is working, what got fixed, and what is still in flight."
      />

      <section
        style={{
          padding: 'clamp(40px, 6vw, 64px) 0 clamp(96px, 12vw, 140px)',
          borderTop: '1px solid ' + SLAB.hair,
        }}
      >
        <div style={{ maxWidth: 820, margin: '0 auto', padding: '0 24px' }}>
          {ENTRIES.map((e, i) => {
            const tagStyle = TAG_STYLES[e.tag];
            return (
              <article
                key={e.version}
                style={{
                  paddingTop: i === 0 ? 48 : 56,
                  paddingBottom: i === ENTRIES.length - 1 ? 0 : 0,
                  borderTop: i === 0 ? 'none' : '1px solid ' + SLAB.hair,
                }}
              >
                <div
                  style={{
                    display: 'flex',
                    gap: 12,
                    alignItems: 'center',
                    marginBottom: 14,
                    flexWrap: 'wrap',
                  }}
                >
                  <span
                    style={{
                      fontFamily: SLAB.mono,
                      fontSize: 12,
                      color: SLAB.muted,
                      letterSpacing: 0.4,
                    }}
                  >
                    {e.date}
                  </span>
                  <span style={{ color: SLAB.dim }}>·</span>
                  <span
                    style={{
                      fontFamily: SLAB.mono,
                      fontSize: 12,
                      color: SLAB.text,
                      letterSpacing: 0.4,
                    }}
                  >
                    v{e.version}
                  </span>
                  <span
                    style={{
                      fontSize: 10,
                      letterSpacing: 1.2,
                      textTransform: 'uppercase',
                      padding: '3px 8px',
                      borderRadius: 4,
                      background: tagStyle.bg,
                      color: tagStyle.fg,
                      fontWeight: 600,
                    }}
                  >
                    {tagStyle.label}
                  </span>
                </div>
                <h2
                  style={{
                    fontFamily: SLAB.serif,
                    fontSize: 30,
                    fontWeight: 400,
                    letterSpacing: -0.6,
                    lineHeight: 1.15,
                    margin: '0 0 18px',
                  }}
                >
                  {e.title}
                </h2>
                <ul
                  style={{
                    margin: 0,
                    paddingLeft: 22,
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 10,
                    fontSize: 15,
                    color: SLAB.text,
                    lineHeight: 1.55,
                    opacity: 0.88,
                  }}
                >
                  {e.bullets.map((b) => (
                    <li key={b}>{b}</li>
                  ))}
                </ul>
              </article>
            );
          })}
        </div>
      </section>
    </PageShell>
  );
}
