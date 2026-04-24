import type { Metadata } from 'next';
import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';
import { PageShell, PageHero } from '@/components/marketing/page-shell';
import { FeatureRow } from '@/components/marketing/feature-row';
import { FinalCta } from '@/components/marketing/final-cta';

export const metadata: Metadata = {
  title: 'Features · Slabbist',
  description:
    'Everything Slabbist does for card shops, show vendors, and collectors. Bulk scanning, cert OCR, a comp engine trained on real sales, and role-based margin rules.',
};

type FeatureCard = {
  icon: IconName;
  title: string;
  blurb: string;
};

const CAPTURE: FeatureCard[] = [
  {
    icon: 'scan',
    title: 'Cert OCR for every major grader',
    blurb:
      'PSA, BGS, CGC, SGC, and TAG. The app detects the grader, reads the cert number, and pulls the population record. Scratched slabs fall back to a two-tap manual entry.',
  },
  {
    icon: 'layers',
    title: 'Bulk queue at 30 slabs a minute',
    blurb:
      'Hold the phone in-hand or set it on a stand and feed the stack. The capture frame is tuned so you never wait for focus between cards.',
  },
  {
    icon: 'reload',
    title: 'Offline-first by default',
    blurb:
      'Scans and edits are captured locally and sync when the connection returns. The venue Wi-Fi dropping out will not stop your buy.',
  },
  {
    icon: 'card',
    title: 'Raw card recognition',
    blurb:
      'Want to comp a raw NM? Point the camera and Slabbist matches the title, set, and number against the TCG database — no slab required.',
  },
];

const COMP_ENGINE: FeatureCard[] = [
  {
    icon: 'chart',
    title: 'Median of recent eBay sales',
    blurb:
      'Every price is a rolling median of recent sold comps, filtered for outliers. Tap any price to open the actual sales it was built from.',
  },
  {
    icon: 'bolt',
    title: '7, 30, 90 day velocity',
    blurb:
      'Is the card heating up or bleeding out? Trend lines show velocity and direction so you can price with confidence, not guesswork.',
  },
  {
    icon: 'sparkle',
    title: 'Confidence scoring',
    blurb:
      'Slabbist tells you how reliable each comp is. Thin comp counts, wide spreads, and stale data all lower the confidence score so you know when to lean in — and when not to.',
  },
  {
    icon: 'flag',
    title: 'Event-aware modifiers',
    blurb:
      'Spiking on release weekend? Bleeding in a correction? Event mode applies a time-boxed modifier so your lot pricing reflects what the market is doing right now.',
  },
];

const COUNTER: FeatureCard[] = [
  {
    icon: 'shield',
    title: 'Role-based visibility',
    blurb:
      'Owners see comp, cost, and margin. Associates see the buy number only. Enforced at the database — not just hidden in the UI.',
  },
  {
    icon: 'tag',
    title: 'Margin rules you actually understand',
    blurb:
      'Per-grader, per-set, and per-price-band modifiers. Preview the buy number before you commit, and keep a history of every rule change.',
  },
  {
    icon: 'receipt',
    title: 'Offer sheets in a tap',
    blurb:
      'Apply your margin, attach a vendor, and print or email a one-page offer. The line items match what you scanned, so nothing gets retyped.',
  },
  {
    icon: 'signature',
    title: 'On-device signature capture',
    blurb:
      'Flip the iPad and capture a seller signature the moment they accept. The signed PDF lives with the lot so you can retrieve it at any point.',
  },
];

const BACK_OFFICE: FeatureCard[] = [
  {
    icon: 'users',
    title: 'Vendor database',
    blurb:
      'Track who sold you what, at which price, with what grade mix. Lots are searchable by vendor, event, or date range.',
  },
  {
    icon: 'store',
    title: 'Multi-location ready',
    blurb:
      'Run it at one counter or ten. Role and visibility rules follow the user, not the device.',
  },
  {
    icon: 'lock',
    title: 'Buy price never leaves the role',
    blurb:
      'The buy number is resolved server-side and only returned to users whose role permits it. A screenshot cannot leak what the API never sent.',
  },
  {
    icon: 'zap',
    title: 'Exports that work with your books',
    blurb:
      'CSV and PDF exports for offer sheets, buy history, and margin reports. Import into QuickBooks, Square, or whatever your accountant expects.',
  },
];

export default function FeaturesPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Features"
        title="Everything the counter needs. Nothing it doesn't."
        italicize="counter"
        subtitle="Slabbist is purpose-built for the moment a stack of slabs hits your counter. Here is every piece that gets it priced, offered, and closed."
      />

      <Section
        id="capture"
        eyebrow="Capture"
        title="Get the slab into the app in one second."
        cards={CAPTURE}
      />

      <FeatureRow />

      <Section
        id="comps"
        eyebrow="Comp engine"
        title="Real prices from real sales."
        cards={COMP_ENGINE}
      />

      <Section
        id="counter"
        eyebrow="At the counter"
        title="A buy that does not leak."
        cards={COUNTER}
      />

      <Section
        id="back-office"
        eyebrow="Back office"
        title="Everything you need after the buy closes."
        cards={BACK_OFFICE}
      />

      <IntegrationsSection />

      <FinalCta />
    </PageShell>
  );
}

function Section({
  id,
  eyebrow,
  title,
  cards,
}: {
  id: string;
  eyebrow: string;
  title: string;
  cards: FeatureCard[];
}) {
  return (
    <section
      id={id}
      style={{
        padding: 'clamp(72px, 9vw, 104px) 0',
        borderTop: '1px solid ' + SLAB.hair,
      }}
    >
      <div className="slab-container" style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'end',
            marginBottom: 'clamp(40px, 5vw, 56px)',
            gap: 40,
            flexWrap: 'wrap',
          }}
        >
          <div>
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
                fontSize: 'clamp(36px, 4.5vw, 52px)',
                fontWeight: 400,
                letterSpacing: -1.2,
                lineHeight: 1.05,
                margin: 0,
                maxWidth: 620,
              }}
            >
              {title}
            </h2>
          </div>
        </div>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))',
            gap: 1,
            background: SLAB.hair,
            border: '1px solid ' + SLAB.hair,
            borderRadius: 16,
            overflow: 'hidden',
          }}
        >
          {cards.map((c) => (
            <div
              key={c.title}
              style={{
                padding: '28px 26px 32px',
                background: SLAB.ink,
                display: 'flex',
                flexDirection: 'column',
                gap: 16,
              }}
            >
              <div
                style={{
                  width: 40,
                  height: 40,
                  borderRadius: 10,
                  background: SLAB.elev2,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: SLAB.gold,
                }}
              >
                <Icon name={c.icon} size={18} sw={1.8} />
              </div>
              <div>
                <div
                  style={{
                    fontSize: 17,
                    fontWeight: 500,
                    letterSpacing: -0.3,
                    marginBottom: 8,
                  }}
                >
                  {c.title}
                </div>
                <div style={{ fontSize: 14, color: SLAB.muted, lineHeight: 1.55 }}>
                  {c.blurb}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function IntegrationsSection() {
  const rows: { name: string; what: string }[] = [
    { name: 'eBay', what: 'Sold listings feed the comp engine. Affiliate links on every comp tap.' },
    { name: 'TCGplayer', what: 'Raw card pricing and affiliate links for non-graded comps.' },
    { name: 'PSA / BGS / CGC / SGC / TAG', what: 'Cert lookups, population reports, and serial validation.' },
    { name: 'Square & Shopify', what: 'Push priced lots into your POS or online store in one click. (Beta cohort.)' },
    { name: 'QuickBooks', what: 'CSV exports mapped to your chart of accounts for easy import.' },
  ];

  return (
    <section
      id="integrations"
      style={{
        padding: 'clamp(72px, 9vw, 104px) 0',
        borderTop: '1px solid ' + SLAB.hair,
      }}
    >
      <div className="slab-container" style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
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
          Integrations
        </div>
        <h2
          style={{
            fontFamily: SLAB.serif,
            fontSize: 'clamp(36px, 4.5vw, 52px)',
            fontWeight: 400,
            letterSpacing: -1.2,
            lineHeight: 1.05,
            margin: '0 0 40px',
            maxWidth: 680,
          }}
        >
          The tools you already use, already wired up.
        </h2>

        <div
          style={{
            border: '1px solid ' + SLAB.hair,
            borderRadius: 16,
            overflow: 'hidden',
          }}
        >
          {rows.map((r, i) => (
            <div
              key={r.name}
              style={{
                display: 'grid',
                gridTemplateColumns: 'minmax(220px, 280px) 1fr',
                gap: 24,
                padding: '22px 26px',
                borderTop: i === 0 ? 'none' : '1px solid ' + SLAB.hair,
                alignItems: 'center',
              }}
            >
              <div
                style={{
                  fontFamily: SLAB.serif,
                  fontSize: 22,
                  letterSpacing: -0.4,
                }}
              >
                {r.name}
              </div>
              <div style={{ fontSize: 14, color: SLAB.muted, lineHeight: 1.55 }}>{r.what}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
