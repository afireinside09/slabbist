import type { Metadata } from 'next';
import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';
import { PageShell, PageHero } from '@/components/marketing/page-shell';
import { FeatureRow } from '@/components/marketing/feature-row';
import { FinalCta } from '@/components/marketing/final-cta';

export const metadata: Metadata = {
  title: 'Features · Slabbist',
  description:
    'Everything Slabbist does for card shops and show vendors. Bulk cert scanning, comps from real sales, on-device grade estimates, market movers, grade-gain arbitrage, and a margin ladder that prices every slab.',
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
    icon: 'layers',
    title: 'Per-grade price ladder',
    blurb:
      'See the going rate across the whole grade ladder — PSA 7 through 10, plus CGC, BGS, and SGC 10 — so a missing comp at one grade falls back to the nearest grade with real sales.',
  },
];

const COUNTER: FeatureCard[] = [
  {
    icon: 'tag',
    title: 'A margin ladder you actually understand',
    blurb:
      'Set buy percentages by price tier once. Every slab is priced against its comp automatically, and you can override any single buy price by hand. The ladder is snapshotted onto the offer the moment you present it.',
  },
  {
    icon: 'receipt',
    title: 'Offer sheet, ready to present',
    blurb:
      'Roll a lot into one offer: total, per-slab line items, and the payment method and reference. Mark it paid and it drops into your transaction ledger, frozen and audit-safe.',
  },
  {
    icon: 'users',
    title: 'Vendors on file',
    blurb:
      'Keep a registry of who you buy from — phone, email, Instagram, notes. Attach a vendor to a lot in two taps; archived vendors stay readable in history.',
  },
  {
    icon: 'reload',
    title: 'Lot workflow that tracks itself',
    blurb:
      'Drafting, priced, presented, accepted, paid, or voided — every lot carries its state, and paid lots lock so a closed buy cannot be edited out from under you.',
  },
];

const BACK_OFFICE: FeatureCard[] = [
  {
    icon: 'receipt',
    title: 'Transaction ledger',
    blurb:
      'Every paid lot becomes an immutable record — vendor, total, payment method, timestamp. Void with a reason if you have to; the audit trail stays intact.',
  },
  {
    icon: 'reload',
    title: 'Offline-first by design',
    blurb:
      'Scans, edits, prices, and offers are written locally first and synced in the background through an outbox. A failed write surfaces in a sheet you can retry — nothing is lost when the venue Wi-Fi quits.',
  },
  {
    icon: 'gauge',
    title: 'Grading history',
    blurb:
      'Every pre-grade estimate is saved with its photos, sub-grades, and reasoning. Star the keepers and filter your collection down to them.',
  },
  {
    icon: 'store',
    title: 'Built multi-tenant',
    blurb:
      'Your store’s data is scoped to your store and nobody else’s, enforced server-side. Run the buy desk knowing your numbers stay yours.',
  },
];

const PREGRADE: FeatureCard[] = [
  {
    icon: 'gauge',
    title: 'PSA-equivalent grade estimate',
    blurb:
      'Frame a raw card and Slabbist returns a composite grade with centering, corners, edges, and surface sub-grades — plus a confidence read so you know how far to trust it.',
  },
  {
    icon: 'crosshair',
    title: 'Centering tool that snaps to the edges',
    blurb:
      'Drag the guides or tap an inner edge to snap them, and read the exact L/R and T/B ratios. Settle a borderline centering call before you commit a dollar.',
  },
  {
    icon: 'card',
    title: 'Front and back, kept on file',
    blurb:
      'Each estimate stores both photos and the reasoning behind the grade, so you can revisit why a card scored the way it did.',
  },
];

const MARKET: FeatureCard[] = [
  {
    icon: 'chart',
    title: 'Movers by set and tier',
    blurb:
      'Top gainers and losers for any set and price band, English or Japanese, each with a 30-day trend. See what is heating up before you make the offer.',
  },
  {
    icon: 'zap',
    title: 'Grade gains arbitrage',
    blurb:
      'Raw cards ranked by their upside to a PSA 10, net of the grading fee. Dial the fee to your submission tier and the profit recalculates on the spot.',
  },
  {
    icon: 'sparkle',
    title: 'Comps with the receipts',
    blurb:
      'Headline price, range, sale count, trend, and a per-grade ladder — with the recent eBay solds behind every number and a TCGplayer link when there is one.',
  },
];

export default function FeaturesPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Features"
        title="Everything the counter needs. Nothing it doesn't."
        italicize="counter"
        subtitle="Slabbist is purpose-built for the moment a stack of slabs hits your counter. Here is every piece that gets it scanned, graded, priced, offered, and closed."
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
        id="pre-grade"
        eyebrow="Pre-grade"
        title="Grade the card before you buy it."
        cards={PREGRADE}
      />

      <Section
        id="market"
        eyebrow="Market intel"
        title="Know where the market is going."
        cards={MARKET}
      />

      <Section
        id="counter"
        eyebrow="At the counter"
        title="From stack to signed-off offer."
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
    { name: 'eBay', what: 'Recent sold listings feed the comp engine, with affiliate links on every comp tap.' },
    { name: 'TCGplayer', what: 'Raw card pricing and product links for non-graded comps.' },
    { name: 'PSA', what: 'Cert lookups and card identity resolution for graded slabs.' },
    { name: 'PSA / BGS / CGC / SGC / TAG', what: 'Cert OCR reads the label and grade off every major grader.' },
    { name: 'POS & accounting (planned)', what: 'Square, Shopify, and QuickBooks exports are on the roadmap, not shipping yet.' },
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
          The tools you already use — with more on the way.
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
