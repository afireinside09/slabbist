'use client';

import { useEffect, useRef, useState } from 'react';
import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';

type Feat = { icon: IconName; title: string; blurb: string };

const FEATS: Feat[] = [
  {
    icon: 'scan',
    title: 'Cert OCR, all five graders',
    blurb:
      'PSA, BGS, CGC, SGC, TAG. Auto-detects the grader, reads the cert, falls back to a manual entry in one tap.',
  },
  {
    icon: 'layers',
    title: 'Bulk scan, continuous capture',
    blurb:
      'Rapid-fire 30 slabs in a minute. Queue runs offline. Results drop in live as comps resolve.',
  },
  {
    icon: 'chart',
    title: 'Defensible comps',
    blurb:
      'Blended median over recent eBay solds, with a confidence meter and 7/30/90-day velocity so you can explain every number.',
  },
  {
    icon: 'shield',
    title: 'Margin rules, per role',
    blurb:
      'Owners see cost and margin. Associates see buy price only. Enforced in the database, not just the UI.',
  },
];

export function FeatureRow() {
  const [active, setActive] = useState(0);
  const ref = useRef<HTMLElement | null>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (!ref.current) return;
    const obs = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting) setVisible(true);
      },
      { threshold: 0.2 },
    );
    obs.observe(ref.current);
    return () => obs.disconnect();
  }, []);

  useEffect(() => {
    if (!visible) return;
    const t = setInterval(() => setActive((a) => (a + 1) % FEATS.length), 4200);
    return () => clearInterval(t);
  }, [visible]);

  return (
    <section id="product" ref={ref} style={{ padding: '160px 0', position: 'relative' }}>
      <div style={{ maxWidth: 1180, margin: '0 auto', padding: '0 32px' }}>
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: '1fr 1fr',
            gap: 80,
            alignItems: 'center',
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
              The counter, rebuilt
            </div>
            <h2
              style={{
                fontFamily: SLAB.serif,
                fontSize: 'clamp(40px, 5vw, 64px)',
                fontWeight: 400,
                letterSpacing: -1.5,
                lineHeight: 1.05,
                margin: '0 0 60px',
                maxWidth: 520,
              }}
            >
              Every scan earns its price.
            </h2>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {FEATS.map((f, i) => (
                <button
                  key={f.title}
                  onClick={() => setActive(i)}
                  style={{
                    display: 'grid',
                    gridTemplateColumns: '44px 1fr',
                    gap: 18,
                    padding: '22px 24px',
                    borderRadius: 16,
                    textAlign: 'left',
                    background: active === i ? SLAB.elev : 'transparent',
                    border: '1px solid ' + (active === i ? SLAB.hairStrong : 'transparent'),
                    color: SLAB.text,
                    cursor: 'pointer',
                    transition: 'all 0.3s',
                    position: 'relative',
                    overflow: 'hidden',
                  }}
                >
                  {active === i && (
                    <div
                      style={{
                        position: 'absolute',
                        left: 0,
                        top: 24,
                        bottom: 24,
                        width: 2,
                        background: SLAB.gold,
                        borderRadius: 2,
                      }}
                    />
                  )}
                  <div
                    style={{
                      width: 44,
                      height: 44,
                      borderRadius: 12,
                      background:
                        active === i
                          ? `linear-gradient(135deg, ${SLAB.gold}, ${SLAB.goldDim})`
                          : SLAB.elev2,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      color: active === i ? SLAB.ink : SLAB.muted,
                      transition: 'all 0.3s',
                    }}
                  >
                    <Icon name={f.icon} size={20} sw={1.8} />
                  </div>
                  <div>
                    <div
                      style={{
                        fontSize: 17,
                        fontWeight: 500,
                        letterSpacing: -0.3,
                        marginBottom: 6,
                      }}
                    >
                      {f.title}
                    </div>
                    <div
                      style={{
                        fontSize: 14,
                        color: SLAB.muted,
                        lineHeight: 1.5,
                        maxHeight: active === i ? 100 : 0,
                        opacity: active === i ? 1 : 0,
                        overflow: 'hidden',
                        transition: 'all 0.35s ease',
                      }}
                    >
                      {f.blurb}
                    </div>
                  </div>
                </button>
              ))}
            </div>
          </div>

          <div style={{ position: 'sticky', top: 100 }}>
            <FeatureMock step={active} />
          </div>
        </div>
      </div>
    </section>
  );
}

function FeatureMock({ step }: { step: number }) {
  return (
    <div
      style={{
        aspectRatio: '4/5',
        borderRadius: 28,
        background: `linear-gradient(145deg, ${SLAB.elev}, ${SLAB.surface})`,
        border: '1px solid ' + SLAB.hair,
        padding: 28,
        position: 'relative',
        overflow: 'hidden',
        boxShadow: '0 40px 100px rgba(0,0,0,0.4)',
      }}
    >
      <div
        aria-hidden
        style={{
          position: 'absolute',
          top: -100,
          right: -100,
          width: 300,
          height: 300,
          borderRadius: '50%',
          background: `radial-gradient(circle, ${SLAB.gold}, transparent 60%)`,
          opacity: 0.07,
          filter: 'blur(40px)',
        }}
      />

      <div
        style={{
          position: 'absolute',
          inset: 28,
          display: 'flex',
          flexDirection: 'column',
        }}
      >
        {step === 0 && <CertOcrPanel />}
        {step === 1 && <BulkQueuePanel />}
        {step === 2 && <CompPanel />}
        {step === 3 && <MarginRulesPanel />}
      </div>
    </div>
  );
}

function CertOcrPanel() {
  const grades = [
    { g: 'PSA', v: '87234091', conf: 0.98 },
    { g: 'BGS', v: '0012984571', conf: 0.94 },
    { g: 'CGC', v: '4821075003', conf: 0.92 },
  ];
  return (
    <div style={{ animation: 'sbmFade 0.5s' }}>
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
        Cert OCR · live pass
      </div>

      <div
        style={{
          position: 'relative',
          aspectRatio: '5/4',
          borderRadius: 14,
          overflow: 'hidden',
          background: 'linear-gradient(145deg, oklch(0.26 0.08 250), oklch(0.12 0.04 250))',
          border: '1px solid ' + SLAB.hair,
          marginBottom: 20,
        }}
      >
        <div
          style={{
            position: 'absolute',
            top: '20%',
            left: '15%',
            right: '15%',
            padding: '6px 8px',
            background: 'rgba(0,0,0,0.65)',
            borderRadius: 4,
            fontFamily: SLAB.mono,
            fontSize: 10,
            color: '#fff',
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            gap: 8,
            border: '1px dashed ' + SLAB.gold,
            whiteSpace: 'nowrap',
          }}
        >
          <span>PSA</span>
          <span>GEM&nbsp;MT&nbsp;10</span>
        </div>
        <div
          style={{
            position: 'absolute',
            bottom: '15%',
            left: '25%',
            right: '25%',
            padding: 6,
            background: 'rgba(0,0,0,0.65)',
            borderRadius: 4,
            fontFamily: SLAB.mono,
            fontSize: 10,
            color: '#fff',
            textAlign: 'center',
            border: '1px dashed ' + SLAB.gold,
            letterSpacing: 1.5,
          }}
        >
          87234091
        </div>
        <div
          style={{
            position: 'absolute',
            left: 0,
            right: 0,
            height: 2,
            background: `linear-gradient(90deg, transparent, ${SLAB.gold}, transparent)`,
            boxShadow: `0 0 10px ${SLAB.gold}`,
            animation: 'sbmScanLine 2.2s ease-in-out infinite',
          }}
        />
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {grades.map((gr, i) => (
          <div
            key={gr.g}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 12,
              padding: '10px 14px',
              background: i === 0 ? SLAB.elev2 : 'transparent',
              border: '1px solid ' + (i === 0 ? SLAB.hairStrong : SLAB.hair),
              borderRadius: 10,
            }}
          >
            <span
              style={{
                fontFamily: SLAB.mono,
                fontSize: 11,
                fontWeight: 600,
                padding: '3px 7px',
                borderRadius: 4,
                background: SLAB.gold,
                color: SLAB.ink,
              }}
            >
              {gr.g}
            </span>
            <span style={{ fontFamily: SLAB.mono, fontSize: 13, flex: 1, letterSpacing: 1 }}>
              {gr.v}
            </span>
            <span style={{ fontSize: 11, color: SLAB.muted, fontFamily: SLAB.mono }}>
              {(gr.conf * 100).toFixed(0)}%
            </span>
            {i === 0 && <Icon name="check" size={14} color={SLAB.pos} sw={2.5} />}
          </div>
        ))}
      </div>
    </div>
  );
}

function BulkQueuePanel() {
  const [n, setN] = useState(0);

  useEffect(() => {
    const t = setInterval(() => setN((x) => (x < 12 ? x + 1 : 12)), 160);
    return () => clearInterval(t);
  }, []);

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
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'baseline',
          marginBottom: 20,
        }}
      >
        <div
          style={{
            fontSize: 11,
            letterSpacing: 2,
            textTransform: 'uppercase',
            color: SLAB.dim,
            fontWeight: 500,
          }}
        >
          Lot #2841 · capturing
        </div>
        <div style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.gold }}>
          {n.toString().padStart(2, '0')}/30
        </div>
      </div>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(5, 1fr)',
          gap: 6,
          flex: 1,
          alignContent: 'start',
        }}
      >
        {Array.from({ length: 15 }).map((_, i) => {
          const state = i < n ? (i % 4 === 3 ? 'pending' : 'ready') : 'empty';
          return (
            <div
              key={i}
              style={{
                aspectRatio: '5/7',
                borderRadius: 6,
                background:
                  state === 'ready'
                    ? `linear-gradient(145deg, oklch(0.36 0.1 ${i * 32}), oklch(0.14 0.04 ${i * 32}))`
                    : state === 'pending'
                      ? SLAB.elev2
                      : 'transparent',
                border:
                  '1px ' +
                  (state === 'empty' ? 'dashed ' + SLAB.hair : 'solid ' + SLAB.hairStrong),
                position: 'relative',
                animation: i === n - 1 ? 'sbmPop 0.35s ease' : 'none',
              }}
            >
              {state === 'pending' && (
                <div
                  style={{
                    position: 'absolute',
                    inset: 0,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontSize: 8,
                    color: SLAB.gold,
                    letterSpacing: 1,
                    textTransform: 'uppercase',
                    fontWeight: 600,
                  }}
                >
                  …
                </div>
              )}
              {state === 'ready' && (
                <div
                  style={{
                    position: 'absolute',
                    bottom: 4,
                    left: 4,
                    right: 4,
                    height: 14,
                    borderRadius: 2,
                    background: 'rgba(0,0,0,0.5)',
                    fontSize: 7,
                    color: '#fff',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontFamily: SLAB.mono,
                  }}
                >
                  ${30 + i * 17}
                </div>
              )}
            </div>
          );
        })}
      </div>

      <div
        style={{
          marginTop: 16,
          padding: 14,
          borderRadius: 12,
          background: SLAB.elev2,
          border: '1px solid ' + SLAB.hair,
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
        }}
      >
        <div>
          <div
            style={{
              fontSize: 10,
              color: SLAB.dim,
              letterSpacing: 1.5,
              textTransform: 'uppercase',
              fontWeight: 500,
            }}
          >
            Running total
          </div>
          <div
            style={{
              fontFamily: SLAB.serif,
              fontSize: 22,
              letterSpacing: -0.5,
              marginTop: 2,
            }}
          >
            $4,{(n * 80).toString().padStart(3, '0')}
          </div>
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
          <span
            style={{
              fontSize: 10,
              padding: '4px 8px',
              borderRadius: 999,
              background: 'transparent',
              border: '1px solid ' + SLAB.hair,
              color: SLAB.muted,
            }}
          >
            {n} ready
          </span>
          <span
            style={{
              fontSize: 10,
              padding: '4px 8px',
              borderRadius: 999,
              background: SLAB.gold + '22',
              border: '1px solid ' + SLAB.gold + '55',
              color: SLAB.gold,
            }}
          >
            {Math.floor(n / 4)} pending
          </span>
        </div>
      </div>
    </div>
  );
}

function CompPanel() {
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
        Comp · PSA 10 · 12 comps
      </div>

      <div style={{ marginBottom: 18 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, marginBottom: 6 }}>
          <div
            style={{
              fontFamily: SLAB.serif,
              fontSize: 56,
              letterSpacing: -1.5,
              lineHeight: 1,
            }}
          >
            $842
          </div>
          <div
            style={{
              fontSize: 13,
              color: SLAB.pos,
              fontFamily: SLAB.mono,
              display: 'flex',
              alignItems: 'center',
              gap: 4,
            }}
          >
            ▲ 12.4%
          </div>
        </div>
        <div style={{ fontSize: 12, color: SLAB.muted }}>Blended median · 30-day window</div>
      </div>

      <div style={{ marginBottom: 18 }}>
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            fontSize: 10,
            letterSpacing: 1,
            textTransform: 'uppercase',
            color: SLAB.dim,
            marginBottom: 6,
            fontWeight: 500,
          }}
        >
          <span>Confidence</span>
          <span>High · 92%</span>
        </div>
        <div
          style={{
            height: 6,
            borderRadius: 3,
            background: SLAB.elev2,
            overflow: 'hidden',
            position: 'relative',
          }}
        >
          <div
            style={{
              position: 'absolute',
              inset: 0,
              width: '92%',
              background: `linear-gradient(90deg, ${SLAB.goldDim}, ${SLAB.gold})`,
              borderRadius: 3,
            }}
          />
        </div>
      </div>

      <div style={{ marginBottom: 20 }}>
        <svg viewBox="0 0 300 80" style={{ width: '100%', height: 80 }} aria-hidden>
          <defs>
            <linearGradient id="sparkFill" x1="0" x2="0" y1="0" y2="1">
              <stop offset="0" stopColor={SLAB.gold} stopOpacity="0.3" />
              <stop offset="1" stopColor={SLAB.gold} stopOpacity="0" />
            </linearGradient>
          </defs>
          <path
            d="M0,60 L30,55 L60,62 L90,48 L120,50 L150,40 L180,35 L210,42 L240,28 L270,22 L300,18 L300,80 L0,80 Z"
            fill="url(#sparkFill)"
          />
          <path
            d="M0,60 L30,55 L60,62 L90,48 L120,50 L150,40 L180,35 L210,42 L240,28 L270,22 L300,18"
            stroke={SLAB.gold}
            strokeWidth="2"
            fill="none"
            strokeLinecap="round"
          />
          <circle cx="300" cy="18" r="3.5" fill={SLAB.gold} />
          <circle cx="300" cy="18" r="8" fill={SLAB.gold} opacity="0.3">
            <animate attributeName="r" values="4;12;4" dur="2s" repeatCount="indefinite" />
            <animate attributeName="opacity" values="0.4;0;0.4" dur="2s" repeatCount="indefinite" />
          </circle>
        </svg>
      </div>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(3, 1fr)',
          gap: 8,
          marginBottom: 16,
        }}
      >
        {(
          [
            ['7d', '4', 'sold'],
            ['30d', '12', 'sold'],
            ['90d', '34', 'sold'],
          ] as const
        ).map(([p, v, l]) => (
          <div
            key={p}
            style={{
              padding: 12,
              borderRadius: 10,
              background: SLAB.elev2,
              border: '1px solid ' + SLAB.hair,
            }}
          >
            <div
              style={{
                fontSize: 10,
                color: SLAB.dim,
                letterSpacing: 1,
                textTransform: 'uppercase',
                fontWeight: 500,
              }}
            >
              {p}
            </div>
            <div
              style={{
                fontFamily: SLAB.mono,
                fontSize: 18,
                fontWeight: 500,
                marginTop: 4,
              }}
            >
              {v}
              <span style={{ fontSize: 10, color: SLAB.muted, marginLeft: 4 }}>{l}</span>
            </div>
          </div>
        ))}
      </div>

      <div
        style={{
          padding: 12,
          borderRadius: 10,
          background: SLAB.elev2,
          border: '1px solid ' + SLAB.hair,
          display: 'flex',
          alignItems: 'center',
          gap: 10,
          fontSize: 12,
          color: SLAB.muted,
        }}
      >
        <Icon name="shield" size={14} color={SLAB.gold} />
        Sourced from 12 recent eBay sold listings
      </div>
    </div>
  );
}

function MarginRulesPanel() {
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
        Margin rules · active
      </div>

      <div
        style={{
          marginBottom: 20,
          padding: 16,
          borderRadius: 14,
          background: 'linear-gradient(145deg, oklch(0.22 0.06 78), oklch(0.14 0.03 78))',
          border: '1px solid ' + SLAB.gold + '44',
        }}
      >
        <div
          style={{
            fontSize: 11,
            letterSpacing: 1.5,
            textTransform: 'uppercase',
            color: SLAB.gold,
            marginBottom: 6,
            fontWeight: 600,
          }}
        >
          Event mode · active
        </div>
        <div style={{ fontSize: 13, color: SLAB.text, marginBottom: 8 }}>
          Prismatic Evolutions release weekend
        </div>
        <div style={{ fontSize: 11, color: SLAB.muted }}>
          Modern vintage modifier −5% until Monday 9am
        </div>
      </div>

      <div
        style={{
          fontSize: 11,
          letterSpacing: 1.5,
          textTransform: 'uppercase',
          color: SLAB.dim,
          marginBottom: 12,
          fontWeight: 500,
        }}
      >
        What each role sees
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
        <div
          style={{
            padding: 14,
            borderRadius: 12,
            background: SLAB.elev2,
            border: '1px solid ' + SLAB.hair,
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 10 }}>
            <div
              style={{
                width: 20,
                height: 20,
                borderRadius: 4,
                background: SLAB.gold,
                color: SLAB.ink,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 10,
                fontWeight: 700,
              }}
            >
              O
            </div>
            <span
              style={{
                fontSize: 11,
                letterSpacing: 1,
                textTransform: 'uppercase',
                fontWeight: 600,
              }}
            >
              Owner
            </span>
          </div>
          <div style={{ fontFamily: SLAB.mono, fontSize: 10, color: SLAB.muted, lineHeight: 1.6 }}>
            <div>
              comp: <span style={{ color: SLAB.text }}>$842</span>
            </div>
            <div>
              cost: <span style={{ color: SLAB.text }}>$506</span>
            </div>
            <div>
              marg: <span style={{ color: SLAB.pos }}>40%</span>
            </div>
            <div>
              buy: <span style={{ color: SLAB.text }}>$506</span>
            </div>
          </div>
        </div>
        <div
          style={{
            padding: 14,
            borderRadius: 12,
            background: SLAB.elev2,
            border: '1px solid ' + SLAB.hair,
            opacity: 0.75,
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 10 }}>
            <div
              style={{
                width: 20,
                height: 20,
                borderRadius: 4,
                background: SLAB.elev,
                color: SLAB.muted,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 10,
                fontWeight: 700,
                border: '1px solid ' + SLAB.hair,
              }}
            >
              A
            </div>
            <span
              style={{
                fontSize: 11,
                letterSpacing: 1,
                textTransform: 'uppercase',
                fontWeight: 600,
              }}
            >
              Associate
            </span>
          </div>
          <div style={{ fontFamily: SLAB.mono, fontSize: 10, color: SLAB.muted, lineHeight: 1.6 }}>
            <div>
              comp: <span style={{ color: SLAB.dim }}>— —</span>
            </div>
            <div>
              cost: <span style={{ color: SLAB.dim }}>— —</span>
            </div>
            <div>
              marg: <span style={{ color: SLAB.dim }}>— —</span>
            </div>
            <div>
              buy: <span style={{ color: SLAB.text }}>$506</span>
            </div>
          </div>
        </div>
      </div>

      <div
        style={{
          marginTop: 'auto',
          paddingTop: 14,
          fontSize: 11,
          color: SLAB.dim,
          display: 'flex',
          alignItems: 'center',
          gap: 6,
        }}
      >
        <Icon name="lock" size={12} />
        Enforced at the database — not just the UI.
      </div>
    </div>
  );
}
