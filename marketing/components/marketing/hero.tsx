'use client';

import { SLAB } from '@/lib/tokens';
import { Icon } from '@/components/icon';
import { useAuth } from './auth-context';

const STATS = [
  { k: '30 slabs', v: 'a minute' },
  { k: '14 sec', v: 'scan to offer' },
  { k: '5 graders', v: 'PSA, BGS, CGC, SGC, TAG' },
];

export function Hero() {
  const { openAuth } = useAuth();

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
            Beta
          </span>
          Live on TestFlight now
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
            Price a stack of slabs
          </span>
          <span style={{ display: 'block', animation: 'sbmRise 0.8s 0.2s ease backwards' }}>
            <span style={{ fontStyle: 'italic', color: SLAB.gold }}>faster</span> than you can
          </span>
          <span style={{ display: 'block', animation: 'sbmRise 0.8s 0.3s ease backwards' }}>
            count them.
          </span>
        </h1>

        <p
          style={{
            fontSize: 20,
            color: SLAB.muted,
            lineHeight: 1.5,
            maxWidth: 560,
            margin: '32px 0 40px',
            letterSpacing: -0.2,
            animation: 'sbmRise 0.8s 0.4s ease backwards',
          }}
        >
          Slabbist turns your iPhone into a bulk scanner for graded Pokémon. Real comps from recent sales. Offer sheets in a tap. Works at your counter and on the show floor.
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
            Get TestFlight access
            <Icon name="arrow" size={15} sw={2.2} />
          </button>
          <a
            href="#how-it-works"
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
              textDecoration: 'none',
            }}
          >
            See how it works
          </a>
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
                marginBottom: 24,
              }}
            >
              What you get
            </div>

            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(3, 1fr)',
                gap: 0,
                maxWidth: 560,
              }}
            >
              {STATS.map((s, i) => (
                <div
                  key={s.k}
                  style={{
                    padding: i === 0 ? '6px 22px 6px 0' : '6px 22px',
                    borderLeft: i > 0 ? '1px solid ' + SLAB.hair : 'none',
                  }}
                >
                  <div
                    style={{
                      fontFamily: SLAB.serif,
                      fontSize: 42,
                      fontWeight: 400,
                      letterSpacing: -1.2,
                      lineHeight: 1,
                    }}
                  >
                    {s.k}
                  </div>
                  <div style={{ fontSize: 12, color: SLAB.muted, marginTop: 10, lineHeight: 1.4 }}>
                    {s.v}
                  </div>
                </div>
              ))}
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
  // Kept as a static composition (no animated tally) so the hero doesn't
  // look like it's reporting fake live activity.
  const shown = 4;
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
                  color: SLAB.gold,
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
