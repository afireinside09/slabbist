import type { Metadata } from 'next';
import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';
import { PageShell, PageHero, Prose } from '@/components/marketing/page-shell';

export const metadata: Metadata = {
  title: 'Security · Slabbist',
  description:
    'How Slabbist secures your data, our responsible disclosure policy, and how to report a vulnerability.',
};

type Pillar = { icon: IconName; title: string; blurb: string };

const PILLARS: Pillar[] = [
  {
    icon: 'lock',
    title: 'Encrypted in transit and at rest',
    blurb:
      'TLS 1.3 for every connection. AES-256 for data at rest in Postgres and object storage. Backups are encrypted with separate keys.',
  },
  {
    icon: 'shield',
    title: 'Role enforcement in the database',
    blurb:
      'Row-level security in Postgres means an associate can never read a column their role does not own. The API never returns what the database refuses to serve.',
  },
  {
    icon: 'users',
    title: 'Least-privilege access',
    blurb:
      'Engineering access to production is gated through SSO + hardware MFA, time-boxed, and logged. There is no shared admin account.',
  },
  {
    icon: 'reload',
    title: 'Tested backups',
    blurb:
      'Point-in-time recovery up to 7 days. Monthly restore drills, tracked in a public-to-customers runbook.',
  },
  {
    icon: 'eye',
    title: 'Audit logging',
    blurb:
      'Every margin rule change, export, and role change is logged with actor, time, and IP. Logs are retained for 12 months minimum.',
  },
  {
    icon: 'flag',
    title: 'Responsible disclosure',
    blurb:
      'Reports to security@slabbist.com are acknowledged within one business day. Good-faith researchers are welcome — see the policy below.',
  },
];

export default function SecurityPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Security"
        title="Your buy price never leaves its lane."
        italicize="never leaves"
        subtitle="Slabbist was built around a single idea: the buy number belongs to the owner, not the associate. Everything else follows from that."
      />

      <section
        style={{
          padding: 'clamp(56px, 8vw, 80px) 0',
          borderTop: '1px solid ' + SLAB.hair,
        }}
      >
        <div style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
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
                <div
                  style={{
                    width: 40,
                    height: 40,
                    borderRadius: 10,
                    background: SLAB.elev2,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    color: SLAB.gold,
                  }}
                >
                  <Icon name={p.icon} size={18} sw={1.8} />
                </div>
                <div style={{ fontSize: 17, fontWeight: 500, letterSpacing: -0.3 }}>{p.title}</div>
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
          reproduction and the affected surface. If you need PGP, request our key in the first
          message and we will send it before you share details.
        </p>
        <p>
          We acknowledge within one business day and aim to triage within three. We do not
          currently run a paid bounty, but we will credit researchers who ask for public
          acknowledgement once a fix ships.
        </p>

        <h3>Safe-harbor</h3>
        <p>
          Good-faith research on the Slabbist production services is not a violation of our
          Terms. &quot;Good-faith&quot; means no data exfiltration beyond a minimum proof of
          concept, no denial of service, no social engineering of our staff, and no accessing
          other users&apos; data beyond your own accounts.
        </p>

        <h2>Subprocessors and infrastructure</h2>
        <p>
          A current list is available on request. Key providers at the time of writing: Supabase
          (Postgres + auth, US region), Cloudflare (edge network), Resend (transactional email),
          Sentry (crash telemetry with PII redaction), Stripe and Persona (marketplace, future).
        </p>

        <h2>Compliance roadmap</h2>
        <p>
          We are working toward SOC 2 Type I in 2026, followed by Type II once we have twelve
          months of production operations. GDPR and CCPA compliance is in place today. Customers
          with specific requirements can ask for a current security questionnaire response.
        </p>
      </Prose>
    </PageShell>
  );
}
