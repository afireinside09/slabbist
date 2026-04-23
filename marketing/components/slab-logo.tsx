import { useId } from 'react';
import { SLAB } from '@/lib/tokens';

export type LogoPalette = {
  bg: { a: string; b: string };
  fg: string;
  accent: { a: string; b: string };
};

export const OBSIDIAN_GOLD: LogoPalette = {
  bg: { a: '#1A1A1F', b: '#08080A' },
  fg: '#F4F2ED',
  accent: { a: SLAB.gold, b: SLAB.goldDim },
};

type Props = {
  size?: number;
  palette?: LogoPalette;
  title?: string;
};

/**
 * Capture mark: four scanner brackets around a serif italic S with a
 * horizontal scanline. Chosen for its tech-forward "put the slab in the
 * frame" story and because it holds up at favicon sizes.
 */
export function SlabLogo({ size = 40, palette = OBSIDIAN_GOLD, title }: Props) {
  const id = useId();
  const bgId = `${id}-bg`;
  const goldId = `${id}-gold`;

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 200 200"
      role={title ? 'img' : undefined}
      aria-label={title}
      aria-hidden={title ? undefined : true}
    >
      <defs>
        <linearGradient id={bgId} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={palette.bg.a} />
          <stop offset="1" stopColor={palette.bg.b} />
        </linearGradient>
        <linearGradient id={goldId} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={palette.accent.a} />
          <stop offset="1" stopColor={palette.accent.b} />
        </linearGradient>
      </defs>

      <rect width="200" height="200" rx="44" fill={`url(#${bgId})`} />

      <g
        stroke={`url(#${goldId})`}
        strokeWidth="6"
        strokeLinecap="round"
        fill="none"
      >
        <path d="M 44 70 L 44 44 L 70 44" />
        <path d="M 130 44 L 156 44 L 156 70" />
        <path d="M 156 130 L 156 156 L 130 156" />
        <path d="M 70 156 L 44 156 L 44 130" />
      </g>

      <text
        x="100"
        y="130"
        textAnchor="middle"
        fontFamily={SLAB.serif}
        fontStyle="italic"
        fontWeight="400"
        fontSize="104"
        fill={palette.fg}
        letterSpacing="-2"
      >
        S
      </text>

      <rect
        x="46"
        y="98"
        width="108"
        height="2"
        fill={`url(#${goldId})`}
        opacity="0.5"
      />
    </svg>
  );
}
