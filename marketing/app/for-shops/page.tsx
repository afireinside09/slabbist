import type { Metadata } from 'next';
import { PageShell, PageHero } from '@/components/marketing/page-shell';
import { AudienceBody, type AudiencePoint } from '@/components/marketing/audience-page';
import { FinalCta } from '@/components/marketing/final-cta';

export const metadata: Metadata = {
  title: 'Slabbist for card shops',
  description:
    'Slabbist turns the counter of your card shop into a bulk-scanning, comp-resolving buy desk. Free on iOS.',
};

const POINTS: AudiencePoint[] = [
  {
    icon: 'scan',
    title: 'Counter-grade capture',
    blurb:
      'Set the phone on a stand or hold it. Either way, 30 slabs a minute without chasing focus between scans.',
  },
  {
    icon: 'shield',
    title: 'Associates only see the buy',
    blurb:
      'Your team can run the scanner on day one without ever seeing comp or margin. The rule is enforced at the database.',
  },
  {
    icon: 'receipt',
    title: 'One-tap offer sheets',
    blurb:
      'Apply your margin rule, attach the vendor, print or email the offer. If the seller accepts, capture their signature right there.',
  },
  {
    icon: 'users',
    title: 'Vendor history at a glance',
    blurb:
      'Who sold you what, at which price, in which grade mix. Search by vendor, event, or date range in two taps.',
  },
  {
    icon: 'chart',
    title: 'Velocity with the comp',
    blurb:
      '7, 30, and 90 day trend on every price. Buy with confidence on the climbers. Skip the ones bleeding out.',
  },
  {
    icon: 'tag',
    title: 'Margin rules you control',
    blurb:
      'Per-grader, per-set, per-price-band modifiers. Event mode for release weekends. Full audit trail on every rule change.',
  },
];

export default function ForShopsPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="For card shops"
        title="Run the buy desk without running the math."
        italicize="the math"
        subtitle="You bought Slabbist to scan slabs. You get a counter that prices, offers, and closes a thirty-slab lot while your associate is still sorting them."
      />
      <AudienceBody
        pain="A walk-in drops a thirty-slab stack. Your associate types cert numbers into eBay one-by-one while the seller waits, and you end up low-balling the climbers and over-paying the dogs."
        shift="Slabs scan, comps resolve, margin applies. The offer sheet prints before the seller finishes their coffee."
        points={POINTS}
        ctaLabel="Join the store waitlist"
        waitlistAudience="store"
      />
      <FinalCta />
    </PageShell>
  );
}
