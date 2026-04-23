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
        padding: 'clamp(84px, 11vw, 120px) 0',
        position: 'relative',
        borderTop: '1px solid ' + SLAB.hair,
      }}
    >
      <div style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'end',
            marginBottom: 'clamp(48px, 6vw, 72px)',
            gap: 40,
            flexWrap: 'wrap',
          }}
        >
          <div>
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
              From stack to signature in five moves.
            </h2>
          </div>
          <div
            style={{
              fontSize: 14,
              color: SLAB.muted,
              maxWidth: 320,
              marginBottom: 16,
              lineHeight: 1.5,
            }}
          >
            Built on the counter, not in a spreadsheet. Every step came from watching a real buy go wrong.
          </div>
        </div>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
            gap: 1,
            background: SLAB.hair,
            border: '1px solid ' + SLAB.hair,
          }}
        >
          {STEPS.map((s, i) => (
            <div
              key={s.n}
              style={{
                padding: '32px 26px 40px',
                position: 'relative',
                background: SLAB.ink,
                animation: visible ? `sbmRise 0.7s ${i * 0.08}s ease backwards` : 'none',
                opacity: visible ? 1 : 0,
              }}
            >
              <div
                style={{
                  fontFamily: SLAB.mono,
                  fontSize: 12,
                  color: SLAB.gold,
                  letterSpacing: 1.2,
                  marginBottom: 20,
                  fontWeight: 500,
                }}
              >
                {s.n}
              </div>
              <div
                style={{
                  fontFamily: SLAB.serif,
                  fontSize: 23,
                  letterSpacing: -0.5,
                  marginBottom: 14,
                  lineHeight: 1.2,
                }}
              >
                {s.t}
              </div>
              <div style={{ fontSize: 14, color: SLAB.muted, lineHeight: 1.55 }}>{s.b}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
