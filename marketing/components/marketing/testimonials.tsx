import { SLAB } from '@/lib/tokens';

const QUOTES = [
  {
    q: "Our associates used to burn 4 hours on a 30-slab stack. Now it's under ten minutes and every number is backed by actual solds.",
    who: 'Marcus Leighton',
    role: 'Owner · Third Street Cards',
    city: 'Portland, OR',
  },
  {
    q: 'The vendor database alone was worth it. I know what I paid them last show, what cards they pushed heavy on, and whether their cert numbers line up.',
    who: 'Priya Vance',
    role: 'Buyer · Summit Hobby',
    city: 'San Diego, CA',
  },
  {
    q: 'I work the Tampa show solo. Bulk scan on a tripod means I can talk to the seller instead of squinting at a phone.',
    who: 'Devin Okafor',
    role: 'Independent vendor',
    city: 'Tampa, FL',
  },
];

export function Testimonials() {
  return (
    <section
      style={{
        padding: '140px 0',
        borderTop: '1px solid ' + SLAB.hair,
        position: 'relative',
      }}
    >
      <div style={{ maxWidth: 1180, margin: '0 auto', padding: '0 32px' }}>
        <div
          style={{
            fontSize: 11,
            letterSpacing: 2.4,
            textTransform: 'uppercase',
            color: SLAB.gold,
            marginBottom: 20,
            fontWeight: 500,
          }}
        >
          From the counter
        </div>
        <h2
          style={{
            fontFamily: SLAB.serif,
            fontSize: 'clamp(40px, 5vw, 64px)',
            fontWeight: 400,
            letterSpacing: -1.5,
            lineHeight: 1.05,
            margin: '0 0 70px',
            maxWidth: 700,
          }}
        >
          Three stores. Two shows.{' '}
          <span style={{ fontStyle: 'italic', color: SLAB.gold }}>One app.</span>
        </h2>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(3, 1fr)',
            gap: 20,
          }}
        >
          {QUOTES.map((q) => (
            <div
              key={q.who}
              style={{
                padding: 36,
                borderRadius: 20,
                background: SLAB.elev,
                border: '1px solid ' + SLAB.hair,
                display: 'flex',
                flexDirection: 'column',
                position: 'relative',
                overflow: 'hidden',
              }}
            >
              <div
                aria-hidden
                style={{
                  position: 'absolute',
                  top: 18,
                  right: 22,
                  fontFamily: SLAB.serif,
                  fontStyle: 'italic',
                  fontSize: 90,
                  color: SLAB.gold,
                  opacity: 0.15,
                  lineHeight: 1,
                }}
              >
                &ldquo;
              </div>
              <div
                style={{
                  fontFamily: SLAB.serif,
                  fontSize: 20,
                  letterSpacing: -0.3,
                  lineHeight: 1.35,
                  marginBottom: 28,
                  textWrap: 'pretty',
                }}
              >
                {q.q}
              </div>
              <div
                style={{
                  marginTop: 'auto',
                  paddingTop: 20,
                  borderTop: '1px solid ' + SLAB.hair,
                }}
              >
                <div style={{ fontSize: 14, fontWeight: 500, marginBottom: 2 }}>{q.who}</div>
                <div style={{ fontSize: 12, color: SLAB.muted }}>{q.role}</div>
                <div
                  style={{
                    fontSize: 11,
                    color: SLAB.dim,
                    marginTop: 4,
                    fontFamily: SLAB.mono,
                    letterSpacing: 0.3,
                  }}
                >
                  {q.city}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
