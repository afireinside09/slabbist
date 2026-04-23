'use client';

import { useEffect, useState } from 'react';
import { SLAB } from '@/lib/tokens';
import { Icon } from '@/components/icon';
import { SlabLogo } from '@/components/slab-logo';
import { useAuth } from './auth-context';

const NAV_LINKS = [
  { label: 'Features', href: '/features' },
  { label: 'How it works', href: '/#how-it-works' },
  { label: 'Pricing', href: '/#pricing' },
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
        transition: 'padding 0.25s ease',
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
        <a
          href="/"
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 14,
            padding: scrolled ? '6px 20px 6px 8px' : '6px 20px 6px 6px',
            borderRadius: 999,
            background: scrolled ? 'oklch(0.13 0.005 78 / 0.7)' : 'transparent',
            backdropFilter: scrolled ? 'blur(12px) saturate(160%)' : 'none',
            WebkitBackdropFilter: scrolled ? 'blur(12px) saturate(160%)' : 'none',
            border: scrolled ? '1px solid ' + SLAB.hair : '1px solid transparent',
            transition: 'padding 0.25s ease, background 0.25s ease, border-color 0.25s ease, backdrop-filter 0.25s ease',
            textDecoration: 'none',
            color: SLAB.text,
          }}
        >
          <div
            style={{
              display: 'flex',
              filter: 'drop-shadow(0 0 18px oklch(0.82 0.13 78 / 0.33))',
            }}
          >
            <SlabLogo size={52} title="Slabbist" />
          </div>
          <span style={{ fontWeight: 500, letterSpacing: -0.4, fontSize: 22 }}>Slabbist</span>
          <span
            style={{
              fontSize: 10,
              letterSpacing: 1.2,
              textTransform: 'uppercase',
              padding: '3px 8px',
              borderRadius: 4,
              color: SLAB.gold,
              border: '1px solid oklch(0.82 0.13 78 / 0.33)',
              fontWeight: 500,
            }}
          >
            Beta
          </span>
        </a>

        <div
          style={{
            display: 'flex',
            gap: 4,
            padding: 4,
            background: 'oklch(0.13 0.005 78 / 0.7)',
            backdropFilter: 'blur(12px) saturate(160%)',
            WebkitBackdropFilter: 'blur(12px) saturate(160%)',
            border: '1px solid ' + SLAB.hair,
            borderRadius: 999,
          }}
        >
          {NAV_LINKS.map((l) => (
            <a
              key={l.label}
              href={l.href}
              className="slab-nav-link"
              style={{
                padding: '12px 18px',
                fontSize: 14,
                textDecoration: 'none',
                borderRadius: 999,
                fontWeight: 500,
              }}
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
            onClick={() => openAuth('waitlist')}
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
            Join waitlist
            <Icon name="arrow" size={13} sw={2} />
          </button>
        </div>
      </div>
    </nav>
  );
}
