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
