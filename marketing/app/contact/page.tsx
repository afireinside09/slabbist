import type { Metadata } from 'next';
import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';
import { PageShell, PageHero } from '@/components/marketing/page-shell';

export const metadata: Metadata = {
  title: 'Contact Slabbist',
  description: 'Get in touch with Slabbist. Support, sales, press, and security contacts.',
};

type ContactLane = {
  icon: IconName;
  label: string;
  blurb: string;
  email: string;
};

const LANES: ContactLane[] = [
  {
    icon: 'store',
    label: 'Shops & vendors',
    blurb:
      'Want to pilot Slabbist in your shop or at your next show? We reply within one business day.',
    email: 'hello@slabbist.com',
  },
  {
    icon: 'users',
    label: 'Collector questions',
    blurb:
      'Questions about the marketplace, buyer fee, or seller verification? Drop us a line.',
    email: 'hello@slabbist.com',
  },
  {
    icon: 'flag',
    label: 'Press',
    blurb:
      'Covering the hobby or the app? Boilerplate and stats live on the /press page. Otherwise:',
    email: 'press@slabbist.com',
  },
  {
    icon: 'shield',
    label: 'Security & privacy',
    blurb:
      'Found a vulnerability or have a responsible-disclosure question? PGP and details on our security page.',
    email: 'security@slabbist.com',
  },
];

export default function ContactPage() {
  return (
    <PageShell>
      <PageHero
        eyebrow="Contact"
        title="Get in touch. We actually read it."
        italicize="actually read it"
        subtitle="Pick the lane that fits. For anything urgent, email hello@ and we will route it."
      />

      <section
        style={{
          padding: 'clamp(40px, 6vw, 64px) 0 clamp(96px, 12vw, 140px)',
          borderTop: '1px solid ' + SLAB.hair,
        }}
      >
        <div
          className="slab-container"
          style={{
            maxWidth: 1180,
            margin: '0 auto',
            padding: '0 24px',
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))',
            gap: 1,
            background: SLAB.hair,
            border: '1px solid ' + SLAB.hair,
            borderRadius: 16,
            overflow: 'hidden',
          }}
        >
          {LANES.map((l) => (
            <a
              key={l.label}
              href={`mailto:${l.email}`}
              style={{
                padding: '28px 26px 32px',
                background: SLAB.ink,
                display: 'flex',
                flexDirection: 'column',
                gap: 14,
                textDecoration: 'none',
                color: SLAB.text,
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
                <Icon name={l.icon} size={18} sw={1.8} />
              </div>
              <div>
                <div
                  style={{
                    fontSize: 17,
                    fontWeight: 500,
                    letterSpacing: -0.3,
                    marginBottom: 8,
                  }}
                >
                  {l.label}
                </div>
                <div style={{ fontSize: 14, color: SLAB.muted, lineHeight: 1.55 }}>{l.blurb}</div>
              </div>
              <div
                style={{
                  marginTop: 'auto',
                  fontSize: 13,
                  color: SLAB.gold,
                  fontFamily: SLAB.mono,
                }}
              >
                {l.email} →
              </div>
            </a>
          ))}
        </div>

        <div
          className="slab-container"
          style={{
            maxWidth: 820,
            margin: '56px auto 0',
            padding: '0 24px',
            fontSize: 14,
            color: SLAB.muted,
            lineHeight: 1.65,
            textAlign: 'center',
          }}
        >
          Based in the Pacific Northwest, USA. For mailing addresses, email{' '}
          <a
            href="mailto:hello@slabbist.com"
            style={{
              color: SLAB.gold,
              textDecoration: 'underline',
              textUnderlineOffset: 3,
            }}
          >
            hello@slabbist.com
          </a>
          .
        </div>
      </section>
    </PageShell>
  );
}
