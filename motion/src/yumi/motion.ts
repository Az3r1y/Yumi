// Port of Character/YumiMotion.swift: the CSS timing functions, transitions and keyframes
// of design/yumi/maquette/reference.html, so durations and curves are written here as there.

/** A CSS `cubic-bezier(x1, y1, x2, y2)` timing function. */
export type Curve = readonly [number, number, number, number];

export const CURVES = {
  linear: [0, 0, 1, 1],
  ease: [0.25, 0.1, 0.25, 1],
  easeOut: [0, 0, 0.58, 1],
  easeInOut: [0.42, 0, 0.58, 1],
  /** `--spring` of the mock-up: overshoots a little, then settles. */
  spring: [0.32, 1.22, 0.42, 1],
  /** Eyelids and eye scale. */
  lid: [0.3, 1.3, 0.5, 1],
  /** The rim drawing itself when the light comes on. */
  draw: [0.6, 0, 0.2, 1],
} as const satisfies Record<string, Curve>;

export const curve = ([x1, y1, x2, y2]: Curve, p: number): number => {
  if (p <= 0) return 0;
  if (p >= 1) return 1;
  const bezier = (u: number, a: number, b: number) =>
    3 * (1 - u) * (1 - u) * u * a + 3 * (1 - u) * u * u * b + u * u * u;
  // x(u) is monotonic for valid curves: bisect to find u, then read y(u)
  let lo = 0;
  let hi = 1;
  let u = p;
  for (let i = 0; i < 24; i++) {
    const x = bezier(u, x1, x2);
    if (Math.abs(x - p) < 1e-5) break;
    if (x < p) lo = u;
    else hi = u;
    u = (lo + hi) / 2;
  }
  return bezier(u, y1, y2);
};

/**
 * A CSS transition on one number: when the target changes, the value leaves from where
 * it is and reaches the target after `duration`, along `curve`.
 */
export class Transition {
  private from: number;
  private to: number;
  private start = 0;
  private duration = 0;
  private curve: Curve = CURVES.ease;

  constructor(value: number) {
    this.from = value;
    this.to = value;
  }

  set(value: number, now: number, duration: number, c: Curve) {
    if (value === this.to) return;
    this.from = this.value(now);
    this.to = value;
    this.start = now;
    this.duration = duration;
    this.curve = c;
  }

  /** Changes the value at once (`transition: none`). */
  jump(value: number) {
    this.from = value;
    this.to = value;
    this.duration = 0;
  }

  value(now: number): number {
    if (this.duration <= 0) return this.to;
    return (
      this.from +
      (this.to - this.from) * curve(this.curve, (now - this.start) / this.duration)
    );
  }
}

/**
 * CSS keyframes for one property: `stops` are (offset 0…1, value) pairs, and the curve is
 * applied between each pair of neighbours, as `animation-timing-function` does.
 */
export const keyframes = (
  p: number,
  stops: readonly (readonly [number, number])[],
  c: Curve,
): number => {
  const first = stops[0];
  const last = stops[stops.length - 1];
  if (p <= first[0]) return first[1];
  if (p >= last[0]) return last[1];
  for (let i = 1; i < stops.length; i++) {
    if (p <= stops[i][0]) {
      const a = stops[i - 1];
      const b = stops[i];
      const span = b[0] - a[0];
      return span > 0 ? a[1] + (b[1] - a[1]) * curve(c, (p - a[0]) / span) : b[1];
    }
  }
  return last[1];
};

/** A small seeded generator: the same script always gives the same film. */
export const mulberry32 = (seed: number) => {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
};
