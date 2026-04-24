import { SLAB } from '@/lib/tokens';
import { SlabLogo } from '@/components/slab-logo';

type Link = { label: string; href: string };
type Col = { h: string; links: Link[] };

const COLS: Col[] = [
  {
    h: 'Product',
    links: [
      { label: 'Features', href: '/features' },
      { label: 'How it works', href: '/#how-it-works' },
      { label: 'Pricing', href: '/#pricing' },
      { label: 'Changelog', href: '/changelog' },
    ],
  },
  {
    h: "Who it's for",
    links: [
      { label: 'Card shops', href: '/for-shops' },
      { label: 'Show vendors', href: '/for-vendors' },
      { label: 'Collectors', href: '/for-collectors' },
    ],
  },
  {
    h: 'Company',
    links: [
      { label: 'About', href: '/about' },
      { label: 'Press', href: '/press' },
      { label: 'Contact', href: '/contact' },
    ],
  },
  {
    h: 'Legal',
    links: [
      { label: 'Privacy', href: '/privacy' },
      { label: 'Terms', href: '/terms' },
      { label: 'Security', href: '/security' },
    ],
  },
];

export function Footer() {
  return (
    <footer
      style={{
        borderTop: '1px solid ' + SLAB.hair,
        padding: '56px 0 36px',
        background: SLAB.surface,
      }}
    >
      <div className="slab-container" style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
            gap: 36,
            marginBottom: 48,
          }}
        >
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 18 }}>
              <SlabLogo size={30} title="Slabbist" />
              <span style={{ fontWeight: 500, fontSize: 16 }}>Slabbist</span>
            </div>
            <div
              style={{
                fontSize: 14,
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
                  fontSize: 12,
                  letterSpacing: 1.2,
                  textTransform: 'uppercase',
                  color: SLAB.dim,
                  marginBottom: 16,
                  fontWeight: 600,
                }}
              >
                {c.h}
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {c.links.map((l) => (
                  <a
                    key={l.label}
                    href={l.href}
                    style={{ fontSize: 13, color: SLAB.text, textDecoration: 'none' }}
                  >
                    {l.label}
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
          <div style={{ fontSize: 12, color: SLAB.muted, fontFamily: SLAB.mono, lineHeight: 1.5 }}>
            © 2026 Slabbist Inc. · Not affiliated with The Pokémon Company, PSA, BGS, CGC, SGC, or TAG.
          </div>
          <div style={{ display: 'flex', gap: 14, alignItems: 'center', color: SLAB.muted }}>
            <a
              href="mailto:hello@slabbist.com"
              style={{ color: SLAB.muted, fontSize: 12, textDecoration: 'none' }}
            >
              hello@slabbist.com
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
}
