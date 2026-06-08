import { SLAB } from '@/lib/tokens';
import { Icon } from '@/components/icon';

// Standalone screen recreations for the Features deep-dives that the homepage
// flow doesn't cover (Pre-grade and Market intel). Each fills the device
// viewport the same way the flow screens do (absolute inset).

const screenWrap: React.CSSProperties = {
  position: 'absolute',
  inset: 0,
  background: SLAB.surface,
  padding: 18,
  overflow: 'hidden',
  display: 'flex',
  flexDirection: 'column',
  gap: 12,
  fontFamily: SLAB.sans,
  color: SLAB.text,
};

function Kicker({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ fontSize: 10, letterSpacing: 1.4, textTransform: 'uppercase', color: SLAB.dim, fontWeight: 500 }}>
      {children}
    </div>
  );
}

function Card({ children, style }: { children: React.ReactNode; style?: React.CSSProperties }) {
  return (
    <div
      style={{ background: SLAB.elev, border: '1px solid ' + SLAB.hair, borderRadius: 14, padding: 14, ...style }}
    >
      {children}
    </div>
  );
}

export function PreGradeScreen() {
  const sub: [string, string][] = [
    ['Centering', '9.5'],
    ['Corners', '9'],
    ['Edges', '9.5'],
    ['Surface', '10'],
  ];
  return (
    <div style={screenWrap}>
      <Kicker>Pre-grade</Kicker>
      <Card
        style={{
          position: 'relative',
          flex: '0 0 auto',
          height: 150,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: 'linear-gradient(145deg, oklch(0.22 0.04 78), oklch(0.12 0.02 78))',
        }}
      >
        <div
          style={{
            position: 'absolute',
            top: 10,
            right: 10,
            width: 44,
            height: 44,
            borderRadius: 999,
            background: `linear-gradient(135deg, ${SLAB.gold}, ${SLAB.goldDim})`,
            color: SLAB.ink,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontFamily: SLAB.serif,
            fontSize: 20,
          }}
        >
          9.5
        </div>
        <div style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim }}>front · back on file</div>
      </Card>

      <Kicker>Sub-grades</Kicker>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
        {sub.map(([k, v]) => (
          <div key={k} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ fontSize: 12, color: SLAB.muted, width: 74 }}>{k}</span>
            <div style={{ flex: 1, height: 6, borderRadius: 999, background: SLAB.elev2, overflow: 'hidden' }}>
              <div style={{ width: `${(parseFloat(v) / 10) * 100}%`, height: '100%', background: SLAB.gold }} />
            </div>
            <span style={{ fontFamily: SLAB.mono, fontSize: 12, width: 26, textAlign: 'right' }}>{v}</span>
          </div>
        ))}
      </div>

      <div
        style={{
          marginTop: 'auto',
          display: 'flex',
          justifyContent: 'space-between',
          fontFamily: SLAB.mono,
          fontSize: 11,
          color: SLAB.dim,
        }}
      >
        <span>Centering 55/45</span>
        <span>Confidence High</span>
      </div>
    </div>
  );
}

export function MarketScreen() {
  const movers: [string, string, boolean][] = [
    ['Charizard #4', '+6.2%', true],
    ['Blastoise #2', '+3.1%', true],
    ['Venusaur #15', '-2.4%', false],
  ];
  return (
    <div style={screenWrap}>
      <Kicker>Movers · Base Set</Kicker>
      <Card>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
          {movers.map(([n, d, up]) => (
            <div key={n} style={{ display: 'flex', alignItems: 'center' }}>
              <span style={{ fontSize: 12 }}>{n}</span>
              <span style={{ marginLeft: 'auto', fontFamily: SLAB.mono, fontSize: 12, color: up ? SLAB.pos : SLAB.neg }}>
                {up ? '▲' : '▼'} {d}
              </span>
            </div>
          ))}
        </div>
      </Card>

      <Kicker>Grade gains</Kicker>
      <Card>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ fontFamily: SLAB.mono, fontSize: 12, color: SLAB.muted }}>Raw $4</span>
          <Icon name="arrow" size={13} sw={2} color={SLAB.dim} />
          <span style={{ fontFamily: SLAB.mono, fontSize: 12, color: SLAB.muted }}>PSA 10 $185</span>
          <span style={{ marginLeft: 'auto', fontFamily: SLAB.mono, fontSize: 13, fontWeight: 600, color: SLAB.gold }}>
            +$156
          </span>
        </div>
        <div style={{ marginTop: 8, fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim }}>after $25 grading fee</div>
      </Card>
    </div>
  );
}
