import { SLAB } from '@/lib/tokens';

const VIEWPORT_W = 300;
const VIEWPORT_H = 620;

function Device({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        width: VIEWPORT_W,
        height: VIEWPORT_H,
        maxWidth: '100%',
        borderRadius: 44,
        background: 'oklch(0.06 0.003 78)',
        padding: 10,
        boxShadow: '0 30px 70px oklch(0 0 0 / 0.40), 0 0 0 1px oklch(0.16 0.005 78), 0 0 0 6px oklch(0.21 0.006 78)',
      }}
    >
      <div style={{ position: 'relative', width: '100%', height: '100%', borderRadius: 36, overflow: 'hidden' }}>
        {children}
      </div>
    </div>
  );
}

export type DeepDive = {
  eyebrow: string;
  title: string;
  paragraphs: string[];
  example: string;
  screen: React.ReactNode;
};

export function FeatureDeepDive({
  eyebrow,
  title,
  paragraphs,
  example,
  screen,
  flip,
}: DeepDive & { flip: boolean }) {
  return (
    <section style={{ padding: 'clamp(72px, 9vw, 104px) 0', borderTop: '1px solid ' + SLAB.hair }}>
      <div className="slab-container" style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
        <div
          className="slab-intel-row"
          style={{
            display: 'grid',
            gridTemplateColumns: '1fr 1fr',
            gap: 'clamp(40px, 5vw, 72px)',
            alignItems: 'center',
            direction: flip ? 'rtl' : 'ltr',
          }}
        >
          <div style={{ direction: 'ltr', display: 'flex', justifyContent: 'center' }}>
            <Device>{screen}</Device>
          </div>

          <div style={{ direction: 'ltr' }}>
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
              {eyebrow}
            </div>
            <h2
              style={{
                fontFamily: SLAB.serif,
                fontSize: 'clamp(32px, 4vw, 48px)',
                fontWeight: 400,
                letterSpacing: -1.2,
                lineHeight: 1.05,
                margin: '0 0 20px',
                maxWidth: '18ch',
              }}
            >
              {title}
            </h2>
            {paragraphs.map((p, i) => (
              <p
                key={i}
                style={{ fontSize: 15, color: SLAB.muted, lineHeight: 1.6, maxWidth: '62ch', margin: '0 0 16px' }}
              >
                {p}
              </p>
            ))}
            <div
              style={{
                marginTop: 24,
                background: SLAB.elev,
                border: '1px solid ' + SLAB.hair,
                borderRadius: 14,
                padding: '14px 16px',
              }}
            >
              <div
                style={{
                  fontSize: 10,
                  letterSpacing: 1.4,
                  textTransform: 'uppercase',
                  color: SLAB.gold,
                  fontWeight: 600,
                  marginBottom: 6,
                }}
              >
                Example
              </div>
              <div style={{ fontFamily: SLAB.mono, fontSize: 13, color: SLAB.text, lineHeight: 1.5 }}>{example}</div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
