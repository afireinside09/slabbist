import type { Metadata } from 'next';
import { PageShell, PageHero } from '@/components/marketing/page-shell';
import { AudienceBody, type AudiencePoint } from '@/components/marketing/audience-page';
import { FinalCta } from '@/components/marketing/final-cta';

export const metadata: Metadata = {
  title: 'Slabbist for collectors',
  description:
    'Buy cert-verified slabs and list your own with zero seller fees. 1% buyer fee at checkout, compared to 20% elsewhere.',
};

const POINTS: AudiencePoint[] = [
  {
    icon: 'shield',
    title: 'Every listing cert-verified',
    blurb:
      'Every slab is cross-checked with the grader DB before it goes live. No mismatched certs, no swapped slabs, no surprises.',
  },
  {
    icon: 'lock',
    title: 'Escrow and an inspection window',
    blurb:
      'Your money is held until the card arrives and you have had time to inspect it. Return it if the slab does not match the listing.',
  },
  {
    icon: 'tag',
    title: 'Zero seller fees',
    blurb:
      'No listing, closing, or commission fees. A 1% buyer fee applies only at checkout. Sellers net the sale price, after payment processing.',
  },
  {
    icon: 'users',
    title: 'Reputation that follows you',
    blurb:
      'Import your eBay and PWCC feedback so a strong seller history is not wiped out when you move marketplaces.',
  },
  {
    icon: 'chart',
    title: 'Price history on every card',
    blurb:
      'The same comp engine that stores use. See the last 90 days of sales on the exact card you are eyeing before you tap buy.',
  },
  {
    icon: 'mail',
    title: 'ID + cert verification up front',
    blurb:
      'New sellers verify identity and the first few certs before they can go live. Trust is earned, not assumed.',
  },
];

export default function ForCollectorsPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="For collectors"
        title="A marketplace that doesn't punish selling."
        italicize="doesn't punish"
        subtitle="Buy cert-verified slabs. List your own with zero seller fees. A 1% buyer fee applies only at checkout — compared to 20% you pay elsewhere."
      />
      <AudienceBody
        pain="You love the hobby but hate the tax. A 13% final-value fee, 3% payment processing, and a promoted-listing fee on top means a $500 slab nets you $420 if you are lucky."
        shift="List for free. Sellers net the sale price after payment processing. Buyers pay a 1% fee at checkout for escrow, inspection, and cert verification."
        points={POINTS}
        ctaLabel="Join the collector waitlist"
        waitlistAudience="collector"
      />
      <FinalCta />
    </PageShell>
  );
}
