/**
 * Portable 32-bit PRNG (mulberry32), bit-exact with
 * app/lib/domain/battle_v3/rng.dart (docs/BATTLE.md §2).
 */

export class Mulberry32 {
  private s: number;

  constructor(seed: number) {
    this.s = seed >>> 0;
  }

  /** Current internal state (uint32). `new Mulberry32(rng.state)` resumes. */
  get state(): number {
    return this.s;
  }

  /** Next uniformly distributed uint32. */
  nextUint32(): number {
    this.s = (this.s + 0x6d2b79f5) >>> 0;
    let t = this.s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return (t ^ (t >>> 14)) >>> 0;
  }

  /** Integer in [0, n): `nextUint32() % n` (1 <= n < 2^31). */
  nextInt(n: number): number {
    if (!Number.isInteger(n) || n < 1) throw new RangeError(`n must be >= 1, got ${n}`);
    return this.nextUint32() % n;
  }
}

/** FNV-1a 32-bit over the UTF-8 bytes of `input`. */
export function fnv1a32(input: string): number {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(input)) {
    h ^= b;
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/**
 * Independent uint32 seed for `stream`:
 * `mulberry32(seed XOR imul(stream + 1, 0x9E3779B1)).next()`.
 * Streams: 0 battle, 1/2 AI a/b, 10 stat jitter, 11 growth, 12 moves,
 * 13 rebirth stats, 14 rebirth moves.
 */
export function deriveSeed(seed: number, stream: number): number {
  return new Mulberry32((seed ^ Math.imul(stream + 1, 0x9e3779b1)) >>> 0).nextUint32();
}
