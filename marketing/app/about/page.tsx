import type { Metadata } from 'next';
import { PageShell, PageHero, Prose } from '@/components/marketing/page-shell';

export const metadata: Metadata = {
  title: 'About Slabbist',
  description:
    'Slabbist is an iOS app for Pokémon hobby stores and show vendors. Scan graded slabs, get real comps, and build offers fast.',
};

export default function AboutPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="About"
        title="We built Slabbist on a card-shop counter."
        italicize="counter"
        subtitle="Not in a conference room. Not in a deck. On a real counter, in a real shop, watching real buys go sideways."
      />
      <Prose>
        <h2>Why we built it</h2>
        <p>
          A seller walks in with a thirty-slab stack. The shop wants to buy. Someone is stuck
          typing cert numbers into eBay one at a time. The seller gets bored. The shop lowballs
          the climbers and overpays the dogs. Nobody wins.
        </p>
        <p>
          Slabbist is the tool we wanted on that counter. The camera reads the cert number.
          The app pulls comps — what those slabs actually sold for — and applies your margin.
          You have an offer before the seller loses patience.
        </p>

        <h2>What we believe</h2>
        <p>
          <strong>Show your work.</strong> Every price in the app links to the sales behind it.
          If we cannot show you the comps, we will not show you the number.
        </p>
        <p>
          <strong>Your data stays in your store.</strong> The database isolates every store's
          comps, costs, and margins. Your pricing never shows up in another shop's app.
        </p>
        <p>
          <strong>Free on iOS.</strong> No seat fee, no subscription. We earn affiliate
          commissions when you tap through to eBay or TCGplayer and buy something there.
        </p>

        <h2>Where we are</h2>
        <p>
          We are a Pacific-Northwest team. We have worked in card shops, run show booths, and
          shipped software. Slabbist is in closed beta with a handful of stores. We are opening
          to more shops through 2026, with a public iOS launch later this year.
        </p>
        <p>
          We are not affiliated with The Pokémon Company, PSA, BGS, CGC, SGC, or TAG.
          Slabbist is a tool for people who love the hobby, built by people who love the hobby.
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
