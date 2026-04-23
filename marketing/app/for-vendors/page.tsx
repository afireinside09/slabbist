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
      'Conference-center Wi-Fi drops at 11am. Scans keep stacking up locally and comps fill in the moment signal returns.',
  },
  {
    icon: 'layers',
    title: 'Showcase in one pass',
    blurb:
      'Scan every slab in the case in under ten minutes. Re-price the showcase on Sunday morning without redoing the work.',
  },
  {
    icon: 'bolt',
    title: 'Event-aware pricing',
    blurb:
      'Release weekend modifier, regional event lift, or a correction applied once and reflected across the whole booth.',
  },
  {
    icon: 'receipt',
    title: 'Buylist from your phone',
    blurb:
      'A vendor wants to sell you a PSA 10. Scan, apply the lot rule, hand them a printed offer. No laptop, no spreadsheet.',
  },
  {
    icon: 'signature',
    title: 'Signature-on-glass',
    blurb:
      'Flip the iPad and close the buy on the spot. The signed PDF lives with the lot in your account, not a stack of paper at the bottom of a tote.',
  },
  {
    icon: 'chart',
    title: 'Export everything on Monday',
    blurb:
      'CSV exports of every lot, every comp, every margin rule applied. Reconcile the show the way your books expect it.',
  },
];

export default function ForVendorsPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="For show vendors"
        title="Price the booth. Close the lot. Catch the flight."
        italicize="the lot"
        subtitle="Slabbist is built for the show floor — bulk capture, offline-first sync, and offer sheets that print on whatever printer the promoter brought."
      />
      <AudienceBody
        pain="You fly into a weekend show with a case full of slabs, a buylist in your head, and a Wi-Fi network that dies every two hours. The numbers never quite agree with your books on Monday."
        shift="One app runs the booth: pricing the case, scanning buylist offers, and exporting a clean reconciliation when you land."
        points={POINTS}
        ctaLabel="Join the vendor waitlist"
        waitlistAudience="store"
      />
      <FinalCta />
    </PageShell>
  );
}
