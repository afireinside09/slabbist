import { SLAB } from '@/lib/tokens';

// ---- shared screen chrome -------------------------------------------------
// Every screen renders inside the device viewport at a fixed logical size so
// the recreations line up across crossfades. The device frame is owned by
// flow-walkthrough.tsx; screens fill their parent.
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
      style={{
        background: SLAB.elev,
        border: '1px solid ' + SLAB.hair,
        borderRadius: 14,
        padding: 14,
        ...style,
      }}
    >
      {children}
    </div>
  );
}

// ---- 02 · Comp ------------------------------------------------------------
const LADDER: [string, string, boolean][] = [
  ['Raw', '$4', false],
  ['PSA 10', '$185', true],
  ['PSA 9.5', '$112', false],
  ['PSA 9', '$68', false],
  ['PSA 8', '$34', false],
  ['BGS 10', '$215', false],
];

function CompScreen() {
  return (
    <div style={screenWrap}>
      <Card>
        <div style={{ fontFamily: SLAB.serif, fontSize: 40, letterSpacing: -1, lineHeight: 1 }}>$188</div>
        <div style={{ fontSize: 10, letterSpacing: 2, textTransform: 'uppercase', color: SLAB.dim, marginTop: 6 }}>
          Poketrace · n=14 · PSA 10
        </div>
        <div style={{ display: 'flex', marginTop: 14, borderTop: '1px solid ' + SLAB.hair, paddingTop: 12 }}>
          {([['AVG', '$188'], ['RANGE', '$175–$210'], ['SALES', 'n=14 ▲']] as const).map(([t, v], i) => (
            <div key={t} style={{ flex: 1, paddingLeft: i ? 12 : 0, borderLeft: i ? '1px solid ' + SLAB.hair : 'none' }}>
              <div style={{ fontSize: 9, letterSpacing: 1.2, textTransform: 'uppercase', color: SLAB.dim }}>{t}</div>
              <div style={{ fontFamily: SLAB.mono, fontSize: 13, fontWeight: 600, marginTop: 3 }}>{v}</div>
            </div>
          ))}
        </div>
        {/* sparkline */}
        <svg width="100%" height="32" viewBox="0 0 200 32" style={{ marginTop: 12 }} aria-hidden>
          <polyline points="0,24 30,20 60,22 90,14 120,16 150,8 200,6" fill="none" stroke={SLAB.gold} strokeWidth="1.5" />
        </svg>
      </Card>

      <Kicker>Per-grade ladder</Kicker>
      <div style={{ display: 'flex', gap: 8, overflowX: 'hidden' }}>
        {LADDER.map(([g, p, hot]) => (
          <div
            key={g}
            style={{
              flex: '0 0 auto',
              padding: '8px 10px',
              borderRadius: 10,
              border: (hot ? '1.5px solid ' + SLAB.gold : '1px solid ' + SLAB.hair),
            }}
          >
            <div style={{ fontSize: 9, letterSpacing: 1.2, textTransform: 'uppercase', color: SLAB.dim }}>{g}</div>
            <div style={{ fontFamily: SLAB.mono, fontSize: 13, marginTop: 2 }}>{p}</div>
          </div>
        ))}
      </div>

      <div style={{ marginTop: 'auto', fontSize: 11, color: SLAB.dim }}>Comp data from Poketrace</div>
    </div>
  );
}

// ---- 01 · Scan ------------------------------------------------------------
type ScanRow = { grader: string; cert: string; dot: string; trail: React.ReactNode };

function Pill({ children }: { children: React.ReactNode }) {
  return (
    <span style={{ fontSize: 11, color: SLAB.gold, border: '1px solid ' + SLAB.gold, borderRadius: 999, padding: '2px 8px' }}>
      {children}
    </span>
  );
}

function ScanScreen() {
  const rows: ScanRow[] = [
    { grader: 'PSA', cert: '12345678', dot: SLAB.pos, trail: <span style={{ fontFamily: SLAB.mono, fontWeight: 600 }}>$188</span> },
    { grader: 'BGS', cert: '0098761234', dot: SLAB.gold, trail: <Pill>Set price</Pill> },
    { grader: 'CGC', cert: '4012998877', dot: SLAB.gold, trail: <span style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim }}>pending validation</span> },
    { grader: 'SGC', cert: '88412290', dot: SLAB.muted, trail: <span style={{ fontFamily: SLAB.mono, fontWeight: 600 }}>$42 ✎</span> },
    { grader: 'PSA', cert: '55120934', dot: SLAB.pos, trail: <span style={{ fontFamily: SLAB.mono, fontWeight: 600 }}>$96</span> },
  ];
  return (
    <div style={{ ...screenWrap, background: SLAB.ink, justifyContent: 'flex-end' }}>
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(ellipse at 50% 35%, oklch(0.13 0.005 78), oklch(0.05 0.002 78))' }} aria-hidden />
      {/* scan-frame brackets */}
      <div style={{ position: 'absolute', top: 70, left: 40, right: 40, height: 150, border: '1px solid ' + SLAB.hairStrong, borderRadius: 10 }} aria-hidden />
      <Card style={{ position: 'relative', background: 'oklch(0.10 0.004 78 / 0.94)' }}>
        <Kicker>Queue</Kicker>
        <div style={{ margin: '2px 0 10px' }}>
          <span style={{ fontFamily: SLAB.mono, fontSize: 20, fontWeight: 600 }}>12</span>
          <span style={{ color: SLAB.muted, fontSize: 13 }}> scanned</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {rows.map((r, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span style={{ width: 8, height: 8, borderRadius: 999, background: r.dot, flexShrink: 0 }} />
              <span style={{ fontFamily: SLAB.mono, fontSize: 12 }}>{r.grader} · {r.cert}</span>
              <span style={{ marginLeft: 'auto', fontSize: 12 }}>{r.trail}</span>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}

// ---- 03 · Margin ----------------------------------------------------------
function MarginScreen() {
  const lines: [string, string, string, boolean][] = [
    // name, comp, buy, overridden
    ['Charizard #4', '$188', 'Buy $131', false],
    ['Blastoise #2', '$96', 'Buy $67', false],
    ['Venusaur #15', '$74', 'Buy $60', true],
  ];
  return (
    <div style={screenWrap}>
      <Card>
        <Kicker>Estimated</Kicker>
        <div style={{ fontFamily: SLAB.serif, fontSize: 38, letterSpacing: -1, lineHeight: 1, marginTop: 4 }}>$1,240</div>
        <div style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim, marginTop: 4 }}>across 9 slabs · 2 manual</div>
      </Card>

      <Card>
        <Kicker>Margin</Kicker>
        <div style={{ display: 'flex', gap: 4, background: SLAB.elev2, borderRadius: 10, padding: 3, margin: '8px 0' }}>
          <div style={{ flex: 1, textAlign: 'center', fontSize: 11, padding: '6px 0', borderRadius: 8, background: SLAB.gold, color: SLAB.ink, fontWeight: 600 }}>Fixed %</div>
          <div style={{ flex: 1, textAlign: 'center', fontSize: 11, padding: '6px 0', color: SLAB.muted }}>Store ladder</div>
        </div>
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {['70%', '75%', '80%', '85%', '90%'].map((c) => (
            <span key={c} style={{ fontSize: 11, fontFamily: SLAB.mono, padding: '4px 8px', borderRadius: 999, border: (c === '70%' ? '1.5px solid ' + SLAB.gold : '1px solid ' + SLAB.hair), color: c === '70%' ? SLAB.gold : SLAB.muted }}>{c}</span>
          ))}
        </div>
      </Card>

      <Kicker>Slabs</Kicker>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        {lines.map(([name, comp, buy, over]) => (
          <div key={name} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ width: 8, height: 8, borderRadius: 999, background: SLAB.pos }} />
            <span style={{ fontSize: 12 }}>{name}</span>
            <span style={{ marginLeft: 'auto', fontFamily: SLAB.mono, fontSize: 11, color: SLAB.muted }}>{comp}</span>
            <span style={{ fontFamily: SLAB.mono, fontSize: 12, fontWeight: 600, color: over ? SLAB.gold : SLAB.text }}>{buy}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ---- 04 · Offer -----------------------------------------------------------
function OfferScreen() {
  const lines: [string, string][] = [
    ['PSA 10 · 12345678', '$131'],
    ['PSA 9 · 0098761234', '$67'],
    ['PSA 10 · 4012998877', '$60'],
  ];
  return (
    <div style={screenWrap}>
      <div>
        <Kicker>Vendor</Kicker>
        <div style={{ fontFamily: SLAB.serif, fontSize: 22, letterSpacing: -0.4 }}>Mike&apos;s Card Shop</div>
      </div>
      <Card>
        <Kicker>Offer total</Kicker>
        <div style={{ fontFamily: SLAB.serif, fontSize: 38, letterSpacing: -1, lineHeight: 1, marginTop: 4 }}>$1,240</div>
        <div style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim, marginTop: 4 }}>9 lines · 70% margin</div>
      </Card>
      <Kicker>Lines</Kicker>
      <Card>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
          {lines.map(([l, v]) => (
            <div key={l} style={{ display: 'flex', alignItems: 'center' }}>
              <span style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.muted }}>{l}</span>
              <span style={{ marginLeft: 'auto', fontFamily: SLAB.mono, fontSize: 13, fontWeight: 600 }}>{v}</span>
            </div>
          ))}
        </div>
      </Card>
      <Card>
        <Kicker>Payment</Kicker>
        <div style={{ display: 'flex', gap: 4, background: SLAB.elev2, borderRadius: 10, padding: 3, margin: '8px 0 6px' }}>
          {['cash', 'check', 'digital'].map((m) => (
            <div key={m} style={{ flex: 1, textAlign: 'center', fontSize: 11, padding: '6px 0', borderRadius: 8, background: m === 'cash' ? SLAB.gold : 'transparent', color: m === 'cash' ? SLAB.ink : SLAB.muted, fontWeight: m === 'cash' ? 600 : 400 }}>{m}</div>
          ))}
        </div>
        <div style={{ fontSize: 11, color: SLAB.dim, border: '1px solid ' + SLAB.hair, borderRadius: 8, padding: '8px 10px' }}>Reference (check #, Venmo handle, …)</div>
      </Card>
      <div style={{ marginTop: 'auto', textAlign: 'center', background: SLAB.gold, color: SLAB.ink, fontWeight: 600, fontSize: 13, padding: '12px 0', borderRadius: 10 }}>Mark paid</div>
    </div>
  );
}

// ---- 05 · Paid ------------------------------------------------------------
function PaidScreen() {
  const lines: [string, string, string][] = [
    ['Charizard #4', 'Base Set · PSA 10', '$131'],
    ['Blastoise #2', 'Base Set · PSA 9', '$67'],
    ['Venusaur #15', 'Base Set · PSA 10', '$60'],
  ];
  return (
    <div style={screenWrap}>
      <div>
        <Kicker>Receipt</Kicker>
        <div style={{ fontFamily: SLAB.serif, fontSize: 22, letterSpacing: -0.4 }}>Mike&apos;s Card Shop</div>
        <div style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim, marginTop: 2 }}>Jun 7, 2026 at 2:14 PM</div>
      </div>
      <Card>
        <Kicker>Total</Kicker>
        <div style={{ fontFamily: SLAB.serif, fontSize: 38, letterSpacing: -1, lineHeight: 1, marginTop: 4 }}>$1,240</div>
        <div style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim, marginTop: 4 }}>cash</div>
      </Card>
      <Kicker>Lines</Kicker>
      <Card>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {lines.map(([name, sub, v]) => (
            <div key={name} style={{ display: 'flex', alignItems: 'center' }}>
              <div>
                <div style={{ fontSize: 13 }}>{name}</div>
                <div style={{ fontFamily: SLAB.mono, fontSize: 11, color: SLAB.dim }}>{sub}</div>
              </div>
              <span style={{ marginLeft: 'auto', fontFamily: SLAB.mono, fontSize: 13, fontWeight: 600 }}>{v}</span>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}

// ---- dispatcher -----------------------------------------------------------
export function FlowScreen({ step }: { step: number }) {
  switch (step) {
    case 0: return <ScanScreen />;
    case 1: return <CompScreen />;
    case 2: return <MarginScreen />;
    case 3: return <OfferScreen />;
    case 4: return <PaidScreen />;
    default: return <ScanScreen />;
  }
}
