import type { Metadata } from 'next';
import { SLAB } from '@/lib/tokens';
import { PageShell, PageHero } from '@/components/marketing/page-shell';

export const metadata: Metadata = {
  title: 'Press · Slabbist',
  description:
    'Press kit, boilerplate, and media contact for Slabbist, the iOS scanner for Pokémon hobby stores.',
};

export default function PressPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Press"
        title="If you cover the hobby, we'd love to talk."
        italicize="love to talk"
        subtitle="Everything you need to write about Slabbist — the what, the who, the how, and where to reach us."
      />

      <section
        style={{
          padding: 'clamp(40px, 6vw, 64px) 0',
          borderTop: '1px solid ' + SLAB.hair,
        }}
      >
        <div
          style={{
            maxWidth: 1180,
            margin: '0 auto',
            padding: '0 24px',
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
            gap: 24,
          }}
        >
          <Card label="Press contact" lines={['press@slabbist.com', 'We reply within one business day.']} cta={{ href: 'mailto:press@slabbist.com', label: 'Email press@' }} />
          <Card
            label="Boilerplate"
            lines={[
              'Slabbist is an iOS app that lets Pokémon hobby stores, show vendors, and collectors bulk-scan graded slabs and return real comps from recent sales. Founded in 2025 and based in the Pacific Northwest.',
            ]}
          />
          <Card
            label="Stats"
            lines={[
              '30 slabs per minute in the bulk queue',
              '14 seconds from scan to offer',
              '5 graders supported: PSA, BGS, CGC, SGC, TAG',
              'Free on iOS',
            ]}
          />
        </div>
      </section>

      <section
        style={{
          padding: 'clamp(56px, 8vw, 96px) 0',
          borderTop: '1px solid ' + SLAB.hair,
        }}
      >
        <div style={{ maxWidth: 820, margin: '0 auto', padding: '0 24px' }}>
          <h2
            style={{
              fontFamily: SLAB.serif,
              fontSize: 'clamp(28px, 3.5vw, 40px)',
              fontWeight: 400,
              letterSpacing: -0.8,
              lineHeight: 1.1,
              margin: '0 0 20px',
            }}
          >
            On naming and disclaimers
          </h2>
          <p style={{ fontSize: 16, color: SLAB.muted, lineHeight: 1.7, marginBottom: 16 }}>
            Slabbist is an independent, third-party tool. We are not affiliated with The Pokémon
            Company International, Nintendo, PSA, BGS, CGC, SGC, or TAG. All trademarks belong to
            their respective owners. If you need the disclaimer verbatim: <em>&quot;Slabbist is a
            third-party tool and is not affiliated with or endorsed by The Pokémon Company,
            Nintendo, or any grading company.&quot;</em>
          </p>
          <p style={{ fontSize: 16, color: SLAB.muted, lineHeight: 1.7 }}>
            High-resolution logos, screenshots, and a short factsheet are available on request —
            <a
              href="mailto:press@slabbist.com"
              style={{
                color: SLAB.gold,
                textDecoration: 'underline',
                textUnderlineOffset: 3,
                marginLeft: 4,
              }}
            >
              email press@slabbist.com
            </a>
            .
          </p>
        </div>
      </section>
    </PageShell>
  );
}

function Card({
  label,
  lines,
  cta,
}: {
  label: string;
  lines: string[];
  cta?: { href: string; label: string };
}) {
  return (
    <div
      style={{
        padding: 28,
        borderRadius: 20,
        background: SLAB.elev,
        border: '1px solid ' + SLAB.hair,
        display: 'flex',
        flexDirection: 'column',
        gap: 14,
      }}
    >
      <div
        style={{
          fontSize: 11,
          letterSpacing: 1.4,
          textTransform: 'uppercase',
          color: SLAB.dim,
          fontWeight: 600,
        }}
      >
        {label}
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {lines.map((l) => (
          <div key={l} style={{ fontSize: 14, color: SLAB.text, lineHeight: 1.55 }}>
            {l}
          </div>
        ))}
      </div>
      {cta && (
        <a
          href={cta.href}
          style={{
            marginTop: 'auto',
            fontSize: 13,
            color: SLAB.gold,
            textDecoration: 'underline',
            textUnderlineOffset: 3,
          }}
        >
          {cta.label} →
        </a>
      )}
    </div>
  );
}
