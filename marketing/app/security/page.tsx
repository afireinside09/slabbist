import type { Metadata } from 'next';
import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';
import { PageShell, PageHero, Prose } from '@/components/marketing/page-shell';

export const metadata: Metadata = {
  title: 'Security · Slabbist',
  description:
    'How Slabbist protects your data, how to report a vulnerability, and our responsible disclosure policy.',
};

type Pillar = { icon: IconName; title: string; blurb: string };

const PILLARS: Pillar[] = [
  {
    icon: 'lock',
    title: 'Encrypted in transit and at rest',
    blurb:
      'TLS 1.3 on every connection. AES-256 for data at rest in Postgres and object storage. Backups use separate encryption keys.',
  },
  {
    icon: 'shield',
    title: 'Your store is isolated in the database',
    blurb:
      'Row-level security in Postgres ties every row to your store. A different store — or a stray query — cannot read your data. The API never returns what the database refuses to serve.',
  },
  {
    icon: 'users',
    title: 'Least-privilege access',
    blurb:
      'Engineering access to production requires SSO and hardware MFA, is time-limited, and is logged. There is no shared admin account.',
  },
  {
    icon: 'reload',
    title: 'Tested backups',
    blurb:
      'Point-in-time recovery up to 7 days. We run monthly restore drills and track them in a runbook available to customers.',
  },
  {
    icon: 'eye',
    title: 'Audit logging',
    blurb:
      'Sensitive account and data changes are logged with the actor, time, and IP address. Logs are kept for at least 12 months.',
  },
  {
    icon: 'flag',
    title: 'Responsible disclosure',
    blurb:
      'Email security@slabbist.com. We acknowledge within one business day. Good-faith researchers are welcome — details below.',
  },
];

export default function SecurityPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Security"
        title="Your store's data never leaves your store."
        italicize="never leaves"
        subtitle="Your store's data is yours alone. The database keeps every store isolated. No other shop can see your comps, costs, or margins."
      />

      <section
        style={{
          padding: 'clamp(56px, 8vw, 80px) 0',
          borderTop: '1px solid ' + SLAB.hair,
        }}
      >
        <div className="slab-container" style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))',
              gap: 1,
              background: SLAB.hair,
              border: '1px solid ' + SLAB.hair,
              borderRadius: 16,
              overflow: 'hidden',
            }}
          >
            {PILLARS.map((p) => (
              <div
                key={p.title}
                style={{
                  padding: '28px 26px 32px',
                  background: SLAB.ink,
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 14,
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <Icon name={p.icon} size={17} sw={1.8} color={SLAB.gold} />
                  <div style={{ fontSize: 17, fontWeight: 500, letterSpacing: -0.3 }}>{p.title}</div>
                </div>
                <div style={{ fontSize: 14, color: SLAB.muted, lineHeight: 1.55 }}>{p.blurb}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      <Prose>
        <h2>Reporting a vulnerability</h2>
        <p>
          Email <a href="mailto:security@slabbist.com">security@slabbist.com</a> with a
          description of what you found and how to reproduce it. If you need PGP, ask in your
          first message and we will send the key before you share any details.
        </p>
        <p>
          We acknowledge within one business day and aim to triage within three. We do not run a
          paid bounty program, but we will publicly credit researchers who ask for it once a fix
          ships.
        </p>

        <h3>Safe harbor</h3>
        <p>
          Good-faith research on Slabbist production services is not a Terms violation.
          Good-faith means: no data taken beyond the minimum needed to prove the issue, no
          denial-of-service testing, no social engineering our staff, and no reading other
          users&apos; data outside your own accounts.
        </p>

        <h2>Subprocessors and infrastructure</h2>
        <p>
          A current list is available on request. Key providers today: Supabase (Postgres and
          auth, US region), Cloudflare (edge network), Resend (transactional email), Sentry
          (crash reporting with PII redacted), Stripe and Persona (marketplace, planned).
        </p>

        <h2>Compliance roadmap</h2>
        <p>
          We are working toward SOC 2 Type I in 2026, followed by Type II after twelve months
          of production operations. GDPR and CCPA compliance is in place today. Customers with
          specific requirements can request a current security questionnaire response.
        </p>
      </Prose>
    </PageShell>
  );
}
