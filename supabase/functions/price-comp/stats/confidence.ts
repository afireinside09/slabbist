export function sampleFactor(n: number): number {
  if (n <= 0) return 0;
  if (n >= 10) return 1.0;
  return n / 10;
}

export function freshnessFactor(windowDays: 90 | 365): number {
  if (windowDays === 90) return 1.0;
  return 0.5;
}

export function confidence(n: number, windowDays: 90 | 365): number {
  return sampleFactor(n) * freshnessFactor(windowDays);
}
