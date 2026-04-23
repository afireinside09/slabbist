import { SLAB } from '@/lib/tokens';
import { Icon } from '@/components/icon';

const COLS = [
  { h: 'Product', links: ['Overview', 'Bulk scan', 'Comp engine', 'Vendor DB', 'Changelog'] },
  { h: 'Stores', links: ['For shops', 'For show vendors', 'For solo buyers', 'Customer stories', 'Onboarding'] },
  { h: 'Company', links: ['About', 'Careers', 'Press', 'Contact', 'Brand kit'] },
  { h: 'Legal', links: ['Privacy', 'Terms', 'Security', 'DMCA', 'Status'] },
];

export function Footer() {
  return (
    <footer
      style={{
        borderTop: '1px solid ' + SLAB.hair,
        padding: '60px 0 40px',
        background: SLAB.surface,
      }}
    >
      <div style={{ maxWidth: 1180, margin: '0 auto', padding: '0 32px' }}>
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: '1.5fr repeat(4, 1fr)',
            gap: 40,
            marginBottom: 60,
          }}
        >
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 18 }}>
              <div
                style={{
                  width: 30,
                  height: 30,
                  borderRadius: 8,
                  background: `linear-gradient(135deg, ${SLAB.gold}, ${SLAB.goldDim})`,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontFamily: SLAB.serif,
                  fontStyle: 'italic',
                  fontWeight: 600,
                  color: SLAB.ink,
                  fontSize: 17,
                }}
              >
                S
              </div>
              <span style={{ fontWeight: 500, fontSize: 16 }}>Slabbist</span>
            </div>
            <div
              style={{
                fontSize: 13,
                color: SLAB.muted,
                maxWidth: 260,
                lineHeight: 1.55,
              }}
            >
              The iOS app for Pokémon hobby stores and vendors. Built in the Pacific Northwest.
            </div>
          </div>
          {COLS.map((c) => (
            <div key={c.h}>
              <div
                style={{
                  fontSize: 11,
                  letterSpacing: 1.5,
                  textTransform: 'uppercase',
                  color: SLAB.dim,
                  marginBottom: 18,
                  fontWeight: 600,
                }}
              >
                {c.h}
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {c.links.map((l) => (
                  <a
                    key={l}
                    href="#"
                    style={{ fontSize: 13, color: SLAB.text, textDecoration: 'none' }}
                  >
                    {l}
                  </a>
                ))}
              </div>
            </div>
          ))}
        </div>
        <div
          style={{
            borderTop: '1px solid ' + SLAB.hair,
            paddingTop: 28,
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            gap: 20,
            flexWrap: 'wrap',
          }}
        >
          <div style={{ fontSize: 12, color: SLAB.dim, fontFamily: SLAB.mono }}>
            © 2026 Slabbist Inc. · Not affiliated with The Pokémon Company, PSA, BGS, CGC, SGC, or TAG.
          </div>
          <div style={{ display: 'flex', gap: 14, alignItems: 'center', color: SLAB.muted }}>
            <a href="#" style={{ color: SLAB.muted, display: 'flex' }} aria-label="GitHub">
              <Icon name="github" size={16} />
            </a>
            <a href="#" style={{ color: SLAB.muted }}>
              X
            </a>
            <a href="#" style={{ color: SLAB.muted, fontSize: 12 }}>
              hello@slabbist.com
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
}
