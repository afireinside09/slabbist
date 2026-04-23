import type { Metadata } from 'next';
import { PageShell, PageHero, Prose } from '@/components/marketing/page-shell';

export const metadata: Metadata = {
  title: 'Terms of Service · Slabbist',
  description:
    'Plain-language terms for using the Slabbist app, website, and marketplace.',
};

export default function TermsPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Terms"
        title="The rules that come with the app."
        italicize="the app"
        subtitle="Short, readable, and binding. By using Slabbist you agree to these terms."
      />
      <Prose>
        <div className="eyebrow">Effective 2026-04-23</div>
        <p>
          These terms are a contract between you and Slabbist Inc. Read them. If anything is
          unclear, email{' '}
          <a href="mailto:legal@slabbist.com">legal@slabbist.com</a> before you sign up.
        </p>

        <h2>1. Your account</h2>
        <p>
          You must be at least 18 (or the age of majority where you live) to create an account. You
          are responsible for keeping your credentials confidential and for everything that happens
          under your account.
        </p>

        <h2>2. Acceptable use</h2>
        <ul>
          <li>Do not misrepresent cert numbers, grades, or card identities.</li>
          <li>Do not scrape, reverse engineer, or resell the comp engine output wholesale.</li>
          <li>Do not use Slabbist to price stolen goods or launder funds.</li>
          <li>Do not upload content you do not have the right to share.</li>
        </ul>

        <h2>3. Your data, your IP</h2>
        <p>
          You own the scans, lots, margin rules, and vendor records you create in Slabbist. You
          grant us the minimal licenses we need to host and display them to you and the people you
          choose to share them with.
        </p>
        <p>
          You agree that we may use aggregated, de-identified pricing data to improve the comp
          engine. We will never identify you or your store in those aggregates.
        </p>

        <h2>4. Pricing and fees</h2>
        <p>
          The Slabbist iOS app is free for stores, sellers, and buyers. We earn revenue from eBay
          and TCGplayer affiliate commissions when you follow a comp link through to a sale. The
          planned collector marketplace charges a 1% buyer fee at checkout. Sellers net the sale
          price after payment processing.
        </p>
        <p>
          If we ever charge for a specific feature, we will say so in advance and make it
          optional.
        </p>

        <h2>5. Comps are a reference, not an appraisal</h2>
        <p>
          Slabbist comps are computed from recent sold listings and are provided for your
          information. They are not a professional appraisal and we do not guarantee any resale
          value. You are responsible for the prices you pay and the prices you charge.
        </p>

        <h2>6. Grader trademarks</h2>
        <p>
          PSA, BGS, CGC, SGC, and TAG are trademarks of their respective owners. Slabbist is an
          independent tool and is not affiliated with, endorsed by, or sponsored by any grading
          company, or by The Pokémon Company International or Nintendo.
        </p>

        <h2>7. Termination</h2>
        <p>
          You can delete your account at any time from the app. We can suspend or terminate your
          account if you violate these terms, attempt to harm other users, or put the integrity of
          the comp engine at risk. We will give you notice and a chance to cure unless the breach
          is egregious.
        </p>

        <h2>8. Warranty and liability</h2>
        <p>
          Slabbist is provided &quot;as is.&quot; To the extent allowed by law, we disclaim
          implied warranties of merchantability, fitness for a particular purpose, and
          non-infringement. Our aggregate liability is capped at the greater of (a) $100 or (b)
          the amounts you paid us in the 12 months before the claim.
        </p>

        <h2>9. Disputes</h2>
        <p>
          These terms are governed by the laws of Delaware, without regard to conflict-of-law
          rules. Disputes are resolved by binding arbitration administered by the AAA on an
          individual basis, except that either party can seek injunctive relief in court for
          violations of IP rights.
        </p>

        <h2>10. Changes</h2>
        <p>
          We may revise these terms. If the change is material, we will email you and post the
          revised terms at least 30 days before they take effect. Continued use after the
          effective date is acceptance.
        </p>
      </Prose>
    </PageShell>
  );
}
