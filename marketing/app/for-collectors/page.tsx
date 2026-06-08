import type { Metadata } from 'next';
import { PageShell, PageHero } from '@/components/marketing/page-shell';
import { AudienceBody, type AudiencePoint } from '@/components/marketing/audience-page';
import { FinalCta } from '@/components/marketing/final-cta';

export const metadata: Metadata = {
  title: 'Slabbist for collectors',
  description:
    'Pre-grade your own cards, track market movers, and comp any slab against real sales today. A collector marketplace is planned.',
};

const POINTS: AudiencePoint[] = [
  {
    icon: 'gauge',
    title: 'Pre-grade your own cards',
    blurb:
      'Get a PSA-equivalent grade estimate and centering read before you spend on a submission. Available today.',
  },
  {
    icon: 'chart',
    title: 'Real comps and market movers',
    blurb:
      'The same comp engine card shops use. See what the last 30 days of sales look like on the exact card you are eyeing. Available today.',
  },
  {
    icon: 'zap',
    title: 'Find the raw cards worth grading',
    blurb:
      'See which raw cards turn a profit after the grading fee, ranked by how much you make on a PSA 10. Available today.',
  },
  {
    icon: 'lock',
    title: 'Escrow and inspection window (planned)',
    blurb:
      'The planned marketplace will hold payment until the card arrives and you have had time to inspect it.',
  },
  {
    icon: 'tag',
    title: 'List your slabs (planned)',
    blurb:
      'List your cert-verified slabs when the marketplace opens. Every sale covered by escrow.',
  },
  {
    icon: 'shield',
    title: 'Cert-verified listings (planned)',
    blurb:
      'Every slab will be checked against the grader database before it goes live. No mismatched certs, no swapped slabs.',
  },
];

export default function ForCollectorsPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="For collectors"
        title="Grade smarter today. Sell fairer tomorrow."
        italicize="fairer"
        subtitle="Pre-grade your own cards, watch the movers, and comp any slab against real sales right now. A marketplace with escrow and cert verification is planned."
      />
      <AudienceBody
        pain="You love the hobby but hate selling: platforms that take a cut, swapped slabs, and no protection when a deal goes wrong."
        shift="Use Slabbist today to grade, comp, and track the market. When the marketplace opens, list your slabs with escrow and cert verification on every sale."
        points={POINTS}
        ctaLabel="Join the waitlist"
        waitlistAudience="collector"
      />
      <FinalCta />
    </PageShell>
  );
}
