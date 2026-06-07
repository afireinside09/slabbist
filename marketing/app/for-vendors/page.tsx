import type { Metadata } from 'next';
import { PageShell, PageHero } from '@/components/marketing/page-shell';
import { AudienceBody, type AudiencePoint } from '@/components/marketing/audience-page';
import { FinalCta } from '@/components/marketing/final-cta';

export const metadata: Metadata = {
  title: 'Slabbist for show vendors',
  description:
    'Price a show-floor showcase, run buylists in your booth, and close offers without leaving your table. Works offline when the venue Wi-Fi quits.',
};

const POINTS: AudiencePoint[] = [
  {
    icon: 'reload',
    title: 'Offline queue',
    blurb:
      'Conference-center Wi-Fi drops at 11am. Scans keep stacking locally and comps fill in the moment signal returns — through an outbox that retries on its own.',
  },
  {
    icon: 'layers',
    title: 'Showcase in one pass',
    blurb:
      'Scan every slab in the case in minutes. Re-price the showcase on Sunday morning without redoing the work.',
  },
  {
    icon: 'chart',
    title: 'Movers before you buy',
    blurb:
      'See the top gainers and losers for the set in front of you, by price tier, English or Japanese. Know what is climbing before you make the offer.',
  },
  {
    icon: 'zap',
    title: 'Grade gains on the floor',
    blurb:
      'Spot the raw cards worth sending to PSA — ranked by upside to a 10, net of the grading fee you actually pay.',
  },
  {
    icon: 'receipt',
    title: 'Buylist from your phone',
    blurb:
      'A vendor wants to sell you a PSA 10. Scan, apply the lot rule, present the offer. No laptop, no spreadsheet.',
  },
  {
    icon: 'gauge',
    title: 'Pre-grade a raw on the spot',
    blurb:
      'Estimate a raw card’s grade and centering at the table, so a borderline buy is a decision, not a gamble.',
  },
];

export default function ForVendorsPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="For show vendors"
        title="Price the booth. Close the lot. Catch the flight."
        italicize="the lot"
        subtitle="Slabbist is built for the show floor — bulk capture, offline-first sync, and offer sheets ready to present right from your phone."
      />
      <AudienceBody
        pain="You fly into a weekend show with a case full of slabs, a buylist in your head, and a Wi-Fi network that dies every two hours. The numbers never quite agree with your books on Monday."
        shift="One app runs the booth: pre-grading raws, pricing the case, reading the movers, and closing buylist offers — online or off."
        points={POINTS}
        ctaLabel="Join the vendor waitlist"
        waitlistAudience="store"
      />
      <FinalCta />
    </PageShell>
  );
}
