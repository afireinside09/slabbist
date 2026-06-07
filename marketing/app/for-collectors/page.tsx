import type { Metadata } from 'next';
import { PageShell, PageHero } from '@/components/marketing/page-shell';
import { AudienceBody, type AudiencePoint } from '@/components/marketing/audience-page';
import { FinalCta } from '@/components/marketing/final-cta';

export const metadata: Metadata = {
  title: 'Slabbist for collectors',
  description:
    'Pre-grade your own cards, watch market movers, and comp any slab against real sales today. A fair marketplace with a 1% buyer fee is on the way.',
};

const POINTS: AudiencePoint[] = [
  {
    icon: 'gauge',
    title: 'Pre-grade your own cards',
    blurb:
      'Estimate a card’s PSA-equivalent grade and centering before you spend on a submission. Available today.',
  },
  {
    icon: 'chart',
    title: 'Market movers and real comps',
    blurb:
      'The same comp engine and gainers/losers stores use. See the last 30 days on the exact card you are eyeing. Available today.',
  },
  {
    icon: 'zap',
    title: 'Spot the grade-gain plays',
    blurb:
      'Find the raw cards worth grading, ranked by upside to a PSA 10 net of the fee. Available today.',
  },
  {
    icon: 'lock',
    title: 'Escrow + inspection window (planned)',
    blurb:
      'The coming marketplace will hold your money until the card arrives and you have had time to inspect it.',
  },
  {
    icon: 'tag',
    title: 'Zero seller fees (planned)',
    blurb:
      'No listing or commission fees. A 1% buyer fee will apply only at checkout; sellers net the sale price after payment processing.',
  },
  {
    icon: 'shield',
    title: 'Cert-verified listings (planned)',
    blurb:
      'Every slab will be cross-checked with the grader database before it goes live — no mismatched certs, no swapped slabs.',
  },
];

export default function ForCollectorsPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="For collectors"
        title="Grade smarter today. Sell fairer tomorrow."
        italicize="fairer"
        subtitle="Pre-grade your own cards, watch the movers, and comp any slab against real sales right now. A marketplace that doesn't punish selling — 1% buyer fee, zero seller fees — is on the way."
      />
      <AudienceBody
        pain="You love the hobby but hate the tax. A 13% final-value fee, 3% payment processing, and a promoted-listing fee on top means a $500 slab nets you $420 if you are lucky."
        shift="Use Slabbist today to grade, comp, and track the market. When the marketplace opens, list for free and keep what selling elsewhere takes from you."
        points={POINTS}
        ctaLabel="Join the collector waitlist"
        waitlistAudience="collector"
      />
      <FinalCta />
    </PageShell>
  );
}
