import type { Metadata } from 'next';
import { PageShell, PageHero, Prose } from '@/components/marketing/page-shell';

export const metadata: Metadata = {
  title: 'Privacy Policy · Slabbist',
  description:
    'How Slabbist handles the data it collects from stores, show vendors, and collectors. Plain language, no dark patterns.',
};

export default function PrivacyPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Privacy"
        title="We collect what we need. Nothing more."
        italicize="what we need"
        subtitle="Plain-language summary of what Slabbist collects, why, who we share it with, and how to delete it."
      />
      <Prose>
        <div className="eyebrow">Effective 2026-04-23</div>
        <p>
          This policy covers the Slabbist iOS app and slabbist.com. We wrote it to be short and
          readable. The defined terms (Controller, Processor, etc.) have the same meaning as in
          the GDPR. The long version of any section is available on request.
        </p>

        <h2>1. Who we are</h2>
        <p>
          Slabbist Inc. (&quot;Slabbist&quot;, &quot;we&quot;) is a Delaware corporation based in
          the Pacific Northwest, USA. For privacy questions write to{' '}
          <a href="mailto:privacy@slabbist.com">privacy@slabbist.com</a>.
        </p>

        <h2>2. What we collect</h2>
        <h3>When you join the waitlist</h3>
        <ul>
          <li>Email address</li>
          <li>Audience (store or collector)</li>
          <li>Approximate timestamp and IP address (used for abuse prevention, discarded after 30 days)</li>
        </ul>

        <h3>When you create a Slabbist account</h3>
        <ul>
          <li>Name, email, and password (hashed with Argon2id)</li>
          <li>Store or role metadata (owner vs. associate)</li>
          <li>Scans, cert numbers, pricing, margin rules, offer sheets, and any other data you enter into the app</li>
          <li>Device type and OS version for crash diagnostics</li>
        </ul>

        <h3>When you use the collector marketplace (future)</h3>
        <ul>
          <li>Government ID and selfie for identity verification (processed by our vendor, Persona)</li>
          <li>Payment method details (processed by Stripe — we never see the card number)</li>
          <li>Shipping address for buys</li>
        </ul>

        <h2>3. What we do not collect</h2>
        <ul>
          <li>We do not sell personal data. Ever.</li>
          <li>We do not fingerprint your device or sync advertising IDs.</li>
          <li>We do not share your buy history with other stores or vendors.</li>
        </ul>

        <h2>4. Why we collect it</h2>
        <p>
          To run the service you asked us to run: reading certs, resolving comps, syncing your lot
          across devices, and producing offer sheets. To spot abuse and fix bugs. To bill for the
          1% buyer fee on marketplace transactions (when that ships).
        </p>

        <h2>5. Who we share it with</h2>
        <p>
          We share personal data with service providers who help us run Slabbist — listed in full
          on request. At the time of writing: Supabase (hosting, Postgres, auth), Stripe
          (payments, future), Persona (ID verification, future), Resend (email), Sentry (crash
          reports, with PII redaction). None of them may use your data for their own purposes.
        </p>
        <p>
          We disclose data to law enforcement only when we are legally compelled. We will give you
          notice first when we are permitted to.
        </p>

        <h2>6. Retention</h2>
        <ul>
          <li>Waitlist signups: until launch, then moved into your account record if you create one, or deleted if you do not.</li>
          <li>Scans and lots: retained for the life of your account; deleted 30 days after account closure.</li>
          <li>Financial records: retained for 7 years where tax law requires it.</li>
          <li>Backups: purged within 90 days.</li>
        </ul>

        <h2>7. Your rights</h2>
        <p>
          Depending on where you live, you have the right to access, correct, delete, port, or
          object to the processing of your personal data. To exercise any of these, email{' '}
          <a href="mailto:privacy@slabbist.com">privacy@slabbist.com</a>. We respond within 30
          days.
        </p>
        <p>
          California residents: we do not sell or share personal information under the CCPA
          definitions. You still have the right to know, delete, correct, and request limited use
          of sensitive personal information.
        </p>

        <h2>8. International transfers</h2>
        <p>
          Slabbist is hosted in the United States. If you access the service from the European
          Economic Area or the United Kingdom, your data is transferred under Standard Contractual
          Clauses or equivalent safeguards.
        </p>

        <h2>9. Children</h2>
        <p>
          Slabbist is not for anyone under 13. If you believe a child has given us personal data,
          email <a href="mailto:privacy@slabbist.com">privacy@slabbist.com</a> and we will delete
          it.
        </p>

        <h2>10. Changes to this policy</h2>
        <p>
          If we change anything material, we will email you and post a dated notice on this page
          at least 30 days before the change takes effect.
        </p>
      </Prose>
    </PageShell>
  );
}
