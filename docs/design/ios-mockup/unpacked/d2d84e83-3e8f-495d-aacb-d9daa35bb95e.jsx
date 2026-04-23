// Onboarding, Home, Profile

function SBStatusBar({ dark = true, time = '9:41' }) {
  const c = dark ? SB_TOKENS.text : '#000';
  return (
    <div style={{
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      padding: '18px 28px 8px', position: 'relative', zIndex: 20,
      fontFamily: SB_TOKENS.sans,
    }}>
      <span style={{ fontWeight: 600, fontSize: 15, color: c, letterSpacing: -0.2 }}>{time}</span>
      <div style={{ width: 126, height: 0 }}/>
      <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
        <svg width="17" height="11" viewBox="0 0 17 11"><rect x="0" y="7" width="3" height="4" rx="0.5" fill={c}/><rect x="4.5" y="5" width="3" height="6" rx="0.5" fill={c}/><rect x="9" y="2.5" width="3" height="8.5" rx="0.5" fill={c}/><rect x="13.5" y="0" width="3" height="11" rx="0.5" fill={c}/></svg>
        <svg width="25" height="12" viewBox="0 0 25 12"><rect x="0.5" y="0.5" width="21" height="11" rx="3" fill="none" stroke={c} strokeOpacity="0.4"/><rect x="2" y="2" width="18" height="8" rx="1.5" fill={c}/><path d="M23 4v4c.7-.3 1.3-1.1 1.3-2s-.6-1.7-1.3-2z" fill={c} fillOpacity="0.5"/></svg>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// ONBOARDING — 3 pages, black w/ gold, animated card entry
// ═════════════════════════════════════════════════════════════
function SBOnboarding({ onFinish }) {
  const [page, setPage] = React.useState(0);
  const pages = [
    {
      kicker: 'Introducing',
      title: 'Know every card\u2019s worth,\nthe moment you see it.',
      sub: 'Point your camera. Slabbist reads the card, the grade, and the live market — in under a second.',
      cta: 'Continue',
    },
    {
      kicker: 'Batch scan',
      title: 'Value an\nentire binder\nin one pass.',
      sub: 'Rapid-fire capture stacks results as you go. Your portfolio total ticks up live.',
      cta: 'Next',
    },
    {
      kicker: 'AR Overlay',
      title: 'See prices pinned\nto every card\nin view.',
      sub: 'Real-time comps hover above each card at the table, the show floor, or the LGS.',
      cta: 'Start scanning',
    },
  ];

  const p = pages[page];

  return (
    <div style={{
      position: 'absolute', inset: 0, background: SB_TOKENS.ink, color: SB_TOKENS.text,
      fontFamily: SB_TOKENS.sans, overflow: 'hidden',
    }}>
      {/* ambient gold blob */}
      <div style={{
        position: 'absolute', top: -140, right: -120, width: 380, height: 380,
        borderRadius: '50%',
        background: `radial-gradient(circle, ${SB_TOKENS.gold} 0%, transparent 60%)`,
        opacity: 0.18, filter: 'blur(40px)',
      }}/>
      <div style={{
        position: 'absolute', bottom: -180, left: -100, width: 340, height: 340,
        borderRadius: '50%',
        background: `radial-gradient(circle, oklch(0.5 0.2 280) 0%, transparent 60%)`,
        opacity: 0.25, filter: 'blur(50px)',
      }}/>

      <SBStatusBar/>

      {/* floating card stack */}
      <div style={{
        position: 'absolute', top: 90, left: 0, right: 0, height: 280,
        display: 'flex', justifyContent: 'center', alignItems: 'center',
      }}>
        {[SB_CARDS[8], SB_CARDS[2], SB_CARDS[6]].map((c, i) => {
          const offset = (i - 1) * 46;
          const rot = (i - 1) * 8 + (page * 3);
          const scale = 1 - Math.abs(i - 1) * 0.06;
          return (
            <div key={c.id} style={{
              position: 'absolute',
              transform: `translate(${offset}px, ${Math.abs(i-1) * 12}px) rotate(${rot}deg) scale(${scale})`,
              transition: 'transform 0.9s cubic-bezier(0.2, 0.9, 0.3, 1.1)',
              zIndex: 10 - Math.abs(i - 1),
            }}>
              <SBCardArt card={c} width={158} height={220}/>
            </div>
          );
        })}
      </div>

      {/* brand lockup */}
      <div style={{
        position: 'absolute', top: 56, left: 32, display: 'flex', gap: 8, alignItems: 'center',
      }}>
        <div style={{
          width: 18, height: 18, borderRadius: 4,
          background: `linear-gradient(135deg, ${SB_TOKENS.gold}, ${SB_TOKENS.goldDim})`,
          boxShadow: `0 0 12px ${SB_TOKENS.gold}`,
        }}/>
        <span style={{ fontSize: 14, letterSpacing: 1.6, fontWeight: 500, textTransform: 'uppercase' }}>Slabbist</span>
      </div>

      {/* copy */}
      <div style={{
        position: 'absolute', left: 32, right: 32, bottom: 172,
      }}>
        <div style={{
          fontSize: 11, letterSpacing: 2.2, textTransform: 'uppercase',
          color: SB_TOKENS.gold, marginBottom: 18, fontWeight: 500,
        }}>{p.kicker}</div>
        <h1 style={{
          fontFamily: SB_TOKENS.serif, fontSize: 42, lineHeight: 1.02, margin: 0,
          letterSpacing: -0.8, fontWeight: 400, whiteSpace: 'pre-line',
        }}>{p.title}</h1>
        <p style={{
          color: SB_TOKENS.muted, fontSize: 15, lineHeight: 1.5,
          marginTop: 18, maxWidth: 300, letterSpacing: -0.1,
        }}>{p.sub}</p>
      </div>

      {/* dots + CTA */}
      <div style={{
        position: 'absolute', left: 32, right: 32, bottom: 56,
        display: 'flex', alignItems: 'center', gap: 16,
      }}>
        <div style={{ display: 'flex', gap: 6 }}>
          {pages.map((_, i) => (
            <div key={i} style={{
              width: i === page ? 20 : 6, height: 6, borderRadius: 3,
              background: i === page ? SB_TOKENS.gold : 'rgba(255,255,255,0.2)',
              transition: 'all 0.3s',
            }}/>
          ))}
        </div>
        <button onClick={() => page < pages.length - 1 ? setPage(page + 1) : onFinish()}
          style={{
            marginLeft: 'auto', height: 52, padding: '0 26px', borderRadius: 26,
            background: SB_TOKENS.gold, color: SB_TOKENS.ink, border: 'none',
            fontFamily: SB_TOKENS.sans, fontSize: 15, fontWeight: 600, letterSpacing: -0.1,
            display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer',
            boxShadow: `0 8px 24px ${SB_TOKENS.gold}30`,
          }}>
          {p.cta}
          <SBIcon name="chevron" size={16} strokeWidth={2.2}/>
        </button>
      </div>

      {/* skip */}
      {page < pages.length - 1 && (
        <button onClick={onFinish} style={{
          position: 'absolute', top: 54, right: 28, background: 'transparent', border: 'none',
          color: SB_TOKENS.muted, fontFamily: SB_TOKENS.sans, fontSize: 14, cursor: 'pointer',
        }}>Skip</button>
      )}
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// HOME — portfolio hero, watchlist, recent activity
// ═════════════════════════════════════════════════════════════
function SBHome({ onOpenCard, onOpenScan }) {
  const total = SB_CARDS.reduce((a, c) => a + c.value, 0);
  const dayChange = 342.80;
  const dayPct = 2.8;

  const movers = [...SB_CARDS].sort((a, b) => Math.abs(b.change) - Math.abs(a.change)).slice(0, 4);

  // mini sparkline
  const sparkPts = [18, 22, 19, 24, 21, 28, 26, 32, 30, 35, 38, 42, 46, 44, 52, 56, 54, 62, 58, 65];

  return (
    <div style={{
      position: 'absolute', inset: 0, background: SB_TOKENS.ink, color: SB_TOKENS.text,
      fontFamily: SB_TOKENS.sans, overflow: 'auto', paddingBottom: 110,
    }}>
      <SBStatusBar/>

      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 24px 0' }}>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          <div style={{
            width: 34, height: 34, borderRadius: 10,
            background: `linear-gradient(135deg, ${SB_TOKENS.gold}, ${SB_TOKENS.goldDim})`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontFamily: SB_TOKENS.serif, color: SB_TOKENS.ink, fontSize: 18, fontStyle: 'italic', fontWeight: 600,
          }}>S</div>
          <div>
            <div style={{ fontSize: 12, color: SB_TOKENS.dim, letterSpacing: 0.1 }}>Portfolio</div>
            <div style={{ fontSize: 14, fontWeight: 500, marginTop: -1 }}>Main vault</div>
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button style={{
            width: 40, height: 40, borderRadius: 20, border: '1px solid ' + SB_TOKENS.hairline,
            background: SB_TOKENS.elev, color: SB_TOKENS.text,
            display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
          }}><SBIcon name="bell" size={18}/></button>
        </div>
      </div>

      {/* Hero value */}
      <div style={{ padding: '32px 24px 20px' }}>
        <div style={{
          fontSize: 11, letterSpacing: 2.2, textTransform: 'uppercase',
          color: SB_TOKENS.dim, fontWeight: 500, marginBottom: 10,
        }}>Estimated value</div>
        <div style={{
          fontFamily: SB_TOKENS.serif, fontSize: 68, lineHeight: 1, letterSpacing: -2,
          fontWeight: 400, display: 'flex', alignItems: 'baseline',
        }}>
          <span style={{ fontSize: 36, opacity: 0.5, marginRight: 6 }}>$</span>
          {Math.round(total).toLocaleString('en-US')}
          <span style={{ fontSize: 34, opacity: 0.35 }}>.{(total % 1 * 100).toFixed(0).padStart(2,'0')}</span>
        </div>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginTop: 16 }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 4,
            color: SB_TOKENS.pos, fontSize: 14, fontWeight: 500,
            fontFamily: SB_TOKENS.mono,
          }}>
            <SBIcon name="arrow-up" size={14} strokeWidth={2.5}/>
            {sbUSD(dayChange, { cents: true })}
            <span style={{ opacity: 0.7, marginLeft: 4 }}>{sbPct(dayPct)}</span>
          </div>
          <span style={{ color: SB_TOKENS.dim, fontSize: 12 }}>Today</span>
        </div>

        {/* Sparkline */}
        <div style={{ marginTop: 24, height: 80, position: 'relative' }}>
          <svg width="100%" height="80" viewBox={`0 0 ${(sparkPts.length-1) * 10} 80`} preserveAspectRatio="none" style={{ display: 'block' }}>
            <defs>
              <linearGradient id="sp-fill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={SB_TOKENS.gold} stopOpacity="0.28"/>
                <stop offset="100%" stopColor={SB_TOKENS.gold} stopOpacity="0"/>
              </linearGradient>
            </defs>
            <path d={`M ${sparkPts.map((v, i) => `${i * 10} ${80 - v}`).join(' L ')} L ${(sparkPts.length-1)*10} 80 L 0 80 Z`} fill="url(#sp-fill)"/>
            <path d={`M ${sparkPts.map((v, i) => `${i * 10} ${80 - v}`).join(' L ')}`} fill="none" stroke={SB_TOKENS.gold} strokeWidth="1.5"/>
            <circle cx={(sparkPts.length-1)*10} cy={80 - sparkPts[sparkPts.length-1]} r="3" fill={SB_TOKENS.gold}/>
          </svg>
          <div style={{
            position: 'absolute', bottom: -4, left: 0, right: 0,
            display: 'flex', justifyContent: 'space-between',
            fontFamily: SB_TOKENS.mono, fontSize: 10, color: SB_TOKENS.dim,
          }}>
            {['1D', '1W', '1M', '3M', '1Y', 'ALL'].map(p => (
              <span key={p} style={{
                padding: '4px 8px', borderRadius: 12,
                background: p === '1M' ? SB_TOKENS.elev2 : 'transparent',
                color: p === '1M' ? SB_TOKENS.text : SB_TOKENS.dim,
              }}>{p}</span>
            ))}
          </div>
        </div>
      </div>

      {/* Primary action — big scan pill */}
      <div style={{ padding: '16px 24px 8px' }}>
        <button onClick={onOpenScan} style={{
          width: '100%', height: 68, borderRadius: 20,
          background: `linear-gradient(135deg, ${SB_TOKENS.gold}, oklch(0.72 0.13 60))`,
          border: 'none', color: SB_TOKENS.ink, cursor: 'pointer',
          display: 'flex', alignItems: 'center', padding: '0 20px', gap: 14,
          fontFamily: SB_TOKENS.sans, textAlign: 'left',
          boxShadow: `0 14px 36px ${SB_TOKENS.gold}22`,
        }}>
          <div style={{
            width: 44, height: 44, borderRadius: 22,
            background: SB_TOKENS.ink, color: SB_TOKENS.gold,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}><SBIcon name="scan" size={22}/></div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 16, fontWeight: 600, letterSpacing: -0.2 }}>Scan cards</div>
            <div style={{ fontSize: 12, opacity: 0.7, marginTop: 1 }}>Batch mode · AR overlay</div>
          </div>
          <SBIcon name="chevron" size={20} strokeWidth={2.2}/>
        </button>
      </div>

      {/* Top movers */}
      <div style={{ padding: '28px 24px 0' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 14 }}>
          <div style={{
            fontSize: 11, letterSpacing: 2.2, textTransform: 'uppercase',
            color: SB_TOKENS.dim, fontWeight: 500,
          }}>Top movers · 24h</div>
          <span style={{ fontSize: 12, color: SB_TOKENS.gold }}>See all</span>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 12, overflow: 'auto', padding: '0 24px 4px', scrollbarWidth: 'none' }}>
        {movers.map(c => (
          <div key={c.id} onClick={() => onOpenCard(c)} style={{
            width: 160, flexShrink: 0, background: SB_TOKENS.elev,
            borderRadius: 18, padding: 14, cursor: 'pointer',
            border: '1px solid ' + SB_TOKENS.hairline,
          }}>
            <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 10 }}>
              <SBCardArt card={c} width={86} height={120} radius={8} glow={false}/>
            </div>
            <div style={{ fontSize: 12, color: SB_TOKENS.dim, fontFamily: SB_TOKENS.mono, marginBottom: 2 }}>{c.num}</div>
            <div style={{ fontSize: 13, fontWeight: 500, lineHeight: 1.2, letterSpacing: -0.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.name}</div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 10 }}>
              <span style={{ fontFamily: SB_TOKENS.mono, fontSize: 14, fontWeight: 500 }}>{sbUSD(c.value, { compact: true })}</span>
              <span style={{ fontFamily: SB_TOKENS.mono, fontSize: 11, color: c.change >= 0 ? SB_TOKENS.pos : SB_TOKENS.neg }}>{sbPct(c.change)}</span>
            </div>
          </div>
        ))}
      </div>

      {/* Activity */}
      <div style={{ padding: '28px 24px 0' }}>
        <div style={{
          fontSize: 11, letterSpacing: 2.2, textTransform: 'uppercase',
          color: SB_TOKENS.dim, fontWeight: 500, marginBottom: 14,
        }}>Recent activity</div>
        <div style={{
          background: SB_TOKENS.elev, borderRadius: 18, overflow: 'hidden',
          border: '1px solid ' + SB_TOKENS.hairline,
        }}>
          {[
            { icon: 'plus', title: 'Added Obsidian Phoenix', sub: 'BGS 10 · Ashforge', amt: '+$4,120', pos: true, time: '2h' },
            { icon: 'chart', title: 'Celestial Oracle priced', sub: 'Auto-valued at BGS 9.5', amt: '+$326', pos: true, time: '5h' },
            { icon: 'arrow-down', title: 'Abyssal Serpent dropped', sub: 'Market correction', amt: '-$8', pos: false, time: '1d' },
          ].map((r, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', padding: '14px 16px',
              gap: 12, borderBottom: i === arr.length - 1 ? 'none' : '1px solid ' + SB_TOKENS.hairline,
            }}>
              <div style={{
                width: 36, height: 36, borderRadius: 18,
                background: r.pos ? 'oklch(0.78 0.14 155 / 0.14)' : 'oklch(0.68 0.18 25 / 0.14)',
                color: r.pos ? SB_TOKENS.pos : SB_TOKENS.neg,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}><SBIcon name={r.icon} size={16}/></div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, fontWeight: 500, letterSpacing: -0.2 }}>{r.title}</div>
                <div style={{ fontSize: 12, color: SB_TOKENS.dim, marginTop: 2 }}>{r.sub}</div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontFamily: SB_TOKENS.mono, fontSize: 13, fontWeight: 500, color: r.pos ? SB_TOKENS.pos : SB_TOKENS.neg }}>{r.amt}</div>
                <div style={{ fontSize: 11, color: SB_TOKENS.dim, marginTop: 2 }}>{r.time}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// PROFILE — premium settings feel, subtle, grading-house vibes
// ═════════════════════════════════════════════════════════════
function SBProfile() {
  const stats = [
    { label: 'Cards', value: '342' },
    { label: 'Est. value', value: '$12.4k' },
    { label: 'Graded', value: '128' },
  ];
  const sections = [
    {
      label: 'Account', items: [
        { icon: 'crown', title: 'Slabbist Pro', sub: 'Unlimited scans · Market alerts', accent: true },
        { icon: 'layers', title: 'Collections', sub: '3 vaults · 342 cards' },
        { icon: 'shield', title: 'Grading submissions', sub: '2 in transit' },
      ]
    },
    {
      label: 'Scanning', items: [
        { icon: 'flash', title: 'Scan quality', detail: 'Ultra' },
        { icon: 'target', title: 'Grading assist', detail: 'On' },
        { icon: 'bell', title: 'Price alerts', detail: '12 active' },
      ]
    },
    {
      label: 'About', items: [
        { icon: 'info', title: 'Pricing sources', detail: '4' },
        { icon: 'heart', title: 'Rate Slabbist' },
      ]
    },
  ];
  return (
    <div style={{
      position: 'absolute', inset: 0, background: SB_TOKENS.ink, color: SB_TOKENS.text,
      fontFamily: SB_TOKENS.sans, overflow: 'auto', paddingBottom: 110,
    }}>
      <SBStatusBar/>

      {/* Header card */}
      <div style={{ padding: '16px 24px 24px' }}>
        <div style={{
          background: `linear-gradient(150deg, ${SB_TOKENS.elev2}, ${SB_TOKENS.elev})`,
          borderRadius: 24, padding: 20, position: 'relative', overflow: 'hidden',
          border: '1px solid ' + SB_TOKENS.hairline,
        }}>
          {/* gold foil accent */}
          <div style={{
            position: 'absolute', top: -60, right: -60, width: 180, height: 180, borderRadius: '50%',
            background: `radial-gradient(circle, ${SB_TOKENS.gold} 0%, transparent 60%)`,
            opacity: 0.14,
          }}/>

          <div style={{ display: 'flex', gap: 14, alignItems: 'center', position: 'relative' }}>
            <div style={{
              width: 56, height: 56, borderRadius: 28,
              background: `linear-gradient(135deg, ${SB_TOKENS.gold}, ${SB_TOKENS.goldDim})`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontFamily: SB_TOKENS.serif, fontSize: 26, color: SB_TOKENS.ink, fontStyle: 'italic', fontWeight: 600,
              boxShadow: '0 8px 24px rgba(0,0,0,0.3)',
            }}>M</div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 18, fontWeight: 500, letterSpacing: -0.3 }}>Marcus Kwon</div>
              <div style={{ fontSize: 12, color: SB_TOKENS.muted, marginTop: 2, display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ width: 6, height: 6, borderRadius: 3, background: SB_TOKENS.gold }}/>
                Archivist · Since Mar 2023
              </div>
            </div>
          </div>

          <div style={{
            display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)',
            gap: 1, background: SB_TOKENS.hairline, marginTop: 18,
            borderRadius: 14, overflow: 'hidden',
          }}>
            {stats.map(s => (
              <div key={s.label} style={{ padding: '14px 12px', background: SB_TOKENS.elev, textAlign: 'center' }}>
                <div style={{ fontFamily: SB_TOKENS.mono, fontSize: 18, fontWeight: 500, letterSpacing: -0.3 }}>{s.value}</div>
                <div style={{ fontSize: 10, letterSpacing: 1.6, textTransform: 'uppercase', color: SB_TOKENS.dim, marginTop: 4 }}>{s.label}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {sections.map(sec => (
        <div key={sec.label} style={{ padding: '0 24px 24px' }}>
          <div style={{
            fontSize: 11, letterSpacing: 2.2, textTransform: 'uppercase',
            color: SB_TOKENS.dim, fontWeight: 500, marginBottom: 10, padding: '0 6px',
          }}>{sec.label}</div>
          <div style={{
            background: SB_TOKENS.elev, borderRadius: 18, overflow: 'hidden',
            border: '1px solid ' + SB_TOKENS.hairline,
          }}>
            {sec.items.map((it, i, arr) => (
              <div key={it.title} style={{
                display: 'flex', alignItems: 'center', padding: '14px 16px', gap: 12,
                borderBottom: i === arr.length - 1 ? 'none' : '1px solid ' + SB_TOKENS.hairline,
              }}>
                <div style={{
                  width: 34, height: 34, borderRadius: 10,
                  background: it.accent ? `linear-gradient(135deg, ${SB_TOKENS.gold}, ${SB_TOKENS.goldDim})` : SB_TOKENS.elev2,
                  color: it.accent ? SB_TOKENS.ink : SB_TOKENS.text,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  border: it.accent ? 'none' : '1px solid ' + SB_TOKENS.hairline,
                }}><SBIcon name={it.icon} size={16} strokeWidth={1.8}/></div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 14, fontWeight: 500, letterSpacing: -0.15 }}>{it.title}</div>
                  {it.sub && <div style={{ fontSize: 12, color: SB_TOKENS.dim, marginTop: 2 }}>{it.sub}</div>}
                </div>
                {it.detail && <div style={{ fontSize: 13, color: SB_TOKENS.muted, fontFamily: SB_TOKENS.mono }}>{it.detail}</div>}
                <SBIcon name="chevron" size={16} color={SB_TOKENS.dim}/>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

Object.assign(window, { SBStatusBar, SBOnboarding, SBHome, SBProfile });
