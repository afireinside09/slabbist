'use client';

import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';
import { useAuth, type WaitlistAudience } from './auth-context';

export type AudiencePoint = { icon: IconName; title: string; blurb: string };

export function AudienceBody({
  pain,
  shift,
  points,
  ctaLabel,
  waitlistAudience,
}: {
  pain: string;
  shift: string;
  points: AudiencePoint[];
  ctaLabel: string;
  waitlistAudience: WaitlistAudience;
}) {
  const { openAuth } = useAuth();

  return (
    <>
      <section
        style={{
          padding: 'clamp(40px, 6vw, 64px) 0 clamp(56px, 8vw, 88px)',
          borderTop: '1px solid ' + SLAB.hair,
        }}
      >
        <div
          style={{
            maxWidth: 1180,
            margin: '0 auto',
            padding: '0 24px',
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
            gap: 'clamp(32px, 5vw, 56px)',
          }}
        >
          <div
            style={{
              padding: 28,
              borderRadius: 20,
              background: SLAB.elev,
              border: '1px solid ' + SLAB.hair,
            }}
          >
            <div
              style={{
                fontSize: 11,
                letterSpacing: 1.4,
                textTransform: 'uppercase',
                color: SLAB.dim,
                marginBottom: 10,
                fontWeight: 600,
              }}
            >
              The problem
            </div>
            <div
              style={{
                fontFamily: SLAB.serif,
                fontSize: 24,
                letterSpacing: -0.5,
                lineHeight: 1.3,
              }}
            >
              {pain}
            </div>
          </div>
          <div
            style={{
              padding: 28,
              borderRadius: 20,
              background: 'linear-gradient(145deg, oklch(0.22 0.06 78), oklch(0.14 0.03 78))',
              border: '1px solid oklch(0.82 0.13 78 / 0.27)',
            }}
          >
            <div
              style={{
                fontSize: 11,
                letterSpacing: 1.4,
                textTransform: 'uppercase',
                color: SLAB.gold,
                marginBottom: 10,
                fontWeight: 600,
              }}
            >
              What changes
            </div>
            <div
              style={{
                fontFamily: SLAB.serif,
                fontSize: 24,
                letterSpacing: -0.5,
                lineHeight: 1.3,
              }}
            >
              {shift}
            </div>
          </div>
        </div>
      </section>

      <section
        style={{
          padding: 'clamp(56px, 8vw, 88px) 0',
          borderTop: '1px solid ' + SLAB.hair,
        }}
      >
        <div style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
          <div
            style={{
              fontSize: 12,
              letterSpacing: 1.6,
              textTransform: 'uppercase',
              color: SLAB.gold,
              marginBottom: 16,
              fontWeight: 500,
            }}
          >
            What you get
          </div>
          <h2
            style={{
              fontFamily: SLAB.serif,
              fontSize: 'clamp(32px, 4vw, 48px)',
              fontWeight: 400,
              letterSpacing: -1,
              lineHeight: 1.1,
              margin: '0 0 40px',
              maxWidth: 600,
            }}
          >
            Made for how you actually work.
          </h2>

          <div
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))',
              gap: 1,
              background: SLAB.hair,
              border: '1px solid ' + SLAB.hair,
              borderRadius: 16,
              overflow: 'hidden',
            }}
          >
            {points.map((p) => (
              <div
                key={p.title}
                style={{
                  padding: '28px 26px 32px',
                  background: SLAB.ink,
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 14,
                }}
              >
                <div
                  style={{
                    width: 40,
                    height: 40,
                    borderRadius: 10,
                    background: SLAB.elev2,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    color: SLAB.gold,
                  }}
                >
                  <Icon name={p.icon} size={18} sw={1.8} />
                </div>
                <div style={{ fontSize: 17, fontWeight: 500, letterSpacing: -0.3 }}>{p.title}</div>
                <div style={{ fontSize: 14, color: SLAB.muted, lineHeight: 1.55 }}>{p.blurb}</div>
              </div>
            ))}
          </div>

          <div style={{ marginTop: 48, display: 'flex', gap: 12, flexWrap: 'wrap' }}>
            <button
              onClick={() => openAuth('waitlist', waitlistAudience)}
              style={{
                padding: '16px 28px',
                borderRadius: 999,
                background: SLAB.gold,
                color: SLAB.ink,
                border: 'none',
                fontSize: 15,
                fontWeight: 600,
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                boxShadow: '0 20px 50px oklch(0.82 0.13 78 / 0.27)',
              }}
            >
              {ctaLabel}
              <Icon name="arrow" size={15} sw={2.2} />
            </button>
            <a
              href="/features"
              style={{
                padding: '16px 28px',
                borderRadius: 999,
                background: SLAB.elev,
                border: '1px solid ' + SLAB.hairStrong,
                color: SLAB.text,
                fontSize: 15,
                fontWeight: 500,
                cursor: 'pointer',
                textDecoration: 'none',
              }}
            >
              See every feature
            </a>
          </div>
        </div>
      </section>
    </>
  );
}
