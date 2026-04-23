export const SLAB = {
  ink: 'oklch(0.08 0.004 78)',
  surface: 'oklch(0.13 0.005 78)',
  elev: 'oklch(0.17 0.006 78)',
  elev2: 'oklch(0.21 0.007 78)',
  hair: 'oklch(1 0 0 / 0.08)',
  hairStrong: 'oklch(1 0 0 / 0.14)',
  text: 'oklch(0.95 0.006 78)',
  muted: 'oklch(0.95 0.006 78 / 0.72)',
  dim: 'oklch(0.95 0.006 78 / 0.58)',
  gold: 'oklch(0.82 0.13 78)',
  goldDim: 'oklch(0.58 0.09 75)',
  pos: 'oklch(0.78 0.14 155)',
  neg: 'oklch(0.68 0.18 25)',
  serif: 'var(--font-serif)',
  sans: 'var(--font-sans)',
  mono: 'var(--font-mono)',
} as const;

export type SlabToken = typeof SLAB;
