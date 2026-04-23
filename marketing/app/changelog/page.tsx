import type { Metadata } from 'next';
import { SLAB } from '@/lib/tokens';
import { PageShell, PageHero } from '@/components/marketing/page-shell';

export const metadata: Metadata = {
  title: 'Changelog · Slabbist',
  description: 'Every release of Slabbist, what shipped, and what is in flight.',
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
    date: '2026-04-18',
    version: '0.9.0',
    title: 'Bulk capture + offer sheets',
    tag: 'beta',
    bullets: [
      'Bulk scan queue with 30 slabs/minute throughput on iPhone 14 and later.',
      'Offer sheets now print or email directly from the lot view.',
      'Signature-on-glass capture for buys closed on iPad.',
    ],
  },
  {
    date: '2026-03-28',
    version: '0.8.2',
    title: 'TAG grading support',
    tag: 'beta',
    bullets: [
      'Added cert OCR and population lookups for TAG-graded slabs.',
      'Confidence scoring now weighs comp volume and spread per grader.',
      'Fixed a sync stall when a queued scan lacked a cert number.',
    ],
  },
  {
    date: '2026-03-10',
    version: '0.8.0',
    title: 'Role-based buy visibility',
    tag: 'beta',
    bullets: [
      'Associates now see only the buy number. Comp, cost, and margin are hidden.',
      'Enforced in Postgres via RLS — the API never returns data your role cannot see.',
      'Audit log for every margin rule change.',
    ],
  },
  {
    date: '2026-02-14',
    version: '0.7.0',
    title: 'Event-aware margin rules',
    tag: 'preview',
    bullets: [
      'Time-boxed modifiers for release weekends and market corrections.',
      'Preview the buy number before you commit a rule change.',
      'Rule history visible on every lot.',
    ],
  },
  {
    date: '2026-01-22',
    version: '0.6.0',
    title: 'Offline-first queue',
    tag: 'preview',
    bullets: [
      'Scans, edits, and offers persist locally and sync on reconnect.',
      'Reduced cold-start capture latency by 34%.',
    ],
  },
  {
    date: '2025-12-08',
    version: '0.5.0',
    title: 'Comp engine v1',
    tag: 'internal',
    bullets: [
      'Rolling median of eBay sold comps with outlier rejection.',
      '7, 30, 90 day velocity per card.',
      'Tap any price to see the sales behind it.',
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
        subtitle="Slabbist is in closed beta with a handful of stores. This is everything that has gone out — the good, the fixed, and the in-flight."
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
