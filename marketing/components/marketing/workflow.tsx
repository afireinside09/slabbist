'use client';

import { useEffect, useRef, useState } from 'react';
import { SLAB } from '@/lib/tokens';

const STEPS = [
  { n: '01', t: 'Stack arrives', b: "Walk-in brings 30 slabs. You don't look at the price. You look at them." },
  { n: '02', t: 'Sweep the stack', b: 'One-by-one in-hand, or continuous on a stand. Cert OCR locks as each slab clears the frame.' },
  { n: '03', t: 'Queue runs silent', b: 'Comps resolve in the background. Pending slabs show a badge. No waiting on a spinner.' },
  { n: '04', t: 'Review the lot', b: "Ready, Pending, Issues — grouped. Any comp you don't trust opens into the sold listings behind it." },
  { n: '05', t: 'Offer sheet', b: 'Apply your margin rule, attach the vendor, print or email the sheet. Signature on an iPad if you need it.' },
];

const METRICS = [
  ['17×', 'Faster per lot vs. manual lookup'],
  ['$0.82', 'Avg cost of a bad comp (they shrink it)'],
  ['14 sec', 'Median scan → confident comp'],
  ['99.2%', 'Cert OCR accuracy across 5 graders'],
] as const;

export function Workflow() {
  const ref = useRef<HTMLElement | null>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (!ref.current) return;
    const obs = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting) setVisible(true);
      },
      { threshold: 0.15 },
    );
    obs.observe(ref.current);
    return () => obs.disconnect();
  }, []);

  return (
    <section
      id="how-it-works"
      ref={ref}
      style={{
        padding: '140px 0',
        position: 'relative',
        borderTop: '1px solid ' + SLAB.hair,
      }}
    >
      <div style={{ maxWidth: 1180, margin: '0 auto', padding: '0 32px' }}>
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'end',
            marginBottom: 80,
            gap: 40,
            flexWrap: 'wrap',
          }}
        >
          <div>
            <div
              style={{
                fontSize: 11,
                letterSpacing: 2.4,
                textTransform: 'uppercase',
                color: SLAB.gold,
                marginBottom: 20,
                fontWeight: 500,
              }}
            >
              Counter flow
            </div>
            <h2
              style={{
                fontFamily: SLAB.serif,
                fontSize: 'clamp(40px, 5vw, 64px)',
                fontWeight: 400,
                letterSpacing: -1.5,
                lineHeight: 1.05,
                margin: 0,
                maxWidth: 600,
              }}
            >
              From stack to signature{' '}
              <span style={{ fontStyle: 'italic', color: SLAB.gold }}>in five moves.</span>
            </h2>
          </div>
          <div
            style={{
              fontSize: 13,
              color: SLAB.muted,
              maxWidth: 280,
              marginBottom: 16,
            }}
          >
            Designed with owners at three stores in Portland, San Diego and the Tampa show floor.
          </div>
        </div>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(5, 1fr)',
            gap: 2,
            borderTop: '1px solid ' + SLAB.hair,
            borderBottom: '1px solid ' + SLAB.hair,
          }}
        >
          {STEPS.map((s, i) => (
            <div
              key={s.n}
              style={{
                padding: '40px 28px 48px',
                position: 'relative',
                borderRight: i < 4 ? '1px solid ' + SLAB.hair : 'none',
                animation: visible ? `sbmRise 0.7s ${i * 0.08}s ease backwards` : 'none',
                opacity: visible ? 1 : 0,
              }}
            >
              <div
                style={{
                  fontFamily: SLAB.mono,
                  fontSize: 11,
                  color: SLAB.gold,
                  letterSpacing: 1.5,
                  marginBottom: 24,
                  fontWeight: 500,
                }}
              >
                {s.n}
              </div>
              <div
                style={{
                  fontFamily: SLAB.serif,
                  fontSize: 24,
                  letterSpacing: -0.5,
                  marginBottom: 16,
                  lineHeight: 1.2,
                }}
              >
                {s.t}
              </div>
              <div style={{ fontSize: 13, color: SLAB.muted, lineHeight: 1.55 }}>{s.b}</div>
            </div>
          ))}
        </div>

        <div
          style={{
            marginTop: 60,
            display: 'grid',
            gridTemplateColumns: 'repeat(4, 1fr)',
            gap: 1,
            background: SLAB.hair,
            border: '1px solid ' + SLAB.hair,
            borderRadius: 20,
            overflow: 'hidden',
          }}
        >
          {METRICS.map(([v, l]) => (
            <div key={l} style={{ padding: '36px 28px', background: SLAB.surface }}>
              <div
                style={{
                  fontFamily: SLAB.serif,
                  fontSize: 44,
                  letterSpacing: -1,
                  lineHeight: 1,
                  color: SLAB.gold,
                  marginBottom: 12,
                }}
              >
                {v}
              </div>
              <div
                style={{
                  fontSize: 12,
                  color: SLAB.muted,
                  maxWidth: 200,
                  lineHeight: 1.5,
                }}
              >
                {l}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
