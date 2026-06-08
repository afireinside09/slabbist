import { SLAB } from '@/lib/tokens';
import { FlowScreen } from './flow-screens';
import { PreGradeScreen, MarketScreen } from './feature-screens';
import { FeatureDeepDive } from './feature-deep-dive';

export function FeatureSections() {
  return (
    <>
      <section id="features" style={{ padding: 'clamp(84px, 11vw, 120px) 0 0', borderTop: '1px solid ' + SLAB.hair }}>
        <div className="slab-container" style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
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
            Every part, in depth
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
            Everything the counter needs. Nothing it doesn&apos;t.
          </h2>
          <p style={{ fontSize: 16, color: SLAB.muted, lineHeight: 1.6, maxWidth: 620, margin: 0 }}>
            Here is every piece that gets a stack scanned, priced, offered, and closed — and how each one
            actually works.
          </p>
        </div>
      </section>

      <FeatureDeepDive
        flip={false}
        eyebrow="Capture"
        title="Get the whole stack into the app, fast."
        paragraphs={[
          "Point the camera at a slab. It reads the cert number off the label — PSA, BGS, CGC, SGC, or TAG — and pulls the card's identity and population. Hold the phone or set it on a stand and feed the stack; the frame stays locked, so you are not waiting on focus between cards. A good run clears about 30 slabs a minute.",
          "Label scratched or hit by glare? Two taps to type the cert by hand. No signal? Scans queue on the device and sync the moment you are back online. Dead venue Wi-Fi never stops a buy.",
        ]}
        example="Scan a stack of 12. Each row fills in with its comp as the lookups land — pending rows show a badge until they do."
        screen={<FlowScreen step={0} />}
      />

      <FeatureDeepDive
        flip
        eyebrow="Comp engine"
        title="A real price, and the sales behind it."
        paragraphs={[
          "Every price is the middle of recent eBay sold listings, with the obvious outliers filtered out. Tap any comp to open the exact sales it came from — date, grade, and price — so you can show the seller where the number comes from.",
          "Each comp carries a confidence score. Thin sale counts, wide spreads, and stale data pull it down, so you know when to lean on the number and when to be careful. You also get the price at every grade, from PSA 7 to 10 plus CGC, BGS, and SGC 10, and how the price moved over 7, 30, and 90 days.",
        ]}
        example="Charizard, Base Set, PSA 10 — 14 recent sales → $188, range $175–$210, confidence High."
        screen={<FlowScreen step={1} />}
      />

      <FeatureDeepDive
        flip={false}
        eyebrow="Pre-grade"
        title="Grade the raw card before you pay for it."
        paragraphs={[
          "Frame a raw card and Slabbist estimates the grade it would come back as — a composite, plus sub-grades for centering, corners, edges, and surface. A confidence score tells you how far to trust it.",
          "Centering is the easy thing to get wrong, so you measure it yourself: drag the guides or tap an edge to snap them, and read the exact left/right and top/bottom ratios. Both photos and the reasoning are saved, so you can see later exactly why a card scored the way it did.",
        ]}
        example="Raw Charizard → estimated PSA 9.5. Centering 55/45, corners 9, edges 9.5, surface 10."
        screen={<PreGradeScreen />}
      />

      <FeatureDeepDive
        flip
        eyebrow="Market intel"
        title="See what's moving, and what's worth grading."
        paragraphs={[
          "Movers ranks the top gainers and losers for any set and price band, English or Japanese, each with a 30-day trend. Know what is climbing before you make an offer — and what is cooling before you get stuck with it.",
          "Grade gains ranks raw cards by the profit you would make grading them to a PSA 10, after the fee. Set your real submission fee and the numbers update on the spot, so the only cards you chase are the ones worth the wait.",
        ]}
        example="Raw $4 → PSA 10 $185. After a $25 grading fee, that is $156 of upside."
        screen={<MarketScreen />}
      />

      <FeatureDeepDive
        flip={false}
        eyebrow="At the counter"
        title="From a stack to a signed-off offer."
        paragraphs={[
          "Set your buy-price rules once — what you pay at each price band. Every slab in the lot gets a buy price from its comp automatically, and you can override any single line by hand. The prices lock onto the offer the moment you present it.",
          "Roll the lot into one offer: total, per-slab lines, payment method, and reference. Attach the vendor from your file in two taps. Mark it paid and it drops into your ledger. Every lot tracks its own state — drafting, priced, presented, accepted, paid — and paid lots lock so a closed buy cannot be changed.",
        ]}
        example="9 lines at 70% of comp → $1,240 total, paid by cash."
        screen={<FlowScreen step={3} />}
      />

      <FeatureDeepDive
        flip
        eyebrow="Back office"
        title="Everything stays clean after the buy."
        paragraphs={[
          "Every paid lot becomes a permanent receipt — vendor, total, payment method, timestamp. Need to undo one? Void it with a reason; the audit trail stays intact.",
          "Scans, edits, prices, and offers save on the device first and sync through a background queue, so nothing is lost when the Wi-Fi quits. Any failed sync surfaces in a sheet you can retry. Your store's data is scoped to your account on the server — no other shop can see your numbers.",
        ]}
        example="Receipt — Mike's Card Shop, $1,240, cash, Jun 7 2026. Locked."
        screen={<FlowScreen step={4} />}
      />

      <IntegrationsSection />
    </>
  );
}

function IntegrationsSection() {
  const rows: { name: string; what: string }[] = [
    { name: 'eBay', what: 'Recent sold listings feed the comp engine. Every comp tap links to the actual eBay sales.' },
    { name: 'TCGplayer', what: 'Raw card pricing and product links for non-graded comps.' },
    { name: 'PSA', what: 'Cert lookups and card identity for graded slabs.' },
    { name: 'PSA / BGS / CGC / SGC / TAG', what: 'The camera reads the cert number and grade off every major grader.' },
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
          The tools you already use. More coming.
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
              <div style={{ fontFamily: SLAB.serif, fontSize: 22, letterSpacing: -0.4 }}>{r.name}</div>
              <div style={{ fontSize: 14, color: SLAB.muted, lineHeight: 1.55 }}>{r.what}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
