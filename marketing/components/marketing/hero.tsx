'use client';

import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';
import { useAuth } from './auth-context';

type Capability = { icon: IconName; title: string; body: string };

const CAPABILITIES: Capability[] = [
  {
    icon: 'scan',
    title: 'Slabs and raw, in one pass',
    body: 'Cert OCR reads PSA, BGS, CGC, SGC, and TAG labels. For raw cards, pick the set and number and the app matches the rest. Shoot them one at a time, or stack a pile in frame.',
  },
  {
    icon: 'chart',
    title: 'Comps from real sales',
    body: 'Graded prices are medians of recent eBay sold listings. Raw prices come from TCGplayer. Every number links back to the sales behind it, with a confidence score and 7, 30, and 90 day velocity.',
  },
  {
    icon: 'shield',
    title: 'Runs anywhere you buy',
    body: 'Use it at the shop counter, the show booth, or on the road. The queue keeps working when venue Wi-Fi drops, and comps fill in when it returns. Buy prices stay locked to owners and hidden from associates.',
  },
];

export function Hero() {
  const { openAuth } = useAuth();

  return (
    <section
      className="slab-hero-section"
      style={{
        position: 'relative',
        paddingTop: 'clamp(120px, 14vw, 148px)',
        paddingBottom: 'clamp(56px, 8vw, 80px)',
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
          opacity: 0.09,
          filter: 'blur(60px)',
          pointerEvents: 'none',
        }}
      />

      <div className="slab-container" style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px', position: 'relative' }}>
        <div
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 10,
            padding: '6px 14px 6px 6px',
            borderRadius: 999,
            background: SLAB.elev,
            border: '1px solid ' + SLAB.hair,
            fontSize: 13,
            color: SLAB.muted,
            marginBottom: 28,
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
            Early
          </span>
          Waitlist is open — iOS launch imminent
          <Icon name="arrow" size={12} sw={2} color={SLAB.gold} />
        </div>

        <h1
          style={{
            fontFamily: SLAB.serif,
            fontSize: 'clamp(40px, 10vw, 104px)',
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
            fontSize: 'clamp(16px, 2.4vw, 20px)',
            color: SLAB.text,
            opacity: 0.82,
            lineHeight: 1.55,
            maxWidth: 560,
            margin: '28px 0 36px',
            letterSpacing: -0.2,
            animation: 'sbmRise 0.8s 0.4s ease backwards',
          }}
        >
          Slabbist turns your iPhone into a bulk scanner for graded Pokémon. Real comps from recent sales. Offer sheets in a tap. Works at your counter and on the show floor.
        </p>

        <div
          className="slab-hero-cta"
          style={{
            display: 'flex',
            gap: 12,
            marginBottom: 48,
            flexWrap: 'wrap',
            animation: 'sbmRise 0.8s 0.5s ease backwards',
          }}
        >
          <button
            onClick={() => openAuth('waitlist')}
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
              boxShadow: '0 14px 40px oklch(1 0 0 / 0.08)',
            }}
          >
            Join the waitlist
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
            gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
            gap: 'clamp(40px, 5vw, 60px)',
            alignItems: 'center',
            marginTop: 32,
          }}
        >
          <div style={{ animation: 'sbmRise 0.9s 0.6s ease backwards' }}>
            <div
              style={{
                fontSize: 12,
                letterSpacing: 1.6,
                textTransform: 'uppercase',
                color: SLAB.dim,
                fontWeight: 500,
                marginBottom: 24,
              }}
            >
              What the app does
            </div>

            <ul
              style={{
                listStyle: 'none',
                padding: 0,
                margin: 0,
                display: 'flex',
                flexDirection: 'column',
                gap: 22,
                maxWidth: 560,
              }}
            >
              {CAPABILITIES.map((c) => (
                <li
                  key={c.title}
                  style={{
                    display: 'grid',
                    gridTemplateColumns: '36px 1fr',
                    gap: 16,
                    alignItems: 'start',
                  }}
                >
                  <div
                    style={{
                      width: 36,
                      height: 36,
                      borderRadius: 10,
                      background: SLAB.elev,
                      border: '1px solid ' + SLAB.hair,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      color: SLAB.gold,
                      marginTop: 2,
                    }}
                  >
                    <Icon name={c.icon} size={18} sw={1.7} />
                  </div>
                  <div>
                    <div
                      style={{
                        fontFamily: SLAB.serif,
                        fontSize: 22,
                        fontWeight: 400,
                        letterSpacing: -0.5,
                        lineHeight: 1.2,
                        marginBottom: 6,
                      }}
                    >
                      {c.title}
                    </div>
                    <div
                      style={{
                        fontSize: 14,
                        color: SLAB.muted,
                        lineHeight: 1.55,
                      }}
                    >
                      {c.body}
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          </div>

          <div className="slab-hero-mock-outer" style={{ animation: 'sbmRise 1s 0.3s ease backwards', position: 'relative' }}>
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
      className="slab-hero-mock"
      style={{
        width: 320,
        height: 640,
        margin: '0 auto',
        borderRadius: 48,
        position: 'relative',
        background: 'oklch(0.06 0.003 78)',
        padding: 10,
        boxShadow:
          '0 50px 120px oklch(0 0 0 / 0.55), 0 0 0 1px oklch(0.16 0.005 78), 0 0 0 6px oklch(0.21 0.006 78)',
        transform: 'perspective(2200px) rotateY(-6deg)',
      }}
    >
      <div
        style={{
          width: '100%',
          height: '100%',
          borderRadius: 40,
          overflow: 'hidden',
          background: 'radial-gradient(ellipse at 50% 30%, oklch(0.14 0.005 78), oklch(0.05 0.002 78))',
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
            background: 'oklch(0.03 0 0)',
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
                boxShadow: '0 0 14px oklch(0.82 0.13 78 / 0.8)',
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
            background: 'oklch(0.13 0.005 78 / 0.88)',
            backdropFilter: 'blur(14px)',
            WebkitBackdropFilter: 'blur(14px)',
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
                  fontSize: 10,
                  letterSpacing: 1.2,
                  textTransform: 'uppercase',
                  color: SLAB.muted,
                  fontWeight: 500,
                }}
              >
                Lot total
              </div>
              <div
                style={{
                  fontFamily: SLAB.serif,
                  fontSize: 32,
                  letterSpacing: -0.8,
                  lineHeight: 1,
                  marginTop: 6,
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

      </div>
    </div>
  );
}
