'use client';

import { useEffect, useRef, useState } from 'react';
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
  const [menuOpen, setMenuOpen] = useState(false);
  const { openAuth } = useAuth();
  const menuButtonRef = useRef<HTMLButtonElement | null>(null);
  const firstSheetLinkRef = useRef<HTMLAnchorElement | null>(null);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    if (!menuOpen) return;
    const previouslyFocused = document.activeElement as HTMLElement | null;
    document.body.style.overflow = 'hidden';
    firstSheetLinkRef.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        setMenuOpen(false);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = '';
      previouslyFocused?.focus?.();
    };
  }, [menuOpen]);

  const closeMenu = () => setMenuOpen(false);

  return (
    <nav
      className="slab-nav-wrap"
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
        className="slab-container"
        style={{
          maxWidth: 1180,
          margin: '0 auto',
          padding: '0 32px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 12,
        }}
      >
        <a
          href="/"
          className="slab-nav-brand"
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
            minWidth: 0,
          }}
        >
          <div
            style={{
              display: 'flex',
              filter: 'drop-shadow(0 0 18px oklch(0.82 0.13 78 / 0.33))',
              flexShrink: 0,
            }}
          >
            <SlabLogo size={52} title="Slabbist" />
          </div>
          <span className="slab-nav-wordmark" style={{ fontWeight: 500, letterSpacing: -0.4, fontSize: 22 }}>Slabbist</span>
          <span
            className="slab-nav-beta"
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
          className="slab-nav-links"
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

        <div style={{ display: 'flex', gap: 10, alignItems: 'center', flexShrink: 0 }}>
          <button
            onClick={() => openAuth('login')}
            className="slab-nav-signin"
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
            className="slab-nav-cta"
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
              whiteSpace: 'nowrap',
            }}
          >
            Join waitlist
            <Icon name="arrow" size={13} sw={2} />
          </button>
          <button
            ref={menuButtonRef}
            type="button"
            className="slab-nav-menu"
            aria-label={menuOpen ? 'Close menu' : 'Open menu'}
            aria-expanded={menuOpen}
            aria-controls="slab-nav-sheet"
            onClick={() => setMenuOpen((o) => !o)}
            style={{
              display: 'none',
              width: 40,
              height: 40,
              borderRadius: 999,
              background: 'transparent',
              border: '1px solid ' + SLAB.hair,
              color: SLAB.text,
              cursor: 'pointer',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <Icon name={menuOpen ? 'x' : 'menu'} size={18} sw={2} />
          </button>
        </div>
      </div>

      {menuOpen && (
        <>
          <div
            onClick={closeMenu}
            aria-hidden
            style={{
              position: 'fixed',
              inset: 0,
              top: 0,
              background: 'oklch(0.05 0.003 78 / 0.72)',
              zIndex: 99,
            }}
          />
          <div
            id="slab-nav-sheet"
            role="dialog"
            aria-modal="true"
            aria-label="Site navigation"
            style={{
              position: 'fixed',
              top: 72,
              left: 16,
              right: 16,
              zIndex: 101,
              padding: 12,
              background: SLAB.surface,
              border: '1px solid ' + SLAB.hair,
              borderRadius: 22,
              display: 'flex',
              flexDirection: 'column',
              gap: 4,
              boxShadow: '0 30px 80px oklch(0 0 0 / 0.5)',
            }}
          >
            {NAV_LINKS.map((l, i) => (
              <a
                key={l.label}
                href={l.href}
                ref={i === 0 ? firstSheetLinkRef : undefined}
                onClick={closeMenu}
                style={{
                  display: 'block',
                  padding: '14px 16px',
                  borderRadius: 14,
                  fontSize: 16,
                  fontWeight: 500,
                  color: SLAB.text,
                  textDecoration: 'none',
                }}
              >
                {l.label}
              </a>
            ))}
            <div style={{ height: 1, background: SLAB.hair, margin: '6px 12px' }} />
            <button
              type="button"
              onClick={() => {
                closeMenu();
                openAuth('login');
              }}
              style={{
                textAlign: 'left',
                padding: '14px 16px',
                borderRadius: 14,
                fontSize: 16,
                fontWeight: 500,
                color: SLAB.text,
                background: 'transparent',
                border: 'none',
                cursor: 'pointer',
              }}
            >
              Sign in
            </button>
          </div>
        </>
      )}
    </nav>
  );
}
