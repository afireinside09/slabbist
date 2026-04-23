'use client';

import { SLAB } from '@/lib/tokens';
import { Icon } from '@/components/icon';
import { useAuth } from './auth-context';

export function FinalCta() {
  const { openAuth } = useAuth();
  return (
    <section
      style={{
        padding: '140px 0 100px',
        position: 'relative',
        borderTop: '1px solid ' + SLAB.hair,
        overflow: 'hidden',
      }}
    >
      <div
        aria-hidden
        style={{
          position: 'absolute',
          top: '-30%',
          left: '50%',
          transform: 'translateX(-50%)',
          width: 900,
          height: 900,
          borderRadius: '50%',
          background: `radial-gradient(circle, ${SLAB.gold} 0%, transparent 60%)`,
          opacity: 0.1,
          filter: 'blur(60px)',
          pointerEvents: 'none',
        }}
      />

      <div
        style={{
          maxWidth: 900,
          margin: '0 auto',
          padding: '0 32px',
          textAlign: 'center',
          position: 'relative',
        }}
      >
        <h2
          style={{
            fontFamily: SLAB.serif,
            fontSize: 'clamp(48px, 7vw, 88px)',
            fontWeight: 400,
            letterSpacing: -2,
            lineHeight: 1,
            margin: '0 0 32px',
          }}
        >
          Put your counter on the{' '}
          <span style={{ fontStyle: 'italic', color: SLAB.gold }}>right side</span> of every buy.
        </h2>
        <p
          style={{
            fontSize: 18,
            color: SLAB.muted,
            maxWidth: 560,
            margin: '0 auto 40px',
            lineHeight: 1.5,
          }}
        >
          We&rsquo;re onboarding new stores in cohorts. Get a 30-minute setup call and your team rolling by next weekend.
        </p>
        <div style={{ display: 'flex', gap: 12, justifyContent: 'center', flexWrap: 'wrap' }}>
          <button
            onClick={() => openAuth('signup')}
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
              boxShadow: `0 20px 50px ${SLAB.gold}44`,
            }}
          >
            Request early access <Icon name="arrow" size={15} sw={2.2} />
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
            Book a demo
          </button>
        </div>
      </div>
    </section>
  );
}
