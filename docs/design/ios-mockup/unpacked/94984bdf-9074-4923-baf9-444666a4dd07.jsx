// Shared design tokens, icons, and card data

const SB_TOKENS = {
  ink: '#08080A',
  surface: '#101013',
  elev: '#17171B',
  elev2: '#1E1E23',
  hairline: 'rgba(255,255,255,0.08)',
  hairlineStrong: 'rgba(255,255,255,0.14)',
  text: '#F4F2ED',
  muted: 'rgba(244,242,237,0.58)',
  dim: 'rgba(244,242,237,0.36)',
  gold: 'oklch(0.82 0.13 78)',
  goldDim: 'oklch(0.58 0.09 75)',
  goldInk: 'oklch(0.32 0.07 72)',
  pos: 'oklch(0.78 0.14 155)',
  neg: 'oklch(0.68 0.18 25)',
  serif: '"Instrument Serif", "Canela", Georgia, serif',
  sans: '"Inter Tight", "Inter", -apple-system, system-ui, sans-serif',
  mono: '"JetBrains Mono", "SF Mono", ui-monospace, monospace',
};

// Fake inventory — generic trading card themes, no copyrighted IP
const SB_CARDS = [
  { id: 'c01', name: 'Emerald Drake', set: 'Verdant Skies', num: '018/162', year: 2024, grade: 'PSA 10', value: 1284, change: +4.2, hue: 145, tier: 'gem',  rarity: 'Secret Rare' },
  { id: 'c02', name: 'Crimson Valkyrie', set: 'Ashforge', num: '072/110', year: 2023, grade: 'PSA 9',  value: 642,  change: -1.1, hue: 18,  tier: 'mint', rarity: 'Ultra Rare' },
  { id: 'c03', name: 'Celestial Oracle', set: 'Starlit Rift', num: 'SR-04', year: 2025, grade: 'BGS 9.5', value: 2890, change: +12.6, hue: 260, tier: 'gem', rarity: 'Alt Art' },
  { id: 'c04', name: 'Frostbound Wolf', set: 'Tundra Cycle', num: '044/200', year: 2022, grade: 'PSA 10', value: 418, change: +0.4, hue: 200, tier: 'gem', rarity: 'Holo Rare' },
  { id: 'c05', name: 'Abyssal Serpent', set: 'Deepwater', num: '089/180', year: 2024, grade: 'Raw NM',  value: 96,  change: -3.8, hue: 220, tier: 'raw',  rarity: 'Rare' },
  { id: 'c06', name: 'Sunforged Warden', set: 'Ashforge', num: '011/110', year: 2023, grade: 'PSA 9',  value: 340, change: +2.1, hue: 38,  tier: 'mint', rarity: 'Holo Rare' },
  { id: 'c07', name: 'Voidwalker', set: 'Hollow Realm', num: 'SR-11', year: 2025, grade: 'PSA 10', value: 1560, change: +8.9, hue: 290, tier: 'gem', rarity: 'Secret Rare' },
  { id: 'c08', name: 'Thornweave Dryad', set: 'Verdant Skies', num: '101/162', year: 2024, grade: 'PSA 9.5', value: 228, change: +1.3, hue: 120, tier: 'mint', rarity: 'Rare' },
  { id: 'c09', name: 'Obsidian Phoenix', set: 'Ashforge', num: '001/110', year: 2023, grade: 'BGS 10', value: 4120, change: +22.7, hue: 8, tier: 'gem', rarity: 'Grail' },
  { id: 'c10', name: 'Silverleaf Sage', set: 'Tundra Cycle', num: '067/200', year: 2022, grade: 'PSA 10', value: 512, change: -0.6, hue: 175, tier: 'gem', rarity: 'Holo Rare' },
  { id: 'c11', name: 'Runic Hierarch', set: 'Starlit Rift', num: '033/210', year: 2025, grade: 'PSA 9', value: 184, change: +3.4, hue: 42, tier: 'mint', rarity: 'Alt Art' },
  { id: 'c12', name: 'Stormcaller', set: 'Deepwater', num: '012/180', year: 2024, grade: 'Raw NM', value: 74, change: -2.2, hue: 235, tier: 'raw', rarity: 'Rare' },
];

// format USD, using fraktional cents
function sbUSD(n, opts = {}) {
  const { cents = false, compact = false, sign = false } = opts;
  if (compact && Math.abs(n) >= 1000) {
    return '$' + (n / 1000).toFixed(n >= 10000 ? 1 : 2).replace(/\.0$/, '') + 'k';
  }
  const num = cents ? n.toFixed(2) : Math.round(n).toLocaleString('en-US');
  return (sign && n > 0 ? '+' : '') + '$' + num;
}

function sbPct(n) {
  const s = n > 0 ? '+' : '';
  return `${s}${n.toFixed(1)}%`;
}

// Tiny SVG icons — outline, 1.7 stroke, consistent
const SBIcon = ({ name, size = 22, color = 'currentColor', strokeWidth = 1.7 }) => {
  const common = { width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: color, strokeWidth, strokeLinecap: 'round', strokeLinejoin: 'round' };
  switch (name) {
    case 'home': return <svg {...common}><path d="M3 11l9-7 9 7v9a2 2 0 0 1-2 2h-4v-6h-6v6H5a2 2 0 0 1-2-2z"/></svg>;
    case 'scan': return <svg {...common}><path d="M4 8V6a2 2 0 0 1 2-2h2M20 8V6a2 2 0 0 0-2-2h-2M4 16v2a2 2 0 0 0 2 2h2M20 16v2a2 2 0 0 1-2 2h-2M3 12h18"/></svg>;
    case 'grid': return <svg {...common}><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></svg>;
    case 'chart': return <svg {...common}><path d="M3 17l5-6 4 3 8-10"/><path d="M14 4h7v7"/></svg>;
    case 'search': return <svg {...common}><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>;
    case 'user': return <svg {...common}><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>;
    case 'close': return <svg {...common}><path d="M18 6 6 18M6 6l12 12"/></svg>;
    case 'chevron': return <svg {...common}><path d="m9 6 6 6-6 6"/></svg>;
    case 'chevron-left': return <svg {...common}><path d="m15 6-6 6 6 6"/></svg>;
    case 'chevron-down': return <svg {...common}><path d="m6 9 6 6 6-6"/></svg>;
    case 'plus': return <svg {...common}><path d="M12 5v14M5 12h14"/></svg>;
    case 'sparkle': return <svg {...common}><path d="M12 3l2 6 6 2-6 2-2 6-2-6-6-2 6-2z"/></svg>;
    case 'flash': return <svg {...common}><path d="M13 2 4 14h7l-1 8 9-12h-7z"/></svg>;
    case 'bolt-off': return <svg {...common}><path d="M13 2 4 14h7l-1 8 9-12h-7z"/><path d="M3 3l18 18" stroke={color}/></svg>;
    case 'flip': return <svg {...common}><path d="M16 3h5v5M4 21l17-17M8 21H3v-5M20 20L3 3"/></svg>;
    case 'filter': return <svg {...common}><path d="M3 5h18M6 12h12M10 19h4"/></svg>;
    case 'arrow-up': return <svg {...common}><path d="M12 19V5M5 12l7-7 7 7"/></svg>;
    case 'arrow-down': return <svg {...common}><path d="M12 5v14M19 12l-7 7-7-7"/></svg>;
    case 'share': return <svg {...common}><path d="M12 3v12M8 7l4-4 4 4M5 15v4a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-4"/></svg>;
    case 'heart': return <svg {...common}><path d="M20 8.5a5.5 5.5 0 0 0-9.5-3.8l-.5.5-.5-.5A5.5 5.5 0 1 0 2 12.6l7.3 7.3a1 1 0 0 0 1.4 0l7.3-7.3A5.5 5.5 0 0 0 20 8.5z"/></svg>;
    case 'crown': return <svg {...common}><path d="M3 8l4 6 5-8 5 8 4-6v10H3z"/></svg>;
    case 'target': return <svg {...common}><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/></svg>;
    case 'check': return <svg {...common}><path d="m5 13 4 4L19 7"/></svg>;
    case 'mic': return <svg {...common}><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>;
    case 'sort': return <svg {...common}><path d="M3 6h18M6 12h12M9 18h6"/></svg>;
    case 'dots': return <svg {...common}><circle cx="5" cy="12" r="1.3" fill={color}/><circle cx="12" cy="12" r="1.3" fill={color}/><circle cx="19" cy="12" r="1.3" fill={color}/></svg>;
    case 'back': return <svg {...common}><path d="M19 12H5M12 19l-7-7 7-7"/></svg>;
    case 'layers': return <svg {...common}><path d="m12 2 10 5-10 5L2 7z"/><path d="m2 12 10 5 10-5M2 17l10 5 10-5"/></svg>;
    case 'bell': return <svg {...common}><path d="M6 8a6 6 0 1 1 12 0c0 7 3 7 3 9H3c0-2 3-2 3-9M10 21h4"/></svg>;
    case 'shield': return <svg {...common}><path d="M12 2 4 6v6c0 5 3.5 8.5 8 10 4.5-1.5 8-5 8-10V6z"/></svg>;
    case 'info': return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="M12 8v.01M11 12h1v5h1"/></svg>;
    default: return null;
  }
};

// The card placeholder — no real Pokémon imagery, instead stylized generic trading card
function SBCardArt({ card, width = 124, height = 172, radius = 10, glow = true }) {
  const { hue, tier, num, name } = card;
  return (
    <div style={{
      width, height, borderRadius: radius, position: 'relative', overflow: 'hidden',
      background: `linear-gradient(145deg, oklch(0.42 0.14 ${hue}) 0%, oklch(0.22 0.10 ${hue}) 55%, oklch(0.14 0.06 ${hue}) 100%)`,
      boxShadow: glow
        ? `0 10px 28px oklch(0.12 0.08 ${hue} / 0.55), inset 0 0 0 1px rgba(255,255,255,0.1), inset 0 1px 0 rgba(255,255,255,0.18)`
        : `inset 0 0 0 1px rgba(255,255,255,0.08)`,
      flexShrink: 0,
    }}>
      {/* Foil sheen */}
      <div style={{
        position: 'absolute', inset: 0,
        background: `linear-gradient(115deg, transparent 40%, oklch(0.85 0.13 ${hue} / 0.22) 50%, transparent 60%)`,
        mixBlendMode: 'screen',
      }}/>
      {/* Inner frame */}
      <div style={{
        position: 'absolute', inset: width * 0.05, borderRadius: radius * 0.5,
        border: `1px solid oklch(0.62 0.09 ${hue} / 0.5)`,
        boxShadow: `inset 0 0 0 1px oklch(0.18 0.05 ${hue})`,
      }}/>
      {/* Art window */}
      <div style={{
        position: 'absolute',
        left: width * 0.1, right: width * 0.1, top: height * 0.12, height: height * 0.52,
        borderRadius: 4,
        background: `radial-gradient(ellipse at 30% 30%, oklch(0.75 0.16 ${hue}) 0%, oklch(0.4 0.14 ${hue}) 45%, oklch(0.12 0.06 ${hue}) 100%)`,
        overflow: 'hidden',
      }}>
        {/* abstract creature silhouette */}
        <svg width="100%" height="100%" viewBox="0 0 100 100" preserveAspectRatio="none">
          <path d={tier === 'gem'
            ? 'M50 20 L68 38 L76 58 L62 72 L50 86 L38 72 L24 58 L32 38 Z'
            : tier === 'mint'
              ? 'M30 30 Q50 10 70 30 Q80 50 70 72 Q50 86 30 72 Q20 50 30 30 Z'
              : 'M22 50 Q50 22 78 50 Q62 74 50 70 Q38 74 22 50 Z'
          } fill={`oklch(0.12 0.05 ${hue} / 0.8)`} stroke={`oklch(0.92 0.08 ${hue})`} strokeWidth="1"/>
        </svg>
      </div>
      {/* Title bar */}
      <div style={{
        position: 'absolute', left: width * 0.08, right: width * 0.08, top: height * 0.03,
        display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
        fontFamily: SB_TOKENS.serif, fontSize: Math.max(7, width * 0.073), color: 'rgba(255,255,255,0.88)',
        letterSpacing: 0.2,
      }}>
        <span style={{ fontStyle: 'italic' }}>{name.split(' ')[0]}</span>
        <span style={{ fontFamily: SB_TOKENS.mono, fontSize: Math.max(6, width * 0.055), opacity: 0.7 }}>{num}</span>
      </div>
      {/* Bottom text block */}
      <div style={{
        position: 'absolute', left: width * 0.1, right: width * 0.1, top: height * 0.68, height: height * 0.22,
        borderRadius: 3,
        background: `linear-gradient(180deg, oklch(0.22 0.06 ${hue} / 0.85), oklch(0.1 0.04 ${hue} / 0.9))`,
        border: `1px solid oklch(0.45 0.08 ${hue} / 0.4)`,
        padding: width * 0.02,
      }}>
        {[0.35, 0.55, 0.4].map((w, i) => (
          <div key={i} style={{
            height: Math.max(1, height * 0.015), width: `${w * 100}%`, borderRadius: 1,
            background: `oklch(0.7 0.08 ${hue} / 0.55)`, marginTop: i === 0 ? height * 0.03 : height * 0.025,
          }}/>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { SB_TOKENS, SB_CARDS, sbUSD, sbPct, SBIcon, SBCardArt });
