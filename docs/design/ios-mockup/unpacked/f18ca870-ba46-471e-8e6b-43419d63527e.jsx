// Scan (AR overlay + batch), Card Detail, Price Chart

// ═════════════════════════════════════════════════════════════
// SCAN — AR overlay with pinned price tags + batch tally
// ═════════════════════════════════════════════════════════════
function SBScan({ onClose, onBatchDone }) {
  const [mode, setMode] = React.useState('ar'); // 'ar' | 'batch'
  const [scanned, setScanned] = React.useState([]); // cards captured
  const [pulse, setPulse] = React.useState(false);
  const [flashOn, setFlashOn] = React.useState(false);

  // AR pins — 3 cards visible in viewfinder, fake positions
  const arCards = [
    { card: SB_CARDS[8], x: 28, y: 30, rot: -7, w: 128, h: 178, conf: 98 },
    { card: SB_CARDS[2], x: 56, y: 46, rot: 3, w: 112, h: 156, conf: 94 },
    { card: SB_CARDS[6], x: 18, y: 62, rot: -2, w: 108, h: 150, conf: 91 },
  ];

  // Simulate auto-batch capture
  React.useEffect(() => {
    if (mode !== 'batch') return;
    if (scanned.length >= 5) return;
    const t = setTimeout(() => {
      setPulse(true);
      setTimeout(() => setPulse(false), 400);
      setScanned(s => [...s, SB_CARDS[(s.length * 3 + 1) % SB_CARDS.length]]);
    }, 1200);
    return () => clearTimeout(t);
  }, [mode, scanned]);

  const totalValue = scanned.reduce((a, c) => a + c.value, 0);

  return (
    <div style={{
      position: 'absolute', inset: 0, background: '#050505', color: SB_TOKENS.text,
      fontFamily: SB_TOKENS.sans, overflow: 'hidden',
    }}>
      {/* Simulated camera viewfinder — dark gradient + grain */}
      <div style={{
        position: 'absolute', inset: 0,
        background: `
          radial-gradient(ellipse 80% 60% at 50% 30%, #1a1a1f 0%, #0b0b0d 60%, #050505 100%),
          linear-gradient(180deg, #0a0a0d 0%, #000 100%)
        `,
      }}/>
      {/* grain */}
      <div style={{
        position: 'absolute', inset: 0, opacity: 0.06, pointerEvents: 'none',
        backgroundImage: `url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='100' height='100'><filter id='n'><feTurbulence baseFrequency='0.9' numOctaves='2'/></filter><rect width='100' height='100' filter='url(%23n)'/></svg>")`,
      }}/>

      {/* Table surface / soft wood shadow */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, height: '45%',
        background: 'linear-gradient(180deg, transparent, rgba(60,40,20,0.22))',
      }}/>

      <SBStatusBar/>

      {/* Top bar */}
      <div style={{
        position: 'absolute', top: 50, left: 0, right: 0, padding: '0 16px', zIndex: 30,
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      }}>
        <button onClick={onClose} style={{
          width: 40, height: 40, borderRadius: 20,
          background: 'rgba(10,10,12,0.6)', backdropFilter: 'blur(20px)',
          border: '1px solid rgba(255,255,255,0.12)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: SB_TOKENS.text, cursor: 'pointer',
        }}><SBIcon name="close" size={18}/></button>

        {/* Mode toggle pill */}
        <div style={{
          display: 'flex', padding: 4, borderRadius: 22,
          background: 'rgba(10,10,12,0.6)', backdropFilter: 'blur(20px)',
          border: '1px solid rgba(255,255,255,0.12)',
        }}>
          {[{k:'ar',l:'AR Overlay'},{k:'batch',l:'Batch'}].map(m => (
            <button key={m.k} onClick={() => { setMode(m.k); if (m.k === 'ar') setScanned([]); }} style={{
              padding: '8px 14px', borderRadius: 18, border: 'none',
              background: mode === m.k ? SB_TOKENS.gold : 'transparent',
              color: mode === m.k ? SB_TOKENS.ink : SB_TOKENS.text,
              fontFamily: SB_TOKENS.sans, fontSize: 12, fontWeight: 600, cursor: 'pointer',
              letterSpacing: -0.1, whiteSpace: 'nowrap',
            }}>{m.l}</button>
          ))}
        </div>

        <button onClick={() => setFlashOn(!flashOn)} style={{
          width: 40, height: 40, borderRadius: 20,
          background: flashOn ? SB_TOKENS.gold : 'rgba(10,10,12,0.6)',
          backdropFilter: 'blur(20px)',
          border: '1px solid rgba(255,255,255,0.12)',
          color: flashOn ? SB_TOKENS.ink : SB_TOKENS.text,
          display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
        }}><SBIcon name={flashOn ? 'flash' : 'bolt-off'} size={16}/></button>
      </div>

      {/* AR mode: cards in viewfinder with pinned price tags */}
      {mode === 'ar' && arCards.map(({ card, x, y, rot, w, h, conf }, i) => (
        <React.Fragment key={card.id}>
          {/* card silhouette */}
          <div style={{
            position: 'absolute', left: `${x}%`, top: `${y}%`,
            transform: `rotate(${rot}deg)`,
            filter: 'brightness(0.95) contrast(1.05)',
            animation: `sbFloat${i} 4s ease-in-out infinite alternate`,
          }}>
            <SBCardArt card={card} width={w} height={h} radius={w * 0.055}/>
            {/* Corner brackets — AR detection */}
            {[[0,0],[1,0],[0,1],[1,1]].map(([px, py], j) => (
              <svg key={j} width="22" height="22" style={{
                position: 'absolute',
                left: px ? w - 11 : -11, top: py ? h - 11 : -11,
                transform: `rotate(${j * 90}deg)`,
              }}>
                <path d="M2 2 L12 2 M2 2 L2 12" stroke={SB_TOKENS.gold} strokeWidth="2" strokeLinecap="round" fill="none"/>
              </svg>
            ))}
          </div>
          {/* Price pin */}
          <div style={{
            position: 'absolute',
            left: `calc(${x}% + ${w/2 - 54}px)`,
            top: `calc(${y}% - 46px)`,
            transform: `rotate(${rot * 0.2}deg)`,
            animation: `sbPinBob 2.5s ease-in-out infinite alternate`,
            zIndex: 20,
          }}>
            <div style={{
              padding: '8px 12px', borderRadius: 14,
              background: 'rgba(10,10,12,0.82)', backdropFilter: 'blur(20px)',
              border: '1px solid ' + SB_TOKENS.gold + '66',
              display: 'flex', alignItems: 'center', gap: 8,
              boxShadow: `0 8px 22px rgba(0,0,0,0.4), 0 0 0 2px ${SB_TOKENS.gold}14`,
            }}>
              <div style={{ width: 6, height: 6, borderRadius: 3, background: SB_TOKENS.gold, boxShadow: `0 0 10px ${SB_TOKENS.gold}` }}/>
              <div>
                <div style={{ fontFamily: SB_TOKENS.mono, fontSize: 14, fontWeight: 600, letterSpacing: -0.2 }}>{sbUSD(card.value, { compact: true })}</div>
                <div style={{ fontSize: 9, color: SB_TOKENS.muted, letterSpacing: 0.6, textTransform: 'uppercase', marginTop: 1 }}>{card.grade} · {conf}%</div>
              </div>
            </div>
            {/* pointer tail */}
            <svg width="12" height="10" style={{ position: 'absolute', left: 20, bottom: -8 }}>
              <path d="M0 0 L6 9 L12 0 Z" fill="rgba(10,10,12,0.82)" stroke={SB_TOKENS.gold + '66'} strokeWidth="1"/>
            </svg>
          </div>
        </React.Fragment>
      ))}

      {/* Batch mode: single framing target */}
      {mode === 'batch' && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{
            position: 'relative', width: 230, height: 320,
            animation: pulse ? 'sbPulseFlash 0.4s ease-out' : 'none',
          }}>
            {/* framing corners */}
            {[[0,0,0],[1,0,90],[1,1,180],[0,1,270]].map(([px,py,r], j) => (
              <svg key={j} width="36" height="36" style={{
                position: 'absolute',
                left: px ? 'calc(100% - 36px)' : 0,
                top: py ? 'calc(100% - 36px)' : 0,
                transform: `rotate(${r}deg)`,
              }}>
                <path d="M2 2 L2 18 M2 2 L18 2" stroke={pulse ? '#fff' : SB_TOKENS.gold}
                  strokeWidth="3" strokeLinecap="round" fill="none"/>
              </svg>
            ))}
            {/* scan line */}
            <div style={{
              position: 'absolute', left: 8, right: 8, height: 2,
              background: `linear-gradient(90deg, transparent, ${SB_TOKENS.gold}, transparent)`,
              animation: 'sbScanLine 2s linear infinite',
              boxShadow: `0 0 14px ${SB_TOKENS.gold}`,
            }}/>
            {/* current card being captured */}
            {scanned.length < 5 && (
              <div style={{
                position: 'absolute', inset: 20, opacity: 0.5,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <SBCardArt card={SB_CARDS[(scanned.length * 3 + 1) % SB_CARDS.length]} width={180} height={250} radius={10}/>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Bottom sheet */}
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 40,
        background: 'linear-gradient(180deg, transparent, rgba(0,0,0,0.85) 30%)',
        paddingTop: 60, paddingBottom: 34,
      }}>
        {mode === 'batch' && (
          <div style={{ padding: '0 20px 16px' }}>
            {/* live tally */}
            <div style={{
              background: 'rgba(14,14,16,0.7)', backdropFilter: 'blur(24px)',
              border: '1px solid ' + SB_TOKENS.hairlineStrong, borderRadius: 22, padding: 16,
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 }}>
                <div>
                  <div style={{ fontSize: 11, letterSpacing: 2, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500 }}>Batch total</div>
                  <div style={{ fontFamily: SB_TOKENS.serif, fontSize: 36, fontWeight: 400, letterSpacing: -1, marginTop: 4, lineHeight: 1,
                    transition: 'all 0.35s cubic-bezier(0.2, 0.9, 0.3, 1.1)',
                    color: pulse ? SB_TOKENS.gold : SB_TOKENS.text,
                  }}>{sbUSD(totalValue)}</div>
                </div>
                <div style={{
                  fontFamily: SB_TOKENS.mono, fontSize: 28, fontWeight: 500,
                  color: SB_TOKENS.gold, letterSpacing: -0.5,
                }}>{scanned.length.toString().padStart(2, '0')}</div>
              </div>
              {/* scanned row */}
              <div style={{ display: 'flex', gap: 6, overflow: 'auto', scrollbarWidth: 'none', paddingBottom: 4 }}>
                {scanned.map((c, i) => (
                  <div key={i} style={{
                    animation: i === scanned.length - 1 ? 'sbSlideIn 0.4s cubic-bezier(0.2, 0.9, 0.3, 1.1)' : 'none',
                    flexShrink: 0,
                  }}>
                    <SBCardArt card={c} width={38} height={52} radius={4} glow={false}/>
                  </div>
                ))}
                {Array.from({ length: Math.max(0, 6 - scanned.length) }).map((_, i) => (
                  <div key={`s${i}`} style={{
                    width: 38, height: 52, borderRadius: 4,
                    border: '1px dashed ' + SB_TOKENS.hairlineStrong, flexShrink: 0,
                  }}/>
                ))}
              </div>
            </div>
          </div>
        )}

        {mode === 'ar' && (
          <div style={{ textAlign: 'center', padding: '0 32px 20px' }}>
            <div style={{
              display: 'inline-flex', padding: '6px 12px', borderRadius: 20,
              background: 'rgba(14,14,16,0.7)', backdropFilter: 'blur(20px)',
              border: '1px solid ' + SB_TOKENS.hairlineStrong,
              fontSize: 12, color: SB_TOKENS.muted, gap: 8, alignItems: 'center',
            }}>
              <span style={{ width: 6, height: 6, borderRadius: 3, background: SB_TOKENS.pos, boxShadow: `0 0 8px ${SB_TOKENS.pos}` }}/>
              Tracking {arCards.length} cards · Live prices
            </div>
          </div>
        )}

        {/* Shutter row */}
        <div style={{
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          padding: '0 36px',
        }}>
          {/* gallery thumb */}
          <div style={{
            width: 44, height: 44, borderRadius: 12,
            background: SB_TOKENS.elev, border: '1px solid ' + SB_TOKENS.hairline,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}><SBIcon name="layers" size={18} color={SB_TOKENS.muted}/></div>

          <button onClick={() => {
            if (mode === 'batch' && scanned.length > 0) onBatchDone(scanned);
            if (mode === 'ar') {
              setPulse(true);
              setTimeout(() => setPulse(false), 400);
            }
          }} style={{
            width: 76, height: 76, borderRadius: 38,
            background: 'transparent', border: `3px solid ${SB_TOKENS.gold}`,
            padding: 4, cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <div style={{
              width: '100%', height: '100%', borderRadius: '50%',
              background: `radial-gradient(circle at 35% 35%, oklch(0.9 0.13 78), ${SB_TOKENS.gold} 60%, ${SB_TOKENS.goldDim} 100%)`,
              boxShadow: `inset 0 -6px 14px rgba(0,0,0,0.3), 0 0 24px ${SB_TOKENS.gold}44`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              {mode === 'batch' && scanned.length > 0 && (
                <span style={{ fontFamily: SB_TOKENS.mono, fontSize: 16, color: SB_TOKENS.ink, fontWeight: 600 }}>
                  <SBIcon name="check" size={24} strokeWidth={2.5} color={SB_TOKENS.ink}/>
                </span>
              )}
            </div>
          </button>

          <div style={{
            width: 44, height: 44, borderRadius: 22,
            background: SB_TOKENS.elev, border: '1px solid ' + SB_TOKENS.hairline,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}><SBIcon name="flip" size={18} color={SB_TOKENS.muted}/></div>
        </div>

        <div style={{ textAlign: 'center', marginTop: 12, fontSize: 11, color: SB_TOKENS.dim, letterSpacing: 1.6, textTransform: 'uppercase' }}>
          {mode === 'batch' ? 'Hold steady · Auto-captures when framed' : 'Tap to freeze prices'}
        </div>
      </div>

      <style>{`
        @keyframes sbFloat0 { from { transform: rotate(-7deg) translateY(0) } to { transform: rotate(-7deg) translateY(-4px) } }
        @keyframes sbFloat1 { from { transform: rotate(3deg) translateY(-2px) } to { transform: rotate(3deg) translateY(2px) } }
        @keyframes sbFloat2 { from { transform: rotate(-2deg) translateY(3px) } to { transform: rotate(-2deg) translateY(-3px) } }
        @keyframes sbPinBob { from { transform: translateY(0) } to { transform: translateY(-3px) } }
        @keyframes sbScanLine { 0% { top: 8px } 50% { top: calc(100% - 10px) } 100% { top: 8px } }
        @keyframes sbPulseFlash { 0%, 100% { transform: scale(1) } 50% { transform: scale(1.03) } }
        @keyframes sbSlideIn { from { transform: translateX(-20px) scale(0.7); opacity: 0 } to { transform: translateX(0) scale(1); opacity: 1 } }
      `}</style>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// CARD DETAIL
// ═════════════════════════════════════════════════════════════
function SBCardDetail({ card, onBack, onOpenChart }) {
  if (!card) return null;

  return (
    <div style={{
      position: 'absolute', inset: 0, background: SB_TOKENS.ink, color: SB_TOKENS.text,
      fontFamily: SB_TOKENS.sans, overflow: 'auto', paddingBottom: 110,
    }}>
      <SBStatusBar/>

      {/* ambient glow behind card */}
      <div style={{
        position: 'absolute', top: 60, left: '50%', transform: 'translateX(-50%)',
        width: 300, height: 300, borderRadius: '50%',
        background: `radial-gradient(circle, oklch(0.5 0.14 ${card.hue}) 0%, transparent 60%)`,
        opacity: 0.35, filter: 'blur(30px)',
      }}/>

      {/* top bar */}
      <div style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 16px', position: 'relative' }}>
        <button onClick={onBack} style={{
          width: 40, height: 40, borderRadius: 20,
          background: SB_TOKENS.elev, border: '1px solid ' + SB_TOKENS.hairline,
          color: SB_TOKENS.text, display: 'flex', alignItems: 'center', justifyContent: 'center',
          cursor: 'pointer',
        }}><SBIcon name="chevron-left" size={18}/></button>
        <div style={{ display: 'flex', gap: 8 }}>
          <button style={{ width: 40, height: 40, borderRadius: 20, background: SB_TOKENS.elev, border: '1px solid ' + SB_TOKENS.hairline, color: SB_TOKENS.text, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}><SBIcon name="heart" size={18}/></button>
          <button style={{ width: 40, height: 40, borderRadius: 20, background: SB_TOKENS.elev, border: '1px solid ' + SB_TOKENS.hairline, color: SB_TOKENS.text, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}><SBIcon name="share" size={18}/></button>
        </div>
      </div>

      {/* hero card */}
      <div style={{ display: 'flex', justifyContent: 'center', padding: '18px 0 28px', position: 'relative' }}>
        <div style={{ transform: 'rotate(-3deg)' }}>
          <SBCardArt card={card} width={208} height={290} radius={14}/>
        </div>
      </div>

      {/* Title block */}
      <div style={{ padding: '0 24px' }}>
        <div style={{
          display: 'flex', gap: 8, alignItems: 'center',
          fontSize: 11, letterSpacing: 2, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500, marginBottom: 8,
        }}>
          <span>{card.set}</span>
          <span>·</span>
          <span style={{ color: SB_TOKENS.gold }}>{card.rarity}</span>
        </div>
        <h1 style={{
          fontFamily: SB_TOKENS.serif, fontSize: 40, lineHeight: 1, letterSpacing: -1, fontWeight: 400,
          margin: 0,
        }}>{card.name}</h1>
        <div style={{
          marginTop: 10, fontFamily: SB_TOKENS.mono, fontSize: 12, color: SB_TOKENS.muted,
          display: 'flex', gap: 14,
        }}>
          <span>#{card.num}</span>
          <span>·</span>
          <span>{card.year}</span>
          <span>·</span>
          <span style={{
            color: SB_TOKENS.gold, padding: '2px 8px', border: `1px solid ${SB_TOKENS.gold}44`,
            borderRadius: 4, fontSize: 10, letterSpacing: 1, textTransform: 'uppercase', fontWeight: 500,
          }}>{card.grade}</span>
        </div>
      </div>

      {/* Value block */}
      <div style={{ padding: '28px 24px 20px' }}>
        <div style={{
          background: SB_TOKENS.elev, borderRadius: 22, padding: 20,
          border: '1px solid ' + SB_TOKENS.hairline,
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
            <div style={{ fontSize: 11, letterSpacing: 2, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500 }}>Market value</div>
            <div style={{
              fontSize: 10, letterSpacing: 1.4, textTransform: 'uppercase',
              color: SB_TOKENS.pos, padding: '3px 8px', borderRadius: 6,
              background: 'oklch(0.78 0.14 155 / 0.14)', fontWeight: 600,
            }}>Live</div>
          </div>
          <div style={{
            fontFamily: SB_TOKENS.serif, fontSize: 58, lineHeight: 1, letterSpacing: -2, fontWeight: 400,
            display: 'flex', alignItems: 'baseline',
          }}>
            <span style={{ fontSize: 30, opacity: 0.5, marginRight: 4 }}>$</span>
            {card.value.toLocaleString('en-US')}
          </div>
          <div style={{
            display: 'flex', gap: 10, alignItems: 'center', marginTop: 10,
            fontFamily: SB_TOKENS.mono, fontSize: 13,
          }}>
            <span style={{ color: card.change >= 0 ? SB_TOKENS.pos : SB_TOKENS.neg, display: 'flex', alignItems: 'center', gap: 3 }}>
              <SBIcon name={card.change >= 0 ? 'arrow-up' : 'arrow-down'} size={13} strokeWidth={2.5}/>
              {sbPct(card.change)}
            </span>
            <span style={{ color: SB_TOKENS.dim, fontSize: 11 }}>30d · updated 4m ago</span>
          </div>

          {/* inline chart preview */}
          <div onClick={onOpenChart} style={{ marginTop: 18, cursor: 'pointer' }}>
            <svg width="100%" height="64" viewBox="0 0 300 64" preserveAspectRatio="none">
              <defs>
                <linearGradient id="cd-fill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor={SB_TOKENS.gold} stopOpacity="0.3"/>
                  <stop offset="100%" stopColor={SB_TOKENS.gold} stopOpacity="0"/>
                </linearGradient>
              </defs>
              {(() => {
                const pts = [36, 34, 40, 38, 44, 42, 48, 46, 52, 50, 56, 54, 58, 55, 60, 58, 50, 56, 52, 48, 54, 50, 44, 48, 46, 50, 48, 52, 55, 56];
                const d = `M ${pts.map((v, i) => `${(i/(pts.length-1))*300} ${64 - v}`).join(' L ')}`;
                return <>
                  <path d={`${d} L 300 64 L 0 64 Z`} fill="url(#cd-fill)"/>
                  <path d={d} fill="none" stroke={SB_TOKENS.gold} strokeWidth="1.5"/>
                </>;
              })()}
            </svg>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: SB_TOKENS.mono, fontSize: 10, color: SB_TOKENS.dim, marginTop: 4 }}>
              <span>Apr 2024</span>
              <span>Tap to expand →</span>
              <span>Today</span>
            </div>
          </div>
        </div>
      </div>

      {/* Comps */}
      <div style={{ padding: '0 24px 16px' }}>
        <div style={{ fontSize: 11, letterSpacing: 2, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500, marginBottom: 10, padding: '0 6px' }}>
          Recent comps
        </div>
        <div style={{
          background: SB_TOKENS.elev, borderRadius: 18, overflow: 'hidden',
          border: '1px solid ' + SB_TOKENS.hairline,
        }}>
          {[
            { src: 'eBay auction', date: 'Apr 18', price: 1299, grade: 'PSA 10' },
            { src: 'Goldin Marketplace', date: 'Apr 12', price: 1275, grade: 'PSA 10' },
            { src: 'PWCC Vault', date: 'Apr 04', price: 1320, grade: 'PSA 10' },
          ].map((r, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', padding: '13px 16px', gap: 12,
              borderBottom: i === arr.length - 1 ? 'none' : '1px solid ' + SB_TOKENS.hairline,
            }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, fontWeight: 500, letterSpacing: -0.15 }}>{r.src}</div>
                <div style={{ fontSize: 12, color: SB_TOKENS.dim, marginTop: 2 }}>{r.date} · {r.grade}</div>
              </div>
              <div style={{ fontFamily: SB_TOKENS.mono, fontSize: 14, fontWeight: 500 }}>{sbUSD(r.price)}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Specs grid */}
      <div style={{ padding: '0 24px 24px' }}>
        <div style={{ fontSize: 11, letterSpacing: 2, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500, marginBottom: 10, padding: '0 6px' }}>
          Details
        </div>
        <div style={{
          background: SB_TOKENS.elev, borderRadius: 18,
          border: '1px solid ' + SB_TOKENS.hairline, padding: 4,
          display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 1,
          backgroundColor: SB_TOKENS.hairline,
        }}>
          {[
            ['Grade', card.grade], ['Population', '1,248'],
            ['Print run', '± 8,400'], ['First release', 'Jun 2024'],
            ['Serial', `#${card.num}`], ['Language', 'English'],
          ].map(([k, v]) => (
            <div key={k} style={{ padding: '14px 16px', background: SB_TOKENS.elev }}>
              <div style={{ fontSize: 10, letterSpacing: 1.6, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500 }}>{k}</div>
              <div style={{ fontSize: 14, fontFamily: SB_TOKENS.mono, fontWeight: 500, marginTop: 4, letterSpacing: -0.2 }}>{v}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// PRICE CHART — full screen detail for a card
// ═════════════════════════════════════════════════════════════
function SBPriceChart({ card, onBack }) {
  const [range, setRange] = React.useState('6M');
  const [hoverIdx, setHoverIdx] = React.useState(20);

  // Synthesize chart data based on card
  const pts = React.useMemo(() => {
    const n = 60;
    const arr = [];
    const seed = (card?.hue || 100);
    for (let i = 0; i < n; i++) {
      const t = i / (n - 1);
      const wave = Math.sin(i * 0.4 + seed * 0.1) * 0.15 + Math.cos(i * 0.23) * 0.08;
      const trend = (card?.change || 5) > 0 ? t * 0.35 : -t * 0.15;
      arr.push(0.55 + wave + trend);
    }
    return arr;
  }, [card]);

  const W = 340, H = 200, PAD = 20;
  const maxV = Math.max(...pts), minV = Math.min(...pts);
  const xy = (i, v) => [PAD + (i / (pts.length - 1)) * (W - PAD * 2), PAD + (1 - (v - minV) / (maxV - minV)) * (H - PAD * 2)];
  const pathD = pts.map((v, i) => { const [x, y] = xy(i, v); return `${i === 0 ? 'M' : 'L'} ${x.toFixed(1)} ${y.toFixed(1)}`; }).join(' ');

  const hoverPrice = (card?.value || 1000) * pts[hoverIdx] / pts[pts.length - 1];
  const [hx, hy] = xy(hoverIdx, pts[hoverIdx]);

  // key events to annotate
  const events = [
    { i: 12, label: 'Set released', sub: 'Jun 2024' },
    { i: 32, label: 'Grading pop +240', sub: 'Oct 2024' },
    { i: 50, label: 'TikTok viral', sub: 'Mar 2025' },
  ];

  return (
    <div style={{
      position: 'absolute', inset: 0, background: SB_TOKENS.ink, color: SB_TOKENS.text,
      fontFamily: SB_TOKENS.sans, overflow: 'auto', paddingBottom: 110,
    }}>
      <SBStatusBar/>
      <div style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 16px' }}>
        <button onClick={onBack} style={{
          width: 40, height: 40, borderRadius: 20, background: SB_TOKENS.elev,
          border: '1px solid ' + SB_TOKENS.hairline, color: SB_TOKENS.text,
          display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
        }}><SBIcon name="chevron-left" size={18}/></button>
        <button style={{
          padding: '0 14px', height: 40, borderRadius: 20, background: SB_TOKENS.elev,
          border: '1px solid ' + SB_TOKENS.hairline, color: SB_TOKENS.text,
          display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer',
          fontFamily: SB_TOKENS.sans, fontSize: 13, fontWeight: 500,
        }}>
          <SBIcon name="bell" size={14}/> Set alert
        </button>
      </div>

      <div style={{ padding: '14px 24px 0' }}>
        <div style={{ fontSize: 11, letterSpacing: 2, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500, marginBottom: 6 }}>
          {card?.name || 'Obsidian Phoenix'} · {card?.grade || 'BGS 10'}
        </div>
        <div style={{
          fontFamily: SB_TOKENS.serif, fontSize: 54, lineHeight: 1, letterSpacing: -1.5, fontWeight: 400,
          display: 'flex', alignItems: 'baseline',
        }}>
          <span style={{ fontSize: 28, opacity: 0.5, marginRight: 4 }}>$</span>
          {Math.round(hoverPrice).toLocaleString('en-US')}
        </div>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginTop: 10, fontFamily: SB_TOKENS.mono, fontSize: 13 }}>
          <span style={{ color: SB_TOKENS.pos }}>+$318 · +8.4%</span>
          <span style={{ color: SB_TOKENS.dim, fontSize: 11 }}>{range}</span>
        </div>
      </div>

      {/* chart */}
      <div style={{ padding: '20px 10px 0', position: 'relative' }}>
        <svg width="100%" viewBox={`0 0 ${W} ${H + 40}`} preserveAspectRatio="xMidYMid meet"
          onMouseMove={e => {
            const rect = e.currentTarget.getBoundingClientRect();
            const x = ((e.clientX - rect.left) / rect.width) * W;
            const i = Math.max(0, Math.min(pts.length - 1, Math.round(((x - PAD) / (W - PAD * 2)) * (pts.length - 1))));
            setHoverIdx(i);
          }}>
          <defs>
            <linearGradient id="pc-fill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={SB_TOKENS.gold} stopOpacity="0.32"/>
              <stop offset="100%" stopColor={SB_TOKENS.gold} stopOpacity="0"/>
            </linearGradient>
          </defs>
          {/* grid lines */}
          {[0, 0.25, 0.5, 0.75, 1].map(t => (
            <line key={t} x1={PAD} x2={W - PAD} y1={PAD + t * (H - PAD * 2)} y2={PAD + t * (H - PAD * 2)}
              stroke="rgba(255,255,255,0.04)" strokeDasharray="2 4"/>
          ))}
          {/* fill */}
          <path d={`${pathD} L ${W - PAD} ${H - PAD} L ${PAD} ${H - PAD} Z`} fill="url(#pc-fill)"/>
          {/* line */}
          <path d={pathD} fill="none" stroke={SB_TOKENS.gold} strokeWidth="2" strokeLinecap="round"/>
          {/* events */}
          {events.map(ev => {
            const [ex, ey] = xy(ev.i, pts[ev.i]);
            return (
              <g key={ev.i}>
                <line x1={ex} x2={ex} y1={ey + 6} y2={H - PAD} stroke="rgba(255,255,255,0.1)" strokeDasharray="2 3"/>
                <circle cx={ex} cy={ey} r="4" fill={SB_TOKENS.ink} stroke={SB_TOKENS.gold} strokeWidth="1.5"/>
              </g>
            );
          })}
          {/* hover crosshair */}
          <line x1={hx} x2={hx} y1={PAD} y2={H - PAD} stroke={SB_TOKENS.text} strokeOpacity="0.25" strokeWidth="1"/>
          <circle cx={hx} cy={hy} r="6" fill={SB_TOKENS.ink} stroke={SB_TOKENS.gold} strokeWidth="2"/>
          <circle cx={hx} cy={hy} r="10" fill={SB_TOKENS.gold} fillOpacity="0.18"/>
        </svg>
      </div>

      {/* range picker */}
      <div style={{ padding: '16px 24px 24px' }}>
        <div style={{
          display: 'flex', background: SB_TOKENS.elev, borderRadius: 12,
          border: '1px solid ' + SB_TOKENS.hairline, padding: 4,
        }}>
          {['1W', '1M', '3M', '6M', '1Y', 'ALL'].map(r => (
            <button key={r} onClick={() => setRange(r)} style={{
              flex: 1, padding: '10px 0', border: 'none',
              background: range === r ? SB_TOKENS.elev2 : 'transparent',
              color: range === r ? SB_TOKENS.text : SB_TOKENS.dim,
              borderRadius: 8, fontFamily: SB_TOKENS.mono, fontSize: 12, fontWeight: 500,
              cursor: 'pointer', letterSpacing: 0.5,
            }}>{r}</button>
          ))}
        </div>
      </div>

      {/* Key events */}
      <div style={{ padding: '0 24px' }}>
        <div style={{ fontSize: 11, letterSpacing: 2, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500, marginBottom: 10, padding: '0 6px' }}>
          Key events
        </div>
        <div style={{
          background: SB_TOKENS.elev, borderRadius: 18, overflow: 'hidden',
          border: '1px solid ' + SB_TOKENS.hairline,
        }}>
          {events.map((e, i, arr) => (
            <div key={e.i} style={{
              display: 'flex', alignItems: 'center', padding: '14px 16px', gap: 12,
              borderBottom: i === arr.length - 1 ? 'none' : '1px solid ' + SB_TOKENS.hairline,
            }}>
              <div style={{
                width: 34, height: 34, borderRadius: 10,
                background: SB_TOKENS.elev2, border: '1px solid ' + SB_TOKENS.hairlineStrong,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontFamily: SB_TOKENS.mono, fontSize: 12, color: SB_TOKENS.gold,
              }}>{String.fromCharCode(65 + i)}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, fontWeight: 500, letterSpacing: -0.15 }}>{e.label}</div>
                <div style={{ fontSize: 12, color: SB_TOKENS.dim, marginTop: 2 }}>{e.sub}</div>
              </div>
              <div style={{ fontFamily: SB_TOKENS.mono, fontSize: 12, color: SB_TOKENS.pos }}>+{(12 + i * 6)}%</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { SBScan, SBCardDetail, SBPriceChart });
