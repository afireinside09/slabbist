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
      'Set the phone on a stand or hold it. Either way, sweep a stack of slabs in one pass without chasing focus between scans.',
  },
  {
    icon: 'gauge',
    title: 'Grade the walk-in before you offer',
    blurb:
      'A seller drops a raw card on the counter? Pre-grade gives you a PSA-equivalent estimate and centering read before you put a number on it.',
  },
  {
    icon: 'chart',
    title: 'Comps you can show the seller',
    blurb:
      'Every price is built from recent sales, with range, trend, and the actual solds behind it. Buy with confidence on the climbers, skip the ones bleeding out.',
  },
  {
    icon: 'tag',
    title: 'Your margin ladder, applied automatically',
    blurb:
      'Set buy percentages by price tier once and every slab gets priced against its comp. Override any single buy by hand when you need to.',
  },
  {
    icon: 'receipt',
    title: 'Offer sheet to paid, in one flow',
    blurb:
      'Roll the lot into an offer, attach the vendor, mark it paid. It drops into your transaction ledger, frozen and audit-safe.',
  },
  {
    icon: 'users',
    title: 'Vendor history at a glance',
    blurb:
      'Who sold you what, in which grade mix. Keep a registry with notes and pull a vendor onto a lot in two taps.',
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
        pain="A walk-in drops a thirty-slab stack. Your associate is comping each slab on eBay and copy-pasting cert numbers into the PSA lookup to make sure they're real — while the seller waits. You end up low-balling the climbers and over-paying the dogs."
        shift="Slabs scan, comps resolve, your margin applies, and the offer is ready to present before the seller finishes their coffee."
        points={POINTS}
        ctaLabel="Join the store waitlist"
        waitlistAudience="store"
      />
      <FinalCta />
    </PageShell>
  );
}
