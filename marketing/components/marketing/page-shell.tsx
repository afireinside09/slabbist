import type { ReactNode } from 'react';
import { SLAB } from '@/lib/tokens';
import { Nav } from './nav';
import { Footer } from './footer';

export function PageShell({ children }: { children: ReactNode }) {
  return (
    <>
      <Nav />
      <main style={{ paddingTop: 'clamp(120px, 14vw, 148px)' }}>{children}</main>
      <Footer />
    </>
  );
}

export function PageHero({
  eyebrow,
  title,
  subtitle,
  italicize,
}: {
  eyebrow: string;
  title: ReactNode;
  subtitle?: string;
  /** Word(s) to italicize + gold inside the title */
  italicize?: string;
}) {
  const rendered = (() => {
    if (!italicize || typeof title !== 'string') return title;
    const idx = title.indexOf(italicize);
    if (idx < 0) return title;
    return (
      <>
        {title.slice(0, idx)}
        <span style={{ fontStyle: 'italic', color: SLAB.gold }}>{italicize}</span>
        {title.slice(idx + italicize.length)}
      </>
    );
  })();

  return (
    <section
      style={{
        position: 'relative',
        paddingBottom: 'clamp(48px, 7vw, 72px)',
        overflow: 'hidden',
      }}
    >
      <div
        aria-hidden
        style={{
          position: 'absolute',
          top: -40,
          right: '-12%',
          width: 620,
          height: 620,
          borderRadius: '50%',
          background: `radial-gradient(circle, ${SLAB.gold} 0%, transparent 55%)`,
          opacity: 0.07,
          filter: 'blur(60px)',
          pointerEvents: 'none',
        }}
      />
      <div className="slab-container" style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px', position: 'relative' }}>
        <div
          style={{
            fontSize: 12,
            letterSpacing: 1.6,
            textTransform: 'uppercase',
            color: SLAB.gold,
            marginBottom: 20,
            fontWeight: 500,
          }}
        >
          {eyebrow}
        </div>
        <h1
          style={{
            fontFamily: SLAB.serif,
            fontSize: 'clamp(34px, 8vw, 80px)',
            fontWeight: 400,
            letterSpacing: -2,
            lineHeight: 1.02,
            margin: 0,
            maxWidth: 860,
          }}
        >
          {rendered}
        </h1>
        {subtitle && (
          <p
            style={{
              fontSize: 'clamp(15px, 2.2vw, 19px)',
              color: SLAB.text,
              opacity: 0.82,
              lineHeight: 1.55,
              maxWidth: 620,
              margin: '28px 0 0',
              letterSpacing: -0.2,
            }}
          >
            {subtitle}
          </p>
        )}
      </div>
    </section>
  );
}

export function Prose({ children }: { children: ReactNode }) {
  return (
    <section
      style={{
        padding: 'clamp(32px, 5vw, 56px) 0 clamp(96px, 12vw, 140px)',
      }}
    >
      <div
        style={{
          maxWidth: 760,
          margin: '0 auto',
          padding: '0 24px',
          fontSize: 16,
          lineHeight: 1.7,
          color: SLAB.text,
        }}
        className="slab-prose slab-container"
      >
        {children}
      </div>
    </section>
  );
}
