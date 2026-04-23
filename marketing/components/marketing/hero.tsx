'use client';

import { useEffect, useState } from 'react';
import { SLAB } from '@/lib/tokens';
import { Icon } from '@/components/icon';
import { useAuth } from './auth-context';

export function Hero() {
  const [count, setCount] = useState(0);
  const [dollars, setDollars] = useState(0);
  const { openAuth } = useAuth();

  useEffect(() => {
    let raf = 0;
    const start = performance.now();
    const animate = (t: number) => {
      const p = Math.min(1, (t - start) / 1600);
      const eased = 1 - Math.pow(1 - p, 3);
      setCount(Math.floor(eased * 42));
      setDollars(Math.floor(eased * 18430));
      if (p < 1) raf = requestAnimationFrame(animate);
    };
    raf = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(raf);
  }, []);

  return (
    <section
      style={{
        position: 'relative',
        paddingTop: 160,
        paddingBottom: 80,
        overflow: 'hidden',
      }}
    >
      <div
        aria-hidden
        style={{
          position: 'absolute',
          top: 100,
          right: '-10%',
          width: 700,
          height: 700,
          borderRadius: '50%',
          background: `radial-gradient(circle, ${SLAB.gold} 0%, transparent 55%)`,
          opacity: 0.11,
          filter: 'blur(60px)',
          pointerEvents: 'none',
        }}
      />
      <div
        aria-hidden
        style={{
          position: 'absolute',
          top: 300,
          left: '-15%',
          width: 600,
          height: 600,
          borderRadius: '50%',
          background: `radial-gradient(circle, oklch(0.5 0.2 280) 0%, transparent 55%)`,
          opacity: 0.16,
          filter: 'blur(70px)',
          pointerEvents: 'none',
        }}
      />

      <div style={{ maxWidth: 1180, margin: '0 auto', padding: '0 32px', position: 'relative' }}>
        <div
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 10,
            padding: '6px 14px 6px 6px',
            borderRadius: 999,
            background: SLAB.elev,
            border: '1px solid ' + SLAB.hair,
            fontSize: 12,
            color: SLAB.muted,
            marginBottom: 32,
            animation: 'sbmFade 0.8s ease backwards',
          }}
        >
          <span
            style={{
              padding: '3px 8px',
              borderRadius: 999,
              background: `linear-gradient(135deg, ${SLAB.gold}, ${SLAB.goldDim})`,
              color: SLAB.ink,
              fontSize: 10,
              fontWeight: 600,
              letterSpacing: 0.6,
              textTransform: 'uppercase',
            }}
          >
            New
          </span>
          Bulk-scan mode is live on TestFlight
          <Icon name="arrow" size={12} sw={2} color={SLAB.gold} />
        </div>

        <h1
          style={{
            fontFamily: SLAB.serif,
            fontSize: 'clamp(52px, 8vw, 104px)',
            fontWeight: 400,
            letterSpacing: -2.5,
            lineHeight: 0.98,
            margin: 0,
            maxWidth: 920,
          }}
        >
          <span style={{ display: 'block', animation: 'sbmRise 0.8s 0.1s ease backwards' }}>
            The buy counter,
          </span>
          <span style={{ display: 'block', animation: 'sbmRise 0.8s 0.2s ease backwards' }}>
            <span style={{ fontStyle: 'italic', color: SLAB.gold }}>rebuilt</span> around
          </span>
          <span style={{ display: 'block', animation: 'sbmRise 0.8s 0.3s ease backwards' }}>
            the slab in your hand.
          </span>
        </h1>

        <p
          style={{
            fontSize: 20,
            color: SLAB.muted,
            lineHeight: 1.45,
            maxWidth: 560,
            margin: '32px 0 40px',
            letterSpacing: -0.2,
            animation: 'sbmRise 0.8s 0.4s ease backwards',
          }}
        >
          Slabbist is the iOS app Pokémon hobby stores use to bulk-scan graded slabs, pull defensible comps, and close buys in seconds — at the counter or on the show floor.
        </p>

        <div
          style={{
            display: 'flex',
            gap: 12,
            marginBottom: 48,
            flexWrap: 'wrap',
            animation: 'sbmRise 0.8s 0.5s ease backwards',
          }}
        >
          <button
            onClick={() => openAuth('signup')}
            style={{
              padding: '16px 28px',
              borderRadius: 999,
              background: SLAB.text,
              color: SLAB.ink,
              border: 'none',
              fontSize: 15,
              fontWeight: 600,
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              boxShadow: '0 14px 40px rgba(255,255,255,0.08)',
            }}
          >
            Request early access
            <Icon name="arrow" size={15} sw={2.2} />
          </button>
          <button
            style={{
              padding: '16px 28px',
              borderRadius: 999,
              background: SLAB.elev,
              border: '1px solid ' + SLAB.hairStrong,
              color: SLAB.text,
              fontSize: 15,
              fontWeight: 500,
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: 8,
            }}
          >
            <Icon name="store" size={16} />
            For stores & vendors
          </button>
        </div>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: '1fr 420px',
            gap: 60,
            alignItems: 'center',
            marginTop: 40,
          }}
        >
          <div style={{ animation: 'sbmRise 0.9s 0.6s ease backwards' }}>
            <div
              style={{
                fontSize: 11,
                letterSpacing: 2.4,
                textTransform: 'uppercase',
                color: SLAB.dim,
                fontWeight: 500,
                marginBottom: 20,
              }}
            >
              Live on the floor · right now
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 0, maxWidth: 480 }}>
              <div style={{ borderRight: '1px solid ' + SLAB.hair, padding: '10px 24px 10px 0' }}>
                <div
                  style={{
                    fontFamily: SLAB.serif,
                    fontSize: 56,
                    fontWeight: 400,
                    letterSpacing: -1.5,
                    lineHeight: 1,
                  }}
                >
                  {count}
                </div>
                <div style={{ fontSize: 12, color: SLAB.muted, marginTop: 8 }}>
                  Slabs comped in the last 60 seconds
                </div>
              </div>
              <div style={{ padding: '10px 0 10px 24px' }}>
                <div
                  style={{
                    fontFamily: SLAB.serif,
                    fontSize: 56,
                    fontWeight: 400,
                    letterSpacing: -1.5,
                    lineHeight: 1,
                    display: 'flex',
                    alignItems: 'baseline',
                  }}
                >
                  <span style={{ fontSize: 32, opacity: 0.55, marginRight: 2 }}>$</span>
                  {dollars.toLocaleString('en-US')}
                </div>
                <div style={{ fontSize: 12, color: SLAB.muted, marginTop: 8 }}>
                  Offered to sellers today
                </div>
              </div>
            </div>

            <div
              style={{
                marginTop: 48,
                display: 'flex',
                gap: 24,
                alignItems: 'center',
                fontSize: 12,
                color: SLAB.dim,
                flexWrap: 'wrap',
              }}
            >
              <span
                style={{
                  fontSize: 11,
                  letterSpacing: 2,
                  textTransform: 'uppercase',
                  fontWeight: 500,
                }}
              >
                Built for
              </span>
              <span>Card shops</span>
              <span style={{ color: SLAB.hairStrong }}>·</span>
              <span>Show vendors</span>
              <span style={{ color: SLAB.hairStrong }}>·</span>
              <span>Full-time buyers</span>
            </div>
          </div>

          <div style={{ animation: 'sbmRise 1s 0.3s ease backwards', position: 'relative' }}>
            <PhoneHeroMock />
          </div>
        </div>
      </div>
    </section>
  );
}

const TALLY = [184, 642, 1284, 418, 2890];

function PhoneHeroMock() {
  const [n, setN] = useState(0);

  useEffect(() => {
    const t = setInterval(() => setN((x) => (x + 1) % 7), 1400);
    return () => clearInterval(t);
  }, []);

  const shown = Math.min(n, 5);
  const total = TALLY.slice(0, shown).reduce((a, b) => a + b, 0);

  return (
    <div
      style={{
        width: 320,
        height: 640,
        margin: '0 auto',
        borderRadius: 48,
        position: 'relative',
        background: '#000',
        padding: 10,
        boxShadow:
          '0 60px 140px rgba(0,0,0,0.65), 0 0 0 1px #111, 0 0 0 6px #1a1a1d, 0 0 0 7px #2a2a2e',
        transform: 'perspective(1800px) rotateY(-10deg) rotateX(4deg)',
      }}
    >
      <div
        style={{
          width: '100%',
          height: '100%',
          borderRadius: 40,
          overflow: 'hidden',
          background: 'radial-gradient(ellipse at 50% 30%, #1a1a1f, #050505)',
          position: 'relative',
          fontFamily: SLAB.sans,
          color: SLAB.text,
        }}
      >
        <div
          style={{
            position: 'absolute',
            top: 9,
            left: '50%',
            transform: 'translateX(-50%)',
            width: 96,
            height: 28,
            borderRadius: 20,
            background: '#000',
            zIndex: 50,
          }}
        />

        <div
          style={{
            position: 'absolute',
            top: 60,
            left: 0,
            right: 0,
            display: 'flex',
            justifyContent: 'center',
          }}
        >
          <div style={{ position: 'relative', width: 180, height: 250 }}>
            {(
              [
                [0, 0, 0],
                [1, 0, 90],
                [1, 1, 180],
                [0, 1, 270],
              ] as const
            ).map(([px, py, r], j) => (
              <svg
                key={j}
                width="30"
                height="30"
                style={{
                  position: 'absolute',
                  left: px ? 'calc(100% - 30px)' : 0,
                  top: py ? 'calc(100% - 30px)' : 0,
                  transform: `rotate(${r}deg)`,
                }}
                aria-hidden
              >
                <path
                  d="M2 2 L2 14 M2 2 L14 2"
                  stroke={SLAB.gold}
                  strokeWidth="2.5"
                  strokeLinecap="round"
                  fill="none"
                />
              </svg>
            ))}
            <div
              style={{
                position: 'absolute',
                left: 8,
                right: 8,
                height: 2,
                background: `linear-gradient(90deg, transparent, ${SLAB.gold}, transparent)`,
                animation: 'sbmScanLine 2s linear infinite',
                boxShadow: `0 0 14px ${SLAB.gold}`,
              }}
            />
            <div
              style={{
                position: 'absolute',
                inset: 16,
                borderRadius: 8,
                background:
                  'linear-gradient(145deg, oklch(0.36 0.14 12), oklch(0.14 0.06 12))',
                opacity: 0.55,
                border: '1px solid oklch(0.5 0.09 12 / 0.5)',
              }}
            >
              <div
                style={{
                  margin: '16px 10px',
                  height: 66,
                  borderRadius: 4,
                  background:
                    'radial-gradient(ellipse at 30% 30%, oklch(0.7 0.14 12), oklch(0.15 0.05 12))',
                }}
              />
            </div>
          </div>
        </div>

        <div
          style={{
            position: 'absolute',
            bottom: 30,
            left: 12,
            right: 12,
            borderRadius: 20,
            padding: 14,
            background: 'rgba(14,14,18,0.78)',
            backdropFilter: 'blur(20px)',
            WebkitBackdropFilter: 'blur(20px)',
            border: '1px solid ' + SLAB.hairStrong,
          }}
        >
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'baseline',
              marginBottom: 10,
            }}
          >
            <div>
              <div
                style={{
                  fontSize: 9,
                  letterSpacing: 1.8,
                  textTransform: 'uppercase',
                  color: SLAB.dim,
                  fontWeight: 500,
                }}
              >
                Lot total
              </div>
              <div
                style={{
                  fontFamily: SLAB.serif,
                  fontSize: 30,
                  letterSpacing: -0.8,
                  lineHeight: 1,
                  marginTop: 4,
                  transition: 'color 0.3s',
                  color: shown > 0 ? SLAB.gold : SLAB.text,
                }}
              >
                ${total.toLocaleString('en-US')}
              </div>
            </div>
            <div
              style={{
                fontFamily: SLAB.mono,
                fontSize: 22,
                color: SLAB.gold,
                fontWeight: 500,
              }}
            >
              {shown.toString().padStart(2, '0')}
            </div>
          </div>
          <div style={{ display: 'flex', gap: 4 }}>
            {Array.from({ length: 6 }).map((_, i) => (
              <div
                key={i}
                style={{
                  flex: 1,
                  height: 42,
                  borderRadius: 4,
                  background:
                    i < shown
                      ? `linear-gradient(145deg, oklch(0.36 0.12 ${i * 47}), oklch(0.16 0.08 ${i * 47}))`
                      : 'transparent',
                  border:
                    '1px ' +
                    (i < shown ? 'solid ' + SLAB.hairStrong : 'dashed ' + SLAB.hair),
                  animation: i === shown - 1 ? 'sbmPop 0.4s ease' : 'none',
                }}
              />
            ))}
          </div>
        </div>

        <div
          style={{
            position: 'absolute',
            top: 54,
            left: '50%',
            transform: 'translateX(-50%)',
            padding: '5px 10px',
            borderRadius: 10,
            background: 'rgba(14,14,18,0.78)',
            backdropFilter: 'blur(20px)',
            WebkitBackdropFilter: 'blur(20px)',
            border: '1px solid ' + SLAB.hair,
            fontSize: 9,
            color: SLAB.muted,
            letterSpacing: 1,
            textTransform: 'uppercase',
            fontWeight: 500,
            display: 'flex',
            alignItems: 'center',
            gap: 6,
          }}
        >
          <span
            style={{
              width: 5,
              height: 5,
              borderRadius: 3,
              background: SLAB.pos,
              boxShadow: `0 0 8px ${SLAB.pos}`,
            }}
          />
          Bulk scan · Auto capture
        </div>
      </div>
    </div>
  );
}
