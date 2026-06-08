import type { Metadata } from 'next';
import { PageShell, PageHero } from '@/components/marketing/page-shell';
import { AudienceBody, type AudiencePoint } from '@/components/marketing/audience-page';
import { FinalCta } from '@/components/marketing/final-cta';

export const metadata: Metadata = {
  title: 'Slabbist for card shops',
  description:
    'Slabbist gives your card shop a buy desk that scans slabs in bulk, pulls real comps, and closes offers from your phone.',
};

const POINTS: AudiencePoint[] = [
  {
    icon: 'scan',
    title: 'Scan the stack fast',
    blurb:
      'Set the phone on a stand or hold it. Sweep a stack of slabs in one pass without chasing focus between scans.',
  },
  {
    icon: 'gauge',
    title: 'Grade the raw card before you offer',
    blurb:
      'A seller drops a raw card on the counter? Pre-grade gives you a PSA-equivalent estimate and centering read before you put a number on it.',
  },
  {
    icon: 'chart',
    title: 'Comps you can show the seller',
    blurb:
      'Every price is a real price you can show the seller: built from recent sales, with range, trend, and the actual solds behind it.',
  },
  {
    icon: 'tag',
    title: 'Your buy-price rules, applied automatically',
    blurb:
      'Set what you pay at each price tier once and every slab gets priced from its comp. Override any single buy by hand when you need to.',
  },
  {
    icon: 'receipt',
    title: 'Offer sheet to paid, in one flow',
    blurb:
      'Roll the lot into an offer, attach the vendor, mark it paid. It locks into your transaction ledger.',
  },
  {
    icon: 'users',
    title: 'Vendor history at a glance',
    blurb:
      'See who sold you what and in which grade mix. Keep a registry with notes and pull a vendor onto a lot in two taps.',
  },
];

export default function ForShopsPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="For card shops"
        title="Run the buy desk without running the math."
        italicize="the math"
        subtitle="Scan the slabs. Pull the comps. Apply your buy-price rules. Close the offer. Slabbist does all of it from your phone."
      />
      <AudienceBody
        pain="A walk-in drops a thirty-slab stack. Your associate is comping each slab on eBay and copy-pasting cert numbers into the PSA lookup — while the seller waits. You end up under-paying the climbers and over-paying the dogs."
        shift="Slabs scan, comps resolve, your buy-price rules apply, and the offer is ready to present. All before the seller loses patience."
        points={POINTS}
        ctaLabel="Join the waitlist"
        waitlistAudience="store"
      />
      <FinalCta />
    </PageShell>
  );
}
