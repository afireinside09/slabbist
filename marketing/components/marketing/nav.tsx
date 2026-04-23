'use client';

import { useEffect, useState } from 'react';
import { SLAB } from '@/lib/tokens';
import { Icon } from '@/components/icon';
import { useAuth } from './auth-context';

const NAV_LINKS = [
  { label: 'Product', href: '#product' },
  { label: 'How it works', href: '#how-it-works' },
  { label: 'Pricing', href: '#pricing' },
  { label: 'Docs', href: '#docs' },
];

export function Nav() {
  const [scrolled, setScrolled] = useState(false);
  const { openAuth } = useAuth();

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <nav
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        right: 0,
        zIndex: 100,
        padding: scrolled ? '12px 0' : '22px 0',
        transition: 'all 0.25s ease',
      }}
    >
      <div
        style={{
          maxWidth: 1180,
          margin: '0 auto',
          padding: '0 32px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}
      >
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            padding: scrolled ? '10px 18px' : '10px 18px 10px 10px',
            borderRadius: 999,
            background: scrolled ? 'rgba(14,14,18,0.7)' : 'transparent',
            backdropFilter: scrolled ? 'blur(18px) saturate(180%)' : 'none',
            WebkitBackdropFilter: scrolled ? 'blur(18px) saturate(180%)' : 'none',
            border: scrolled ? '1px solid ' + SLAB.hair : '1px solid transparent',
            transition: 'all 0.25s ease',
          }}
        >
          <div
            style={{
              width: 30,
              height: 30,
              borderRadius: 8,
              background: `linear-gradient(135deg, ${SLAB.gold}, ${SLAB.goldDim})`,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontFamily: SLAB.serif,
              fontStyle: 'italic',
              fontWeight: 600,
              color: SLAB.ink,
              fontSize: 17,
              boxShadow: `0 0 14px ${SLAB.gold}44`,
            }}
          >
            S
          </div>
          <span style={{ fontWeight: 500, letterSpacing: -0.3, fontSize: 16 }}>Slabbist</span>
          <span
            style={{
              fontSize: 9,
              letterSpacing: 1.2,
              textTransform: 'uppercase',
              padding: '2px 6px',
              borderRadius: 4,
              color: SLAB.gold,
              border: `1px solid ${SLAB.gold}55`,
              fontWeight: 500,
              marginLeft: 4,
            }}
          >
            Beta
          </span>
        </div>

        <div
          style={{
            display: 'flex',
            gap: 4,
            padding: 4,
            background: 'rgba(14,14,18,0.7)',
            backdropFilter: 'blur(18px) saturate(180%)',
            WebkitBackdropFilter: 'blur(18px) saturate(180%)',
            border: '1px solid ' + SLAB.hair,
            borderRadius: 999,
          }}
        >
          {NAV_LINKS.map((l) => (
            <a
              key={l.label}
              href={l.href}
              style={{
                padding: '10px 18px',
                fontSize: 13,
                color: SLAB.muted,
                textDecoration: 'none',
                borderRadius: 999,
                fontWeight: 500,
                transition: 'color 0.15s',
              }}
              onMouseEnter={(e) => (e.currentTarget.style.color = SLAB.text)}
              onMouseLeave={(e) => (e.currentTarget.style.color = SLAB.muted)}
            >
              {l.label}
            </a>
          ))}
        </div>

        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          <button
            onClick={() => openAuth('login')}
            style={{
              padding: '10px 18px',
              borderRadius: 999,
              background: 'transparent',
              border: '1px solid ' + SLAB.hair,
              color: SLAB.text,
              fontSize: 13,
              fontWeight: 500,
              cursor: 'pointer',
            }}
          >
            Sign in
          </button>
          <button
            onClick={() => openAuth('signup')}
            style={{
              padding: '10px 20px',
              borderRadius: 999,
              background: SLAB.text,
              color: SLAB.ink,
              border: 'none',
              fontSize: 13,
              fontWeight: 600,
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: 6,
            }}
          >
            Get started
            <Icon name="arrow" size={13} sw={2} />
          </button>
        </div>
      </div>
    </nav>
  );
}
