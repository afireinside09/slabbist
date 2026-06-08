import type { Metadata } from 'next';
import { PageShell, PageHero } from '@/components/marketing/page-shell';
import { AudienceBody, type AudiencePoint } from '@/components/marketing/audience-page';
import { FinalCta } from '@/components/marketing/final-cta';

export const metadata: Metadata = {
  title: 'Slabbist for show vendors',
  description:
    'Price your showcase, run buylists in your booth, and close offers right from your phone. Works offline when venue Wi-Fi quits.',
};

const POINTS: AudiencePoint[] = [
  {
    icon: 'reload',
    title: 'Works when Wi-Fi drops',
    blurb:
      'Conference Wi-Fi dies at 11am every show. Scans keep stacking locally and comps fill in the moment signal returns. Nothing gets lost.',
  },
  {
    icon: 'layers',
    title: 'Price the showcase in one pass',
    blurb:
      'Scan every slab in the case in minutes. Re-price on Sunday morning without starting over.',
  },
  {
    icon: 'chart',
    title: 'See the movers before you buy',
    blurb:
      'Top gainers and losers for the set in front of you, by price tier, English or Japanese. Know what is climbing before you make an offer.',
  },
  {
    icon: 'zap',
    title: 'Find the raw cards worth grading',
    blurb:
      'See which raw cards turn a profit after the PSA grading fee. Ranked by how much you make on a PSA 10. Set your actual submission fee and the numbers update.',
  },
  {
    icon: 'receipt',
    title: 'Buy from your phone',
    blurb:
      'Someone wants to sell you a PSA 10. Scan it, apply your buy-price rules, present the offer. No laptop, no spreadsheet.',
  },
  {
    icon: 'gauge',
    title: 'Pre-grade a raw on the spot',
    blurb:
      'Get a PSA-equivalent grade estimate and centering read at the table. Turn a borderline call into a real decision.',
  },
];

export default function ForVendorsPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="For show vendors"
        title="Price the booth. Close the lot. Catch the flight."
        italicize="the lot"
        subtitle="Slabbist is built for the show floor. Scan slabs in bulk, pull comps offline, and present an offer right from your phone."
      />
      <AudienceBody
        pain="You fly into a weekend show with a case full of slabs, a buylist in your head, and a Wi-Fi network that dies every two hours. The numbers never quite match your books on Monday."
        shift="One app runs the booth: pre-grading raws, pricing the case, checking the movers, and closing buys online or off."
        points={POINTS}
        ctaLabel="Join the waitlist"
        waitlistAudience="store"
      />
      <FinalCta />
    </PageShell>
  );
}
