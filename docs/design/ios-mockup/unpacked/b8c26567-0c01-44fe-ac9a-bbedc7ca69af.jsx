// Collection grid, Search, Batch result sheet

// ═════════════════════════════════════════════════════════════
// COLLECTION — grid / list toggle + filter chips
// ═════════════════════════════════════════════════════════════
function SBCollection({ onOpenCard }) {
  const [view, setView] = React.useState('grid');
  const [sort, setSort] = React.useState('value');
  const sorted = [...SB_CARDS].sort((a, b) => {
    if (sort === 'value') return b.value - a.value;
    if (sort === 'change') return b.change - a.change;
    return a.name.localeCompare(b.name);
  });
  const total = sorted.reduce((a, c) => a + c.value, 0);

  return (
    <div style={{
      position: 'absolute', inset: 0, background: SB_TOKENS.ink, color: SB_TOKENS.text,
      fontFamily: SB_TOKENS.sans, overflow: 'auto', paddingBottom: 110,
    }}>
      <SBStatusBar/>

      {/* Header */}
      <div style={{ padding: '8px 24px 20px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
          <div>
            <div style={{ fontSize: 11, letterSpacing: 2.2, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500 }}>Vault</div>
            <h1 style={{ fontFamily: SB_TOKENS.serif, fontSize: 36, fontWeight: 400, letterSpacing: -1, margin: '4px 0 0', lineHeight: 1 }}>Collection</h1>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <button style={{
              width: 40, height: 40, borderRadius: 20, background: SB_TOKENS.elev,
              border: '1px solid ' + SB_TOKENS.hairline, color: SB_TOKENS.text,
              display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
            }}><SBIcon name="filter" size={17}/></button>
          </div>
        </div>

        <div style={{ display: 'flex', gap: 16, marginTop: 18, fontFamily: SB_TOKENS.mono }}>
          <div>
            <div style={{ fontSize: 20, fontWeight: 500, letterSpacing: -0.3 }}>{sorted.length}</div>
            <div style={{ fontSize: 10, color: SB_TOKENS.dim, letterSpacing: 1.4, textTransform: 'uppercase', marginTop: 2 }}>Cards</div>
          </div>
          <div style={{ width: 1, background: SB_TOKENS.hairline }}/>
          <div>
            <div style={{ fontSize: 20, fontWeight: 500, letterSpacing: -0.3 }}>{sbUSD(total, { compact: true })}</div>
            <div style={{ fontSize: 10, color: SB_TOKENS.dim, letterSpacing: 1.4, textTransform: 'uppercase', marginTop: 2 }}>Est. value</div>
          </div>
          <div style={{ width: 1, background: SB_TOKENS.hairline }}/>
          <div>
            <div style={{ fontSize: 20, fontWeight: 500, letterSpacing: -0.3, color: SB_TOKENS.pos }}>+4.1%</div>
            <div style={{ fontSize: 10, color: SB_TOKENS.dim, letterSpacing: 1.4, textTransform: 'uppercase', marginTop: 2 }}>30 days</div>
          </div>
        </div>
      </div>

      {/* Sort chips + view toggle */}
      <div style={{
        display: 'flex', gap: 8, padding: '0 24px 16px', alignItems: 'center',
        overflowX: 'auto', scrollbarWidth: 'none',
      }}>
        {[
          { k: 'value', l: 'Value' }, { k: 'change', l: '% change' }, { k: 'name', l: 'A–Z' },
          { k: 'grade', l: 'Grade' }, { k: 'year', l: 'Year' },
        ].map(s => (
          <button key={s.k} onClick={() => setSort(s.k)} style={{
            padding: '8px 14px', borderRadius: 18, whiteSpace: 'nowrap',
            background: sort === s.k ? SB_TOKENS.text : SB_TOKENS.elev,
            color: sort === s.k ? SB_TOKENS.ink : SB_TOKENS.muted,
            border: '1px solid ' + (sort === s.k ? SB_TOKENS.text : SB_TOKENS.hairline),
            fontFamily: SB_TOKENS.sans, fontSize: 12, fontWeight: 500, cursor: 'pointer',
          }}>{s.l}</button>
        ))}
        <div style={{ flexShrink: 0, marginLeft: 'auto', display: 'flex', padding: 3, background: SB_TOKENS.elev, borderRadius: 10, border: '1px solid ' + SB_TOKENS.hairline }}>
          {['grid', 'list'].map(v => (
            <button key={v} onClick={() => setView(v)} style={{
              width: 32, height: 28, border: 'none', borderRadius: 7,
              background: view === v ? SB_TOKENS.elev2 : 'transparent',
              color: view === v ? SB_TOKENS.text : SB_TOKENS.dim,
              display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
            }}><SBIcon name={v === 'grid' ? 'grid' : 'sort'} size={14}/></button>
          ))}
        </div>
      </div>

      {/* Grid or list */}
      {view === 'grid' ? (
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14,
          padding: '0 20px',
        }}>
          {sorted.map(c => (
            <div key={c.id} onClick={() => onOpenCard(c)} style={{ cursor: 'pointer' }}>
              <div style={{ aspectRatio: '0.72', position: 'relative', borderRadius: 10, overflow: 'hidden' }}>
                <SBCardArt card={c} width={110} height={154} radius={10}/>
                {c.tier === 'gem' && (
                  <div style={{
                    position: 'absolute', top: 6, right: 6, width: 20, height: 20, borderRadius: 10,
                    background: `linear-gradient(135deg, ${SB_TOKENS.gold}, ${SB_TOKENS.goldDim})`,
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    boxShadow: '0 2px 8px rgba(0,0,0,0.3)',
                  }}>
                    <SBIcon name="sparkle" size={11} color={SB_TOKENS.ink} strokeWidth={2.5}/>
                  </div>
                )}
              </div>
              <div style={{ fontSize: 11, color: SB_TOKENS.dim, fontFamily: SB_TOKENS.mono, marginTop: 8 }}>{c.num}</div>
              <div style={{ fontSize: 12, fontWeight: 500, marginTop: 2, lineHeight: 1.2, letterSpacing: -0.1,
                display: '-webkit-box', WebkitLineClamp: 1, WebkitBoxOrient: 'vertical', overflow: 'hidden',
              }}>{c.name}</div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 4 }}>
                <span style={{ fontFamily: SB_TOKENS.mono, fontSize: 12, fontWeight: 500 }}>{sbUSD(c.value, { compact: true })}</span>
                <span style={{ fontFamily: SB_TOKENS.mono, fontSize: 10, color: c.change >= 0 ? SB_TOKENS.pos : SB_TOKENS.neg }}>{sbPct(c.change)}</span>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div style={{ padding: '0 16px' }}>
          <div style={{
            background: SB_TOKENS.elev, borderRadius: 18, overflow: 'hidden',
            border: '1px solid ' + SB_TOKENS.hairline,
          }}>
            {sorted.map((c, i, arr) => (
              <div key={c.id} onClick={() => onOpenCard(c)} style={{
                display: 'flex', alignItems: 'center', padding: '12px 14px', gap: 12,
                borderBottom: i === arr.length - 1 ? 'none' : '1px solid ' + SB_TOKENS.hairline,
                cursor: 'pointer',
              }}>
                <SBCardArt card={c} width={40} height={56} radius={4} glow={false}/>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 13, fontWeight: 500, letterSpacing: -0.15, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.name}</div>
                  <div style={{ fontSize: 11, color: SB_TOKENS.dim, fontFamily: SB_TOKENS.mono, marginTop: 2 }}>{c.num} · {c.grade}</div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div style={{ fontFamily: SB_TOKENS.mono, fontSize: 13, fontWeight: 500 }}>{sbUSD(c.value)}</div>
                  <div style={{ fontFamily: SB_TOKENS.mono, fontSize: 11, color: c.change >= 0 ? SB_TOKENS.pos : SB_TOKENS.neg, marginTop: 2 }}>{sbPct(c.change)}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// SEARCH
// ═════════════════════════════════════════════════════════════
function SBSearch({ onOpenCard }) {
  const [q, setQ] = React.useState('');
  const results = q ? SB_CARDS.filter(c =>
    c.name.toLowerCase().includes(q.toLowerCase()) || c.set.toLowerCase().includes(q.toLowerCase())
  ) : [];

  const trending = [SB_CARDS[8], SB_CARDS[2], SB_CARDS[6], SB_CARDS[0]];
  const recent = ['Obsidian Phoenix', 'Ashforge holos', 'BGS 10 cards'];

  return (
    <div style={{
      position: 'absolute', inset: 0, background: SB_TOKENS.ink, color: SB_TOKENS.text,
      fontFamily: SB_TOKENS.sans, overflow: 'auto', paddingBottom: 110,
    }}>
      <SBStatusBar/>

      <div style={{ padding: '8px 20px 20px' }}>
        <h1 style={{ fontFamily: SB_TOKENS.serif, fontSize: 36, fontWeight: 400, letterSpacing: -1, margin: '0 4px 16px', lineHeight: 1 }}>Search</h1>

        {/* Search field */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          background: SB_TOKENS.elev, borderRadius: 14, padding: '0 14px',
          border: '1px solid ' + SB_TOKENS.hairlineStrong, height: 50,
        }}>
          <SBIcon name="search" size={18} color={SB_TOKENS.muted}/>
          <input value={q} onChange={e => setQ(e.target.value)}
            placeholder="Card, set, or serial #"
            style={{
              flex: 1, background: 'transparent', border: 'none', outline: 'none',
              color: SB_TOKENS.text, fontFamily: SB_TOKENS.sans, fontSize: 15, letterSpacing: -0.2,
            }}/>
          <button style={{
            width: 32, height: 32, borderRadius: 16, background: SB_TOKENS.elev2,
            border: 'none', color: SB_TOKENS.gold,
            display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
          }}><SBIcon name="mic" size={14}/></button>
        </div>
      </div>

      {q === '' && (
        <>
          {/* Trending */}
          <div style={{ padding: '0 24px' }}>
            <div style={{ fontSize: 11, letterSpacing: 2.2, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500, marginBottom: 14 }}>
              Trending today
            </div>
          </div>
          <div style={{ display: 'flex', gap: 12, overflow: 'auto', padding: '0 20px 20px', scrollbarWidth: 'none' }}>
            {trending.map((c, i) => (
              <div key={c.id} onClick={() => onOpenCard(c)} style={{
                width: 130, flexShrink: 0, background: SB_TOKENS.elev,
                borderRadius: 16, padding: 12, cursor: 'pointer',
                border: '1px solid ' + SB_TOKENS.hairline, position: 'relative',
              }}>
                <div style={{
                  position: 'absolute', top: 10, left: 10, fontSize: 10,
                  fontFamily: SB_TOKENS.mono, color: SB_TOKENS.gold, letterSpacing: 1,
                }}>#{(i + 1).toString().padStart(2, '0')}</div>
                <div style={{ display: 'flex', justifyContent: 'center', margin: '14px 0 8px' }}>
                  <SBCardArt card={c} width={72} height={100} radius={6} glow={false}/>
                </div>
                <div style={{ fontSize: 12, fontWeight: 500, letterSpacing: -0.1, lineHeight: 1.2,
                  whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.name}</div>
                <div style={{ fontFamily: SB_TOKENS.mono, fontSize: 11, color: SB_TOKENS.pos, marginTop: 4 }}>{sbPct(c.change)}</div>
              </div>
            ))}
          </div>

          {/* Recent searches */}
          <div style={{ padding: '0 24px 12px' }}>
            <div style={{ fontSize: 11, letterSpacing: 2.2, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500, marginBottom: 14 }}>
              Recent
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {recent.map(r => (
                <button key={r} onClick={() => setQ(r)} style={{
                  padding: '10px 14px', borderRadius: 20,
                  background: SB_TOKENS.elev, border: '1px solid ' + SB_TOKENS.hairline,
                  color: SB_TOKENS.text, fontFamily: SB_TOKENS.sans, fontSize: 13, cursor: 'pointer',
                }}>{r}</button>
              ))}
            </div>
          </div>

          {/* Browse by set */}
          <div style={{ padding: '12px 24px 0' }}>
            <div style={{ fontSize: 11, letterSpacing: 2.2, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500, marginBottom: 14 }}>
              Browse by set
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
              {['Ashforge', 'Verdant Skies', 'Starlit Rift', 'Tundra Cycle'].map((s, i) => {
                const hue = [18, 145, 260, 200][i];
                return (
                  <div key={s} style={{
                    borderRadius: 14, padding: 14, height: 86, position: 'relative', overflow: 'hidden',
                    background: `linear-gradient(135deg, oklch(0.32 0.12 ${hue}), oklch(0.14 0.05 ${hue}))`,
                    border: '1px solid ' + SB_TOKENS.hairlineStrong, cursor: 'pointer',
                  }}>
                    <div style={{ fontFamily: SB_TOKENS.serif, fontSize: 18, fontWeight: 400, letterSpacing: -0.3, fontStyle: 'italic' }}>{s}</div>
                    <div style={{ position: 'absolute', bottom: 10, left: 14, fontSize: 10, fontFamily: SB_TOKENS.mono, color: 'rgba(255,255,255,0.6)', letterSpacing: 0.5 }}>
                      {[110, 162, 210, 200][i]} cards
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </>
      )}

      {q && results.length > 0 && (
        <div style={{ padding: '0 16px' }}>
          <div style={{
            background: SB_TOKENS.elev, borderRadius: 18, overflow: 'hidden',
            border: '1px solid ' + SB_TOKENS.hairline,
          }}>
            {results.map((c, i, arr) => (
              <div key={c.id} onClick={() => onOpenCard(c)} style={{
                display: 'flex', alignItems: 'center', padding: '12px 14px', gap: 12,
                borderBottom: i === arr.length - 1 ? 'none' : '1px solid ' + SB_TOKENS.hairline,
                cursor: 'pointer',
              }}>
                <SBCardArt card={c} width={40} height={56} radius={4} glow={false}/>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14, fontWeight: 500, letterSpacing: -0.15 }}>{c.name}</div>
                  <div style={{ fontSize: 11, color: SB_TOKENS.dim, fontFamily: SB_TOKENS.mono, marginTop: 2 }}>{c.set} · {c.grade}</div>
                </div>
                <div style={{ fontFamily: SB_TOKENS.mono, fontSize: 13, fontWeight: 500 }}>{sbUSD(c.value, { compact: true })}</div>
              </div>
            ))}
          </div>
        </div>
      )}

      {q && results.length === 0 && (
        <div style={{ padding: '40px 24px', textAlign: 'center', color: SB_TOKENS.muted }}>
          No matches for "{q}"
        </div>
      )}
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// BATCH RESULT — summary after a batch scan
// ═════════════════════════════════════════════════════════════
function SBBatchResult({ cards, onDone, onOpenCard }) {
  const total = cards.reduce((a, c) => a + c.value, 0);
  const gems = cards.filter(c => c.tier === 'gem').length;

  return (
    <div style={{
      position: 'absolute', inset: 0, background: SB_TOKENS.ink, color: SB_TOKENS.text,
      fontFamily: SB_TOKENS.sans, overflow: 'auto', paddingBottom: 110,
    }}>
      <SBStatusBar/>

      <div style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 16px' }}>
        <button onClick={onDone} style={{
          width: 40, height: 40, borderRadius: 20, background: SB_TOKENS.elev,
          border: '1px solid ' + SB_TOKENS.hairline, color: SB_TOKENS.text,
          display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
        }}><SBIcon name="close" size={18}/></button>
        <button style={{
          padding: '0 14px', height: 40, borderRadius: 20,
          background: SB_TOKENS.gold, color: SB_TOKENS.ink, border: 'none',
          fontFamily: SB_TOKENS.sans, fontSize: 13, fontWeight: 600, cursor: 'pointer',
        }}>Save to vault</button>
      </div>

      {/* Big total */}
      <div style={{ padding: '24px 24px 28px', textAlign: 'center', position: 'relative' }}>
        <div style={{
          position: 'absolute', top: -20, left: '50%', transform: 'translateX(-50%)',
          width: 280, height: 200, borderRadius: '50%',
          background: `radial-gradient(circle, ${SB_TOKENS.gold} 0%, transparent 60%)`,
          opacity: 0.14, filter: 'blur(40px)', zIndex: 0,
        }}/>
        <div style={{ position: 'relative' }}>
          <div style={{ fontSize: 11, letterSpacing: 2.4, textTransform: 'uppercase', color: SB_TOKENS.dim, fontWeight: 500 }}>
            Scan complete
          </div>
          <div style={{
            fontFamily: SB_TOKENS.serif, fontSize: 68, lineHeight: 1, letterSpacing: -2, fontWeight: 400,
            marginTop: 12, display: 'flex', alignItems: 'baseline', justifyContent: 'center',
          }}>
            <span style={{ fontSize: 36, opacity: 0.5 }}>$</span>
            {Math.round(total).toLocaleString('en-US')}
          </div>
          <div style={{ display: 'flex', gap: 20, justifyContent: 'center', marginTop: 16, fontFamily: SB_TOKENS.mono }}>
            <div>
              <div style={{ fontSize: 18, fontWeight: 500 }}>{cards.length}</div>
              <div style={{ fontSize: 10, color: SB_TOKENS.dim, letterSpacing: 1.4, textTransform: 'uppercase', marginTop: 2 }}>Cards</div>
            </div>
            <div style={{ width: 1, background: SB_TOKENS.hairline }}/>
            <div>
              <div style={{ fontSize: 18, fontWeight: 500, color: SB_TOKENS.gold }}>{gems}</div>
              <div style={{ fontSize: 10, color: SB_TOKENS.dim, letterSpacing: 1.4, textTransform: 'uppercase', marginTop: 2 }}>Gems</div>
            </div>
            <div style={{ width: 1, background: SB_TOKENS.hairline }}/>
            <div>
              <div style={{ fontSize: 18, fontWeight: 500, color: SB_TOKENS.pos }}>98%</div>
              <div style={{ fontSize: 10, color: SB_TOKENS.dim, letterSpacing: 1.4, textTransform: 'uppercase', marginTop: 2 }}>Confidence</div>
            </div>
          </div>
        </div>
      </div>

      {/* Card list */}
      <div style={{ padding: '0 16px' }}>
        <div style={{
          background: SB_TOKENS.elev, borderRadius: 20, overflow: 'hidden',
          border: '1px solid ' + SB_TOKENS.hairline,
        }}>
          {cards.map((c, i) => (
            <div key={`${c.id}-${i}`} onClick={() => onOpenCard(c)} style={{
              display: 'flex', alignItems: 'center', padding: '14px 14px', gap: 12,
              borderBottom: i === cards.length - 1 ? 'none' : '1px solid ' + SB_TOKENS.hairline,
              cursor: 'pointer',
              animation: `sbBRIn 0.5s ${i * 0.08}s cubic-bezier(0.2, 0.9, 0.3, 1.1) backwards`,
            }}>
              <div style={{
                width: 22, fontFamily: SB_TOKENS.mono, fontSize: 11, color: SB_TOKENS.dim,
              }}>{String(i + 1).padStart(2, '0')}</div>
              <SBCardArt card={c} width={44} height={62} radius={5} glow={false}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 500, letterSpacing: -0.15 }}>{c.name}</div>
                <div style={{ fontSize: 11, color: SB_TOKENS.dim, fontFamily: SB_TOKENS.mono, marginTop: 2 }}>
                  {c.grade} · {c.num}
                </div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontFamily: SB_TOKENS.mono, fontSize: 14, fontWeight: 500 }}>{sbUSD(c.value)}</div>
                <div style={{ fontSize: 10, color: SB_TOKENS.gold, letterSpacing: 1, textTransform: 'uppercase', marginTop: 2, fontWeight: 500 }}>
                  Identified
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      <style>{`@keyframes sbBRIn { from { opacity: 0; transform: translateY(8px) } to { opacity: 1; transform: translateY(0) } }`}</style>
    </div>
  );
}

Object.assign(window, { SBCollection, SBSearch, SBBatchResult });
