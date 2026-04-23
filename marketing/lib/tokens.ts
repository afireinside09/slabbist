export const SLAB = {
  ink: '#08080A',
  surface: '#0E0E12',
  elev: '#16161B',
  elev2: '#1D1D23',
  hair: 'rgba(255,255,255,0.08)',
  hairStrong: 'rgba(255,255,255,0.14)',
  text: '#F4F2ED',
  muted: 'rgba(244,242,237,0.6)',
  dim: 'rgba(244,242,237,0.38)',
  gold: 'oklch(0.82 0.13 78)',
  goldDim: 'oklch(0.58 0.09 75)',
  pos: 'oklch(0.78 0.14 155)',
  neg: 'oklch(0.68 0.18 25)',
  serif: 'var(--font-serif)',
  sans: 'var(--font-sans)',
  mono: 'var(--font-mono)',
} as const;

export type SlabToken = typeof SLAB;
