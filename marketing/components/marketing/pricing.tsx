'use client';

import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';
import { useAuth } from './auth-context';

type Tier = {
  audience: string;
  blurb: string;
  price: string;
  priceUnit: string;
  feat: string[];
  cta: string;
  ctaMode: 'signup' | 'login';
  footnote: string;
  featured?: boolean;
  icon: IconName;
};

const TIERS: Tier[] = [
  {
    audience: 'Stores & vendors',
    blurb: 'The scanner that runs the counter. Free on the App Store.',
    price: 'Free',
    priceUnit: 'on iOS',
    feat: [
      'Bulk scan, cert OCR, comp engine',
      'Margin rules and role visibility',
      'Unlimited users, unlimited scans',
      'Offer sheets, vendor DB, buylist',
    ],
    cta: 'Download on iOS',
    ctaMode: 'signup',
    footnote: 'How we get paid: eBay and TCGplayer affiliate, and only if you follow a comp.',
    icon: 'scan',
  },
  {
    audience: 'Sellers',
    blurb: 'List a slab in minutes. No listing fees. No sold fees.',
    price: 'Free',
    priceUnit: 'to list',
    feat: [
      'Zero listing or closing fees',
      'ID + cert verification before you go live',
      'Escrowed payouts on delivery confirm',
      'Reputation imports from eBay & PWCC',
      'Buyer inspection window before payout',
    ],
    cta: 'Join the seller waitlist',
    ctaMode: 'signup',
    footnote: 'Marketplace rolling out in cohorts. Verified sellers go first.',
    featured: true,
    icon: 'store',
  },
  {
    audience: 'Buyers',
    blurb: 'Every slab cert-verified before it ever hits your feed.',
    price: '1%',
    priceUnit: 'at checkout',
    feat: [
      'The scanner and comps are always free',
      'Every listing cross-checked with the grader DB',
      'Escrow + inspection window on every buy',
      'No hidden spreads or junk fees',
    ],
    cta: 'Join the buyer waitlist',
    ctaMode: 'signup',
    footnote: 'Compare to 20% elsewhere. Buyers should keep more of their money.',
    icon: 'shield',
  },
];

export function Pricing() {
  const { openAuth } = useAuth();

  return (
    <section
      id="pricing"
      style={{
        padding: 'clamp(84px, 11vw, 120px) 0',
        borderTop: '1px solid ' + SLAB.hair,
        position: 'relative',
      }}
    >
      <div style={{ maxWidth: 1180, margin: '0 auto', padding: '0 24px' }}>
        <div style={{ textAlign: 'center', marginBottom: 'clamp(40px, 5vw, 56px)' }}>
          <div
            style={{
              fontSize: 12,
              letterSpacing: 1.6,
              textTransform: 'uppercase',
              color: SLAB.gold,
              marginBottom: 18,
              fontWeight: 500,
            }}
          >
            Pricing
          </div>
          <h2
            style={{
              fontFamily: SLAB.serif,
              fontSize: 'clamp(40px, 5vw, 64px)',
              fontWeight: 400,
              letterSpacing: -1.5,
              lineHeight: 1.05,
              margin: '0 0 20px',
            }}
          >
            Free now. Fair later.
          </h2>
          <p
            style={{
              fontSize: 16,
              color: SLAB.muted,
              maxWidth: 620,
              margin: '0 auto',
              lineHeight: 1.6,
            }}
          >
            The app is free for stores, sellers, and buyers. We make money from eBay and TCGplayer affiliate links when you follow a comp through to a sale. So we only get paid when you do.
          </p>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: 20 }}>
          {TIERS.map((t) => (
            <div
              key={t.audience}
              style={{
                padding: 36,
                borderRadius: 24,
                background: t.featured
                  ? 'linear-gradient(145deg, oklch(0.22 0.06 78), oklch(0.12 0.03 78))'
                  : SLAB.elev,
                border: '1px solid ' + (t.featured ? 'oklch(0.82 0.13 78 / 0.33)' : SLAB.hair),
                display: 'flex',
                flexDirection: 'column',
                position: 'relative',
                boxShadow: t.featured ? '0 30px 80px oklch(0.82 0.13 78 / 0.13)' : 'none',
              }}
            >
              {t.featured && (
                <div
                  style={{
                    position: 'absolute',
                    top: -1,
                    right: 24,
                    padding: '6px 14px',
                    borderRadius: '0 0 8px 8px',
                    whiteSpace: 'nowrap',
                    background: SLAB.gold,
                    color: SLAB.ink,
                    fontSize: 10,
                    fontWeight: 600,
                    letterSpacing: 1.2,
                    textTransform: 'uppercase',
                  }}
                >
                  Where we go next
                </div>
              )}

              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 10,
                  marginBottom: 6,
                }}
              >
                <div
                  style={{
                    width: 36,
                    height: 36,
                    borderRadius: 10,
                    background: t.featured
                      ? `linear-gradient(135deg, ${SLAB.gold}, ${SLAB.goldDim})`
                      : SLAB.elev2,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    color: t.featured ? SLAB.ink : SLAB.muted,
                  }}
                >
                  <Icon name={t.icon} size={18} sw={1.8} />
                </div>
                <div
                  style={{
                    fontFamily: SLAB.serif,
                    fontSize: 26,
                    letterSpacing: -0.4,
                  }}
                >
                  {t.audience}
                </div>
              </div>
              <div
                style={{
                  fontSize: 14,
                  color: SLAB.muted,
                  marginBottom: 24,
                  lineHeight: 1.5,
                  minHeight: 40,
                }}
              >
                {t.blurb}
              </div>

              <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 8 }}>
                <span
                  style={{
                    fontFamily: SLAB.serif,
                    fontSize: 64,
                    letterSpacing: -1.5,
                    lineHeight: 1,
                    color: t.featured ? SLAB.gold : SLAB.text,
                  }}
                >
                  {t.price}
                </span>
                <span style={{ fontSize: 13, color: SLAB.muted, whiteSpace: 'nowrap' }}>
                  {t.priceUnit}
                </span>
              </div>
              <div
                style={{
                  fontSize: 12,
                  color: SLAB.muted,
                  marginBottom: 28,
                  fontFamily: SLAB.mono,
                  letterSpacing: 0.3,
                  lineHeight: 1.55,
                }}
              >
                {t.footnote}
              </div>

              <button
                onClick={() => openAuth(t.ctaMode)}
                style={{
                  padding: '14px 22px',
                  borderRadius: 999,
                  background: t.featured ? SLAB.gold : 'transparent',
                  color: t.featured ? SLAB.ink : SLAB.text,
                  border: t.featured ? 'none' : '1px solid ' + SLAB.hairStrong,
                  fontSize: 14,
                  fontWeight: 600,
                  cursor: 'pointer',
                  marginBottom: 28,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 8,
                }}
              >
                {t.cta} <Icon name="arrow" size={14} sw={2} />
              </button>

              <div
                style={{
                  borderTop: '1px solid ' + SLAB.hair,
                  paddingTop: 24,
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 12,
                }}
              >
                {t.feat.map((f) => (
                  <div
                    key={f}
                    style={{
                      display: 'flex',
                      alignItems: 'flex-start',
                      gap: 10,
                      fontSize: 13,
                      color: SLAB.text,
                      lineHeight: 1.35,
                    }}
                  >
                    <span style={{ flexShrink: 0, marginTop: 2 }}>
                      <Icon
                        name="check"
                        size={14}
                        color={t.featured ? SLAB.gold : SLAB.muted}
                        sw={2.5}
                      />
                    </span>
                    <span style={{ textWrap: 'balance' }}>{f}</span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>

        <div
          style={{
            marginTop: 40,
            textAlign: 'center',
            fontSize: 13,
            color: SLAB.muted,
            maxWidth: 640,
            margin: '40px auto 0',
            lineHeight: 1.65,
          }}
        >
          No subscriptions. No seat fees. No paywalled features. If we ever need to charge for something specific, we will say so up front, and it will still be optional.
        </div>
      </div>
    </section>
  );
}
