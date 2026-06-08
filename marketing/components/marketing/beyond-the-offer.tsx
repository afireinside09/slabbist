import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';

type Beat = { icon: IconName; kicker: string; title: string; body: string };

const BEATS: Beat[] = [
  { icon: 'gauge', kicker: 'Pre-grade', title: 'Grade the walk-in first', body: 'Camera-grade a raw card to a PSA-equivalent composite with sub-grades before you commit a dollar to submission.' },
  { icon: 'chart', kicker: 'Movers', title: 'See where the market’s heading', body: 'Top gainers and losers by set and price tier, English or Japanese, with a 30-day trend on every card.' },
  { icon: 'zap', kicker: 'Grade gains', title: 'Find the cards worth sending in', body: 'Raw cards ranked by their upside to a PSA 10, net of the grading fee — dial the fee to your submission tier.' },
];

export function BeyondTheOffer() {
  return (
    <section style={{ padding: 'clamp(84px, 11vw, 120px) 0', borderTop: '1px solid ' + SLAB.hair }}>
      <div style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
        <div style={{ marginBottom: 'clamp(40px, 5vw, 56px)', maxWidth: 620 }}>
          <div style={{ fontSize: 12, letterSpacing: 1.6, textTransform: 'uppercase', color: SLAB.gold, marginBottom: 18, fontWeight: 500 }}>Beyond the offer</div>
          <h2 style={{ fontFamily: SLAB.serif, fontSize: 'clamp(36px, 4.5vw, 52px)', fontWeight: 400, letterSpacing: -1.2, lineHeight: 1.05, margin: 0 }}>
            The market intelligence around every buy.
          </h2>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: 1, background: SLAB.hair, border: '1px solid ' + SLAB.hair, borderRadius: 16, overflow: 'hidden' }}>
          {BEATS.map((b) => (
            <div key={b.kicker} style={{ padding: '28px 26px 32px', background: SLAB.ink, display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <Icon name={b.icon} size={17} sw={1.8} color={SLAB.gold} />
                <div style={{ fontSize: 11, letterSpacing: 1.4, textTransform: 'uppercase', color: SLAB.dim, fontWeight: 500 }}>{b.kicker}</div>
              </div>
              <div style={{ fontFamily: SLAB.serif, fontSize: 24, letterSpacing: -0.4 }}>{b.title}</div>
              <div style={{ fontSize: 14, color: SLAB.muted, lineHeight: 1.55 }}>{b.body}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
