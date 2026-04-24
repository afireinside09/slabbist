'use client';

import { SLAB } from '@/lib/tokens';
import { Icon } from '@/components/icon';
import { useAuth } from './auth-context';

export function FinalCta() {
  const { openAuth } = useAuth();
  return (
    <section
      style={{
        padding: 'clamp(80px, 10vw, 112px) 0 clamp(72px, 8vw, 88px)',
        position: 'relative',
        borderTop: '1px solid ' + SLAB.hair,
        overflow: 'hidden',
      }}
    >
      <div
        className="slab-container"
        style={{
          maxWidth: 900,
          margin: '0 auto',
          padding: '0 24px',
          textAlign: 'center',
          position: 'relative',
        }}
      >
        <h2
          style={{
            fontFamily: SLAB.serif,
            fontSize: 'clamp(36px, 9vw, 88px)',
            fontWeight: 400,
            letterSpacing: -2,
            lineHeight: 1.02,
            margin: '0 0 28px',
          }}
        >
          Get it on your iPhone before your{' '}
          <span style={{ fontStyle: 'italic', color: SLAB.gold }}>next show</span>.
        </h2>
        <p
          style={{
            fontSize: 'clamp(15px, 2.2vw, 18px)',
            color: SLAB.muted,
            maxWidth: 580,
            margin: '0 auto 36px',
            lineHeight: 1.55,
          }}
        >
          Slabbist is rolling out to stores, sellers, and buyers in cohorts. Drop your email and we'll ping you the moment yours opens. No card, no setup call, no seat fees.
        </p>
        <div className="slab-finalcta-row" style={{ display: 'flex', gap: 12, justifyContent: 'center', flexWrap: 'wrap' }}>
          <button
            onClick={() => openAuth('waitlist')}
            style={{
              padding: '16px 30px',
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
            Join the waitlist <Icon name="arrow" size={15} sw={2.2} />
          </button>
          <button
            style={{
              padding: '16px 30px',
              borderRadius: 999,
              background: 'transparent',
              border: '1px solid ' + SLAB.hairStrong,
              color: SLAB.text,
              fontSize: 15,
              fontWeight: 500,
              cursor: 'pointer',
            }}
          >
            Book a 15-minute call
          </button>
        </div>
      </div>
    </section>
  );
}
