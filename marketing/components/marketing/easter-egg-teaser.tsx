import { SLAB } from '@/lib/tokens';

export function EasterEggTeaser() {
  return (
    <section
      style={{
        padding: 'clamp(72px, 9vw, 104px) 0',
        borderTop: '1px solid ' + SLAB.hair,
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      {/* Abstract silhouette peeking in from the edge — intentionally unrecognizable. */}
      <div
        aria-hidden
        style={{
          position: 'absolute',
          right: -36,
          top: '50%',
          transform: 'translateY(-50%)',
          width: 150,
          height: 150,
          borderRadius: '50% 50% 46% 54% / 58% 58% 42% 42%',
          background: `radial-gradient(circle at 38% 34%, oklch(0.82 0.13 78 / 0.22), oklch(0.82 0.13 78 / 0.04))`,
          border: '1px solid oklch(0.82 0.13 78 / 0.18)',
          filter: 'blur(0.4px)',
          pointerEvents: 'none',
        }}
      />
      <div className="slab-container" style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px', position: 'relative' }}>
        <div style={{ maxWidth: 620 }}>
          <div
            style={{
              fontSize: 12,
              letterSpacing: 1.6,
              textTransform: 'uppercase',
              color: SLAB.gold,
              marginBottom: 18,
              fontWeight: 500,
            }}
          >
            One more thing
          </div>
          <h2
            style={{
              fontFamily: SLAB.serif,
              fontSize: 'clamp(32px, 4.5vw, 56px)',
              fontWeight: 400,
              letterSpacing: -1.4,
              lineHeight: 1.06,
              margin: 0,
            }}
          >
            There's something in here we{' '}
            <span style={{ fontStyle: 'italic', color: SLAB.gold }}>didn't</span> tell you about.
          </h2>
          <p style={{ fontSize: 17, color: SLAB.muted, lineHeight: 1.6, marginTop: 22 }}>
            Keep the app open and stay sharp. Every so often, something pokes its head in — blink and
            it's gone. Catch it, and a door opens. We won't say what's behind it.
          </p>
          <p style={{ fontSize: 17, color: SLAB.text, lineHeight: 1.6, marginTop: 14, fontStyle: 'italic' }}>
            Half the fun is finding out.
          </p>
        </div>
      </div>
    </section>
  );
}
