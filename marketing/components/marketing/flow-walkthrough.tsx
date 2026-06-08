'use client';

import { useEffect, useRef, useState } from 'react';
import { SLAB } from '@/lib/tokens';
import { FLOW_STEPS, type FlowStep } from './flow-steps';
import { FlowScreen } from './flow-screens';

const VIEWPORT_W = 300;
const VIEWPORT_H = 620;

function Device({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        width: VIEWPORT_W,
        height: VIEWPORT_H,
        borderRadius: 44,
        background: 'oklch(0.06 0.003 78)',
        padding: 10,
        margin: '0 auto',
        boxShadow: '0 30px 70px oklch(0 0 0 / 0.40), 0 0 0 1px oklch(0.16 0.005 78), 0 0 0 6px oklch(0.21 0.006 78)',
      }}
    >
      <div style={{ position: 'relative', width: '100%', height: '100%', borderRadius: 36, overflow: 'hidden' }}>
        {children}
      </div>
    </div>
  );
}

function Beat({ step, active }: { step: FlowStep; active: boolean }) {
  return (
    <div style={{ opacity: active ? 1 : 0.4, transition: 'opacity 0.3s ease' }}>
      <div style={{ fontFamily: SLAB.mono, fontSize: 12, color: SLAB.gold, marginBottom: 10 }}>{step.n}</div>
      <div style={{ fontSize: 11, letterSpacing: 1.6, textTransform: 'uppercase', color: SLAB.dim, marginBottom: 12, fontWeight: 500 }}>{step.kicker}</div>
      <h3 style={{ fontFamily: SLAB.serif, fontSize: 'clamp(28px, 3.4vw, 40px)', fontWeight: 400, letterSpacing: -1, lineHeight: 1.05, margin: '0 0 16px' }}>{step.title}</h3>
      <p style={{ fontSize: 15, color: SLAB.muted, lineHeight: 1.6, maxWidth: '46ch', margin: 0 }}>{step.body}</p>
    </div>
  );
}

function SectionHeader() {
  return (
    <div style={{ marginBottom: 'clamp(40px, 5vw, 64px)', maxWidth: 620 }}>
      <div style={{ fontSize: 12, letterSpacing: 1.6, textTransform: 'uppercase', color: SLAB.gold, marginBottom: 18, fontWeight: 500 }}>How it works</div>
      <h2 style={{ fontFamily: SLAB.serif, fontSize: 'clamp(40px, 5vw, 64px)', fontWeight: 400, letterSpacing: -1.5, lineHeight: 1.05, margin: 0 }}>
        Watch a stack turn into a paid offer.
      </h2>
    </div>
  );
}

export function FlowWalkthrough() {
  const [active, setActive] = useState(0);
  const [stacked, setStacked] = useState(false);
  const beatRefs = useRef<(HTMLDivElement | null)[]>([]);

  useEffect(() => {
    const rm = window.matchMedia('(prefers-reduced-motion: reduce)');
    const mob = window.matchMedia('(max-width: 720px)');
    const update = () => setStacked(rm.matches || mob.matches);
    update();
    rm.addEventListener('change', update);
    mob.addEventListener('change', update);
    return () => {
      rm.removeEventListener('change', update);
      mob.removeEventListener('change', update);
    };
  }, []);

  useEffect(() => {
    if (stacked) return;
    const obs = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            const i = beatRefs.current.indexOf(e.target as HTMLDivElement);
            if (i >= 0) setActive(i);
          }
        });
      },
      { rootMargin: '-45% 0px -45% 0px', threshold: 0 },
    );
    beatRefs.current.forEach((el) => el && obs.observe(el));
    return () => obs.disconnect();
  }, [stacked]);

  const sectionStyle: React.CSSProperties = {
    padding: 'clamp(84px, 11vw, 120px) 0',
    borderTop: '1px solid ' + SLAB.hair,
  };
  const container: React.CSSProperties = { maxWidth: 1180, margin: '0 auto', padding: '0 24px' };

  if (stacked) {
    return (
      <section id="how-it-works" style={sectionStyle}>
        <div style={container}>
          <SectionHeader />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'clamp(56px, 9vw, 80px)' }}>
            {FLOW_STEPS.map((s, i) => (
              <div key={s.id}>
                <div style={{ width: VIEWPORT_W, maxWidth: '100%', marginBottom: 28 }}>
                  <Device>
                    <FlowScreen step={i} />
                  </Device>
                </div>
                <Beat step={s} active />
              </div>
            ))}
          </div>
        </div>
      </section>
    );
  }

  return (
    <section id="how-it-works" style={sectionStyle}>
      <div style={container}>
        <SectionHeader />
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 48, alignItems: 'start' }}>
          <div style={{ position: 'sticky', top: 100, height: 'fit-content' }}>
            <Device>
              {FLOW_STEPS.map((s, i) => (
                <div
                  key={s.id}
                  aria-hidden
                  style={{ position: 'absolute', inset: 0, opacity: active === i ? 1 : 0, transition: 'opacity 0.4s ease', pointerEvents: 'none' }}
                >
                  <FlowScreen step={i} />
                </div>
              ))}
            </Device>
          </div>
          <div>
            {FLOW_STEPS.map((s, i) => (
              <div
                key={s.id}
                ref={(el) => {
                  beatRefs.current[i] = el;
                }}
                style={{ minHeight: '78vh', display: 'flex', flexDirection: 'column', justifyContent: 'center' }}
              >
                <Beat step={s} active={active === i} />
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
