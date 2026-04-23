'use client';

import { useEffect, useRef, useState } from 'react';
import { SLAB } from '@/lib/tokens';

const STEPS = [
  { n: '01', t: 'Walk-in arrives', b: 'A seller drops thirty slabs on the counter. You look at the cards, not the calculator.' },
  { n: '02', t: 'Sweep the stack', b: 'Scan each slab in hand, or set the phone on a stand and feed them through. The cert reads as the frame locks.' },
  { n: '03', t: 'Queue runs quiet', b: 'Comps resolve in the background while you keep scanning. Slow ones show a small pending mark. No spinner, no blocking.' },
  { n: '04', t: 'Review the lot', b: 'Ready, pending, and issues grouped on one screen. Tap any comp to open the actual eBay solds behind it.' },
  { n: '05', t: 'Offer sheet', b: 'Apply your margin rule, attach a vendor, and print or email the sheet. Capture a signature on an iPad if the buy needs one.' },
];

const METRICS = [
  ['30', 'Slabs scanned per minute, hands-on'],
  ['5', 'Graders read (PSA, BGS, CGC, SGC, TAG)'],
  ['0', 'Subscription fees'],
  ['1%', 'Marketplace premium, when it opens'],
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
            Built on the counter, not in a spreadsheet. Every step came from watching a real buy go wrong.
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
