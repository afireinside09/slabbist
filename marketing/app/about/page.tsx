import type { Metadata } from 'next';
import { PageShell, PageHero, Prose } from '@/components/marketing/page-shell';

export const metadata: Metadata = {
  title: 'About Slabbist',
  description:
    'Slabbist is a Pacific-Northwest-built iOS app for Pokémon hobby stores and vendors. Here is why we built it and what we believe.',
};

export default function AboutPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="About"
        title="We built Slabbist on a card-shop counter."
        italicize="counter"
        subtitle="Not in a conference room. Not in a deck. On a real counter, in a real shop, watching real buys go wrong."
      />
      <Prose>
        <h2>Why we built it</h2>
        <p>
          A seller walks into a card shop with a thirty-slab stack. The owner wants to buy. The
          associate is stuck typing cert numbers into eBay one by one. The seller gets bored. The
          owner lowballs the climbers and overpays the dogs. Everyone loses a little — the seller
          on the sale, the shop on the margin, the hobby on another person who decides the counter
          is not worth the trip.
        </p>
        <p>
          Slabbist is the tool we wanted on that counter. A scanner that reads every grader. A
          comp engine that shows you a real median of real sales. A buy flow that applies your
          margin rule and prints an offer before the seller finishes their coffee.
        </p>

        <h2>What we believe</h2>
        <p>
          <strong>Price transparency is non-negotiable.</strong> Every number in the app links to
          the sales that produced it. If we cannot show you the comps, we will not show you the
          price.
        </p>
        <p>
          <strong>The buy price is not a UI toggle.</strong> Role-based visibility is enforced in
          the database. An associate cannot leak the margin because the margin never left the
          server for them.
        </p>
        <p>
          <strong>Free on iOS, forever.</strong> Stores, sellers, and buyers do not pay a seat fee
          or a subscription. We make money from eBay and TCGplayer affiliate links when you
          follow a comp through to a sale.
        </p>
        <p>
          <strong>The hobby should keep more of its money.</strong> The planned collector
          marketplace charges a 1% buyer fee at checkout — compared to the 20% sellers lose
          elsewhere. Sellers net the sale price after payment processing. That is it.
        </p>

        <h2>Where we are</h2>
        <p>
          Slabbist is a Pacific-Northwest team that has worked in card shops, run show booths,
          and shipped software for a living. We are in closed beta with a handful of stores and
          will open to more cohorts through 2026. The iOS app launches publicly later this year.
        </p>
        <p>
          We are not affiliated with The Pokémon Company, PSA, BGS, CGC, SGC, or TAG. Slabbist is
          a tool for people who love the hobby — built by people who love the hobby.
        </p>

        <h2>How to reach us</h2>
        <p>
          Questions, partnerships, or want to pilot Slabbist in your shop?{' '}
          <a href="/contact">Get in touch</a>. We read every message.
        </p>
      </Prose>
    </PageShell>
  );
}
