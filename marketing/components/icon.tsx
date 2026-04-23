import type { SVGProps } from 'react';

export type IconName =
  | 'scan' | 'bolt' | 'check' | 'check-c' | 'arrow' | 'chart' | 'shield' | 'users'
  | 'lock' | 'mail' | 'eye' | 'x' | 'menu' | 'github' | 'sparkle' | 'layers'
  | 'tag' | 'store' | 'zap' | 'receipt' | 'signature' | 'card' | 'reload' | 'flag';

type Props = {
  name: IconName;
  size?: number;
  color?: string;
  sw?: number;
} & Omit<SVGProps<SVGSVGElement>, 'stroke' | 'fill' | 'width' | 'height' | 'viewBox'>;

export function Icon({ name, size = 20, color = 'currentColor', sw = 1.6, ...rest }: Props) {
  const common = {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: color,
    strokeWidth: sw,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    ...rest,
  };
  switch (name) {
    case 'scan':
      return <svg {...common}><path d="M4 8V6a2 2 0 0 1 2-2h2M20 8V6a2 2 0 0 0-2-2h-2M4 16v2a2 2 0 0 0 2 2h2M20 16v2a2 2 0 0 1-2 2h-2M3 12h18"/></svg>;
    case 'bolt':
      return <svg {...common}><path d="M13 2 4 14h7l-1 8 9-12h-7z"/></svg>;
    case 'check':
      return <svg {...common}><path d="m5 13 4 4L19 7"/></svg>;
    case 'check-c':
      return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/></svg>;
    case 'arrow':
      return <svg {...common}><path d="M5 12h14M13 5l7 7-7 7"/></svg>;
    case 'chart':
      return <svg {...common}><path d="M3 17l5-6 4 3 8-10"/><path d="M14 4h7v7"/></svg>;
    case 'shield':
      return <svg {...common}><path d="M12 2 4 6v6c0 5 3.5 8.5 8 10 4.5-1.5 8-5 8-10V6z"/></svg>;
    case 'users':
      return <svg {...common}><circle cx="9" cy="8" r="4"/><path d="M1 21a8 8 0 0 1 16 0M17 11a4 4 0 0 0 0-8M23 21a7 7 0 0 0-5-6.7"/></svg>;
    case 'lock':
      return <svg {...common}><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>;
    case 'mail':
      return <svg {...common}><rect x="2" y="5" width="20" height="14" rx="2"/><path d="m2 7 10 6 10-6"/></svg>;
    case 'eye':
      return <svg {...common}><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>;
    case 'x':
      return <svg {...common}><path d="M18 6 6 18M6 6l12 12"/></svg>;
    case 'menu':
      return <svg {...common}><path d="M3 6h18M3 12h18M3 18h18"/></svg>;
    case 'github':
      return <svg {...common}><path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.9a3.4 3.4 0 0 0-.9-2.6c3-.3 6.1-1.5 6.1-6.6A5.1 5.1 0 0 0 19.9 5a4.7 4.7 0 0 0-.1-3.5S18.5 1 16 2.8a12 12 0 0 0-6.4 0C7.1 1 5.7 1.5 5.7 1.5a4.7 4.7 0 0 0-.1 3.5A5.1 5.1 0 0 0 4 8.9c0 5 3.1 6.2 6 6.6a3.4 3.4 0 0 0-.9 2.5V22"/></svg>;
    case 'sparkle':
      return <svg {...common}><path d="M12 3l2 6 6 2-6 2-2 6-2-6-6-2 6-2z"/></svg>;
    case 'layers':
      return <svg {...common}><path d="m12 2 10 5-10 5L2 7z"/><path d="m2 12 10 5 10-5M2 17l10 5 10-5"/></svg>;
    case 'tag':
      return <svg {...common}><path d="M20 12 12 20l-8-8V4h8z"/><circle cx="8" cy="8" r="1.5"/></svg>;
    case 'store':
      return <svg {...common}><path d="M3 9h18l-2-4H5z M5 9v11h14V9M9 14h6"/></svg>;
    case 'zap':
      return <svg {...common}><path d="m4 14 8-12v10h8l-8 12v-10z"/></svg>;
    case 'receipt':
      return <svg {...common}><path d="M4 2v20l3-2 3 2 3-2 3 2 3-2V2l-3 2-3-2-3 2-3-2z"/><path d="M8 8h8M8 12h8M8 16h5"/></svg>;
    case 'signature':
      return <svg {...common}><path d="M3 18c4 0 5-3 6-6s2-6 4-6 3 3 1 6-3 5 0 5 4-4 4-4M3 22h18"/></svg>;
    case 'card':
      return <svg {...common}><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 10h18M7 15h4"/></svg>;
    case 'reload':
      return <svg {...common}><path d="M21 12a9 9 0 0 1-15 6.7L3 16M3 12a9 9 0 0 1 15-6.7L21 8M3 22v-6h6M21 2v6h-6"/></svg>;
    case 'flag':
      return <svg {...common}><path d="M4 22V4c6-3 8 3 16 0v10c-8 3-10-3-16 0"/></svg>;
    default:
      return null;
  }
}
