import { SLAB } from '@/lib/tokens';

export function Pricing() {
  return (
    <section
      id="pricing"
      style={{
        padding: 'clamp(84px, 11vw, 120px) 0',
        borderTop: '1px solid ' + SLAB.hair,
        position: 'relative',
      }}
    >
      <div
        className="slab-container"
        style={{ maxWidth: 760, margin: '0 auto', padding: '0 24px', textAlign: 'center' }}
      >
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
          Pricing
        </div>
        <h2
          style={{
            fontFamily: SLAB.serif,
            fontSize: 'clamp(40px, 5vw, 64px)',
            fontWeight: 400,
            letterSpacing: -1.5,
            lineHeight: 1.05,
            margin: '0 0 20px',
          }}
        >
          Free to download. No subscriptions.
        </h2>
        <p
          style={{
            fontSize: 16,
            color: SLAB.muted,
            maxWidth: 620,
            margin: '0 auto',
            lineHeight: 1.6,
          }}
        >
          Slabbist is free. We earn affiliate commissions when you tap through to eBay or TCGplayer
          and buy something on those platforms. Nothing comes out of your pocket.
        </p>
        <div
          style={{
            fontSize: 13,
            color: SLAB.muted,
            maxWidth: 560,
            margin: '32px auto 0',
            lineHeight: 1.65,
          }}
        >
          No subscriptions. No seat fees. No locked features. If we ever charge for something
          specific, we'll say so up front, and it will still be optional.
        </div>
      </div>
    </section>
  );
}
